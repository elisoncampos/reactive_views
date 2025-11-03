# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tree Rendering Integration', type: :request do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = 'http://localhost:5175'
      config.tree_rendering_enabled = true
    end
  end

  describe 'nested component rendering' do
    it 'sends tree structure to render-tree endpoint' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Outer').and_return('/path/to/Outer.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Inner').and_return('/path/to/Inner.tsx')

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 200, body: { html: '<div>Outer with Inner</div>' }.to_json)

      html = '<Outer><Inner /></Outer>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('Outer with Inner')
      expect(WebMock).to have_requested(:post, 'http://localhost:5175/render-tree').once
    end

    it 'preserves component order in tree' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Parent').and_return('/path/to/Parent.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Child1').and_return('/path/to/Child1.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Child2').and_return('/path/to/Child2.tsx')

      stub_request(:post, 'http://localhost:5175/render-tree')
        .with(body: hash_including('componentPath' => '/path/to/Parent.tsx'))
        .to_return(status: 200, body: { html: '<div>Parent with children</div>' }.to_json)

      html = '<Parent><Child1 /><Child2 /></Parent>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('Parent with children')
    end

    it 'handles deeply nested components' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 200, body: { html: '<div>Deeply nested</div>' }.to_json)

      html = '<Level1><Level2><Level3 /></Level2></Level1>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('Deeply nested')
    end

    it 'warns about excessive nesting depth' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')
      allow(Rails).to receive(:logger).and_return(double(warn: nil, error: nil))

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 200, body: { html: '<div>Deep</div>' }.to_json)

      # Create a deeply nested structure (depth > 3)
      html = '<L1><L2><L3><L4 /></L3></L2></L1>'
      ReactiveViews::TagTransformer.transform(html)

      expect(Rails.logger).to have_received(:warn).with(/nesting depth/)
    end
  end

  describe 'children props' do
    it 'passes HTML children alongside component children via tree' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub = stub_request(:post, 'http://localhost:5175/render-tree')
        .with { |req|
          body = JSON.parse(req.body)
          body['htmlChildren'].to_s.include?('Hello')
        }
        .to_return(status: 200, body: { html: '<div>Container with children</div>' }.to_json)

      html = '<Container><div>Hello World</div><ChildComponent /></Container>'
      ReactiveViews::TagTransformer.transform(html)

      expect(stub).to have_been_requested
    end

    it 'handles mixed HTML and component children' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 200, body: { html: '<div>Mixed content</div>' }.to_json)

      html = '<Parent><div>Text</div><Child /></Parent>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('Mixed content')
    end

    it 'handles components with no children' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Empty').and_return('/path/to/Empty.tsx')

      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(status: 200, body: {
          results: [{ html: '<div>Empty component</div>' }]
        }.to_json)

      html = '<Empty />'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('Empty component')
    end
  end

  describe 'error handling' do
    it 'shows error overlay when tree rendering fails' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')
      allow(Rails).to receive(:env).and_return(double(development?: true))

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 500, body: { error: 'Rendering failed' }.to_json)

      html = '<Broken><Child /></Broken>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('ReactiveViews SSR Error')
      expect(result).to include('Rendering failed')
    end

    it 'handles component resolution failure in tree' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Parent').and_return('/path/to/Parent.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('Missing').and_return(nil)
      allow(Rails).to receive(:env).and_return(double(development?: true))

      html = '<Parent><Missing /></Parent>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(result).to include('ReactiveViews SSR Error')
      expect(result).to include('Missing')
    end
  end

  describe 'adaptive strategy' do
    it 'uses batch rendering for flat layouts' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(status: 200, body: {
          results: [
            { html: '<div>Component 1</div>' },
            { html: '<div>Component 2</div>' }
          ]
        }.to_json)

      html = '<Component1 /><Component2 />'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
      expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/render-tree')
    end

    it 'uses tree rendering for nested layouts' do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub_request(:post, 'http://localhost:5175/render-tree')
        .to_return(status: 200, body: { html: '<div>Nested</div>' }.to_json)

      html = '<Parent><Child /></Parent>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(WebMock).to have_requested(:post, 'http://localhost:5175/render-tree').once
      expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/batch-render')
    end

    it 'falls back to batch rendering when tree rendering is disabled' do
      ReactiveViews.config.tree_rendering_enabled = false

      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(status: 200, body: {
          results: [
            { html: '<div>Parent</div>' },
            { html: '<div>Child</div>' }
          ]
        }.to_json)

      html = '<Parent><Child /></Parent>'
      result = ReactiveViews::TagTransformer.transform(html)

      expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
      expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/render-tree')
    end
  end
end
