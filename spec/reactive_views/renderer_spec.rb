# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views'

RSpec.describe ReactiveViews::Renderer do
  let(:component_name) { 'TestComponent' }
  let(:props) { { message: 'Hello', count: 42 } }

  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = 'http://localhost:5175'
      config.ssr_timeout = 5
      config.component_views_paths = ['app/views/components']
      config.component_js_paths = ['app/javascript/components']
    end
  end

  describe '.render' do
    context 'when component cannot be resolved' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(nil)
      end

      it 'returns error marker' do
        result = described_class.render(component_name, props)
        expect(result).to start_with('___REACTIVE_VIEWS_ERROR___')
      end

      it 'includes error message in marker with searched paths' do
        result = described_class.render(component_name, props)
        expect(result).to include('not found')
        expect(result).to include('Searched in:')
      end
    end

    context 'when SSR server is available' do
      let(:component_path) { '/path/to/TestComponent.tsx' }
      let(:ssr_response) { { 'html' => '<div>SSR Content</div>', 'error' => nil }.to_json }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, 'http://localhost:5175/render')
          .with(
            body: hash_including(
              'componentPath' => component_path,
              'props' => props
            )
          )
          .to_return(status: 200, body: ssr_response)
      end

      it 'makes POST request to SSR server' do
        described_class.render(component_name, props)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render')
      end

      it 'sends component path and props' do
        described_class.render(component_name, props)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render')
          .with(body: hash_including('componentPath' => component_path))
      end

      it 'returns rendered HTML' do
        result = described_class.render(component_name, props)
        expect(result).to eq('<div>SSR Content</div>')
      end
    end

    context 'when SSR server returns error' do
      let(:component_path) { '/path/to/TestComponent.tsx' }
      let(:error_response) { { 'html' => nil, 'error' => 'Render failed' }.to_json }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 200, body: error_response)
      end

      it 'returns error marker' do
        result = described_class.render(component_name, props)
        expect(result).to start_with('___REACTIVE_VIEWS_ERROR___')
      end

      it 'includes server error message' do
        result = described_class.render(component_name, props)
        expect(result).to include('Render failed')
      end
    end

    context 'when SSR server is unavailable' do
      let(:component_path) { '/path/to/TestComponent.tsx' }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, 'http://localhost:5175/render')
          .to_timeout
      end

      it 'returns error marker' do
        result = described_class.render(component_name, props)
        expect(result).to start_with('___REACTIVE_VIEWS_ERROR___')
      end

      it 'includes timeout error' do
        result = described_class.render(component_name, props)
        expect(result).to match(/timed out|timeout|unavailable/i)
      end
    end

    context 'when SSR server returns non-200 status' do
      let(:component_path) { '/path/to/TestComponent.tsx' }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns error marker' do
        result = described_class.render(component_name, props)
        expect(result).to start_with('___REACTIVE_VIEWS_ERROR___')
      end
    end
  end

  describe '.batch_render' do
    let(:component_specs) do
      [
        { uuid: 'uuid-1', component_name: 'Component1', props: { title: 'First' } },
        { uuid: 'uuid-2', component_name: 'Component2', props: { title: 'Second' } },
        { uuid: 'uuid-3', component_name: 'Component3', props: { title: 'Third' } }
      ]
    end

    context 'with multiple components' do
      let(:batch_response) do
        {
          'results' => [
            { 'html' => '<div>Component 1</div>' },
            { 'html' => '<div>Component 2</div>' },
            { 'html' => '<div>Component 3</div>' }
          ]
        }.to_json
      end

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component1').and_return('/path/to/Component1.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component2').and_return('/path/to/Component2.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component3').and_return('/path/to/Component3.tsx')

        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: batch_response)
      end

      it 'makes single POST request to batch-render endpoint' do
        described_class.batch_render(component_specs)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
      end

      it 'sends all components in one request' do
        described_class.batch_render(component_specs)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render')
          .with(body: hash_including('components'))
      end

      it 'returns array of results in same order' do
        results = described_class.batch_render(component_specs)

        expect(results).to be_an(Array)
        expect(results.size).to eq(3)
        expect(results[0]).to have_key(:html)
        expect(results[1]).to have_key(:html)
        expect(results[2]).to have_key(:html)
      end

      it 'includes HTML for each component' do
        results = described_class.batch_render(component_specs)

        expect(results[0][:html]).to eq('<div>Component 1</div>')
        expect(results[1][:html]).to eq('<div>Component 2</div>')
        expect(results[2][:html]).to eq('<div>Component 3</div>')
      end
    end

    context 'when component cannot be resolved' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component1').and_return('/path/to/Component1.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component2').and_return(nil) # Can't be resolved
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component3').and_return('/path/to/Component3.tsx')
      end

      it 'returns error for unresolved component' do
        results = described_class.batch_render(component_specs)

        expect(results[1]).to have_key(:error)
        expect(results[1][:error]).to include('not found')
      end

      it 'still processes other components' do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: {
            'results' => [
              { 'html' => '<div>Component 1</div>' },
              { 'html' => '<div>Component 3</div>' }
            ]
          }.to_json)

        results = described_class.batch_render(component_specs)

        expect(results[0]).to have_key(:html)
        expect(results[2]).to have_key(:html)
      end
    end

    context 'when batch request fails' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 500, body: 'Server Error')
      end

      it 'falls back to individual rendering' do
        # Stub individual render endpoints
        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 200, body: { 'html' => '<div>Fallback</div>' }.to_json)

        results = described_class.batch_render(component_specs)

        # Should have made 1 batch request + 3 individual fallback requests
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render').times(3)
      end

      it 'returns results from fallback rendering' do
        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 200, body: { 'html' => '<div>Fallback</div>' }.to_json)

        results = described_class.batch_render(component_specs)

        expect(results.size).to eq(3)
        expect(results.all? { |r| r[:html] == '<div>Fallback</div>' }).to be true
      end
    end

    context 'when batch request times out' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_timeout
      end

      it 'falls back to individual rendering' do
        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 200, body: { 'html' => '<div>Fallback</div>' }.to_json)

        results = described_class.batch_render(component_specs)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render').times(3)
      end
    end

    context 'with empty component specs array' do
      it 'returns empty array' do
        results = described_class.batch_render([])
        expect(results).to eq([])
      end

      it 'does not make any HTTP requests' do
        described_class.batch_render([])
        expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/batch-render')
      end
    end

    context 'with partial batch failure' do
      let(:batch_response) do
        {
          'results' => [
            { 'html' => '<div>Success</div>' },
            { 'error' => 'Component 2 failed to render' },
            { 'html' => '<div>Success</div>' }
          ]
        }.to_json
      end

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: batch_response)
      end

      it 'returns mixed results' do
        results = described_class.batch_render(component_specs)

        expect(results[0]).to have_key(:html)
        expect(results[1]).to have_key(:error)
        expect(results[2]).to have_key(:html)
      end

      it 'preserves order of results' do
        results = described_class.batch_render(component_specs)

        expect(results[0][:html]).to eq('<div>Success</div>')
        expect(results[1][:error]).to eq('Component 2 failed to render')
        expect(results[2][:html]).to eq('<div>Success</div>')
      end
    end
  end
end
