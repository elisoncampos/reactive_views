# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multiple Islands Rendering', type: :request do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
    end
  end

  describe 'rendering multiple components on one page' do
    before do
      # Mock component resolution
      allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_call_original
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('HelloWorld').and_return('/path/to/hello_world.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('ProductList').and_return('/path/to/product_list.tsx')

      # Mock SSR server to return unique content for each component
      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(
          status: 200,
          body: {
            results: [
              { html: '<div>Hello World SSR</div>' },
              { html: '<div>Product List SSR</div>' }
            ]
          }.to_json
        )
    end

    it 'renders all component islands' do
      # Simulate a page with multiple components
      html = <<~HTML
        <div>
          <HelloWorld />
          <ProductList data='[{"id":1}]' />
        </div>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Both components should be transformed
      expect(transformed).to include('data-component="HelloWorld"')
      expect(transformed).to include('data-component="ProductList"')
    end

    it 'includes props script tags for all components with props' do
      html = <<~HTML
        <html><body><div>
          <HelloWorld name="Test" />
          <ProductList data='[{"id":1}]' />
        </div></body></html>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Count script tags with props
      script_tags = transformed.scan(/script.*data-island-uuid/i).size
      expect(script_tags).to eq(2)

      # Scripts should be aggregated at the end (after all components)
      last_component_pos = transformed.rindex('data-component=')
      first_script_pos = transformed.index('<script')
      expect(first_script_pos).to be > last_component_pos
    end

    it 'assigns unique UUIDs to each island' do
      html = <<~HTML
        <div>
          <HelloWorld />
          <ProductList data='[]' />
        </div>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Extract all UUIDs (avoid brittle regex matching on quote style)
      doc = Nokogiri::HTML.fragment(transformed)
      uuids = doc.css('[data-island-uuid]').map { |n| n['data-island-uuid'] }.compact

      # HelloWorld has no props, so only 1 script tag (for ProductList)
      # Should have 3 UUIDs: 2 for div containers, 1 for ProductList script tag
      expect(uuids.size).to eq(3)

      # 2 unique UUIDs: one for HelloWorld (div only), one for ProductList (div + script)
      expect(uuids.uniq.size).to eq(2)
    end

    it 'preserves order of components' do
      html = <<~HTML
        <div>
          <HelloWorld />
          <ProductList data='[]' />
          <HelloWorld />
        </div>
      HTML

      # Need to stub for 3 components since the before block only stubs for 2
      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(
          status: 200,
          body: {
            results: [
              { html: '<div>Hello World SSR</div>' },
              { html: '<div>Product List SSR</div>' },
              { html: '<div>Hello World SSR</div>' }
            ]
          }.to_json
        )

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Extract component names in order
      components = transformed.scan(/data-component="([^"]+)"/).flatten

      expect(components).to eq(%w[HelloWorld ProductList HelloWorld])
    end
  end

  describe 'handling errors in multi-component pages' do
    before do
      # Mock component resolution
      allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_call_original
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('HelloWorld').and_return('/path/to/hello_world.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('ProductList').and_return('/path/to/product_list.tsx')
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .with('AnotherComponent').and_return('/path/to/another_component.tsx')

      # Mock batch rendering with mixed success/failure
      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(
          status: 200,
          body: {
            results: [
              { html: '<div>Success</div>' },
              { error: 'Rendering failed' }
            ]
          }.to_json
        )
    end

    it 'renders successful components even when others fail' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

      html = <<~HTML
        <div>
          <HelloWorld />
          <ProductList data='[]' />
        </div>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Successful component should be in the output
      expect(transformed).to include('data-component="HelloWorld"')

      # Failed component should show error overlay
      expect(transformed).to include('ReactiveViews SSR Error')
      expect(transformed).to include('ProductList')
    end

    it 'does not stop processing after first error' do
      # Mock batch rendering with 3 components: success, error, success
      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(
          status: 200,
          body: {
            results: [
              { html: '<div>Success</div>' },
              { error: 'Rendering failed' },
              { html: '<div>Another Success</div>' }
            ]
          }.to_json
        )

      html = <<~HTML
        <div>
          <HelloWorld />
          <ProductList data='[]' />
          <AnotherComponent />
        </div>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # First component should render
      expect(transformed).to include('data-component="HelloWorld"')

      # Second component should show error
      expect(transformed).to include('data-reactive-views-error')

      # Third component should still render despite second failing
      expect(transformed).to include('data-component="AnotherComponent"')
    end
  end

  describe 'props serialization for multiple components' do
    before do
      # Mock component resolution for all components
      allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_call_original
      %w[Component1 Component2 Component3 Component4 Component5].each do |comp|
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with(comp).and_return("/path/to/#{comp}.tsx")
      end

      # Mock batch rendering to return success for all components
      stub_request(:post, 'http://localhost:5175/batch-render')
        .to_return(
          status: 200,
          body: {
            results: [
              { html: '<div>Rendered1</div>' },
              { html: '<div>Rendered2</div>' },
              { html: '<div>Rendered3</div>' },
              { html: '<div>Rendered4</div>' },
              { html: '<div>Rendered5</div>' }
            ]
          }.to_json
        )
    end

    it 'properly serializes different prop types' do
      html = <<~HTML
        <html><body><div>
          <Component1 string="hello" />
          <Component2 number="42" />
          <Component3 array='[1,2,3]' />
          <Component4 object='{"key":"value"}' />
          <Component5 bool="true" />
        </div></body></html>
      HTML

      transformed = ReactiveViews::TagTransformer.transform(html)

      # Check that all components were processed
      expect(transformed).to include('data-component="Component1"')
      expect(transformed).to include('data-component="Component2"')
      expect(transformed).to include('data-component="Component3"')
      expect(transformed).to include('data-component="Component4"')
      expect(transformed).to include('data-component="Component5"')

      # Verify props are in script tags
      expect(transformed).to include('"string":"hello"')
      expect(transformed).to include('"number":42')
      expect(transformed).to include('"array":[1,2,3]')
      expect(transformed).to include('"object":{"key":"value"}')
      expect(transformed).to include('"bool":true')

      # Scripts should be aggregated at the end (after all components)
      last_component_pos = transformed.rindex('data-component=')
      first_script_pos = transformed.index('<script')
      expect(first_script_pos).to be > last_component_pos
    end
  end
end
