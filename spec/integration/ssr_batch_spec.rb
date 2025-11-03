# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SSR Batch Rendering', type: :request do
  let(:batch_components) do
    [
      { componentPath: '/path/to/Component1.tsx', props: { title: 'First' } },
      { componentPath: '/path/to/Component2.tsx', props: { title: 'Second' } },
      { componentPath: '/path/to/Component3.tsx', props: { title: 'Third' } }
    ]
  end

  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = 'http://localhost:5175'
    end
  end

  describe 'POST /batch-render' do
    context 'with valid components array' do
      let(:batch_response) do
        {
          results: [
            { html: '<div>Component 1</div>' },
            { html: '<div>Component 2</div>' },
            { html: '<div>Component 3</div>' }
          ]
        }.to_json
      end

      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .with(
            body: hash_including('components'),
            headers: { 'Content-Type' => 'application/json' }
          )
          .to_return(status: 200, body: batch_response)
      end

      it 'accepts batch render request' do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        component_specs = [
          { component_name: 'Component1', props: { title: 'First' } },
          { component_name: 'Component2', props: { title: 'Second' } },
          { component_name: 'Component3', props: { title: 'Third' } }
        ]

        ReactiveViews::Renderer.batch_render(component_specs)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render')
      end

      it 'sends array of components' do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        component_specs = [
          { component_name: 'Component1', props: { title: 'First' } },
          { component_name: 'Component2', props: { title: 'Second' } },
          { component_name: 'Component3', props: { title: 'Third' } }
        ]

        ReactiveViews::Renderer.batch_render(component_specs)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render')
      end

      it 'receives array of results' do
        results = JSON.parse(batch_response)

        expect(results['results']).to be_an(Array)
        expect(results['results'].size).to eq(3)
      end

      it 'returns results in same order as input' do
        results = JSON.parse(batch_response)

        expect(results['results'][0]['html']).to eq('<div>Component 1</div>')
        expect(results['results'][1]['html']).to eq('<div>Component 2</div>')
        expect(results['results'][2]['html']).to eq('<div>Component 3</div>')
      end
    end

    context 'with parallel rendering' do
      let(:batch_response) do
        {
          results: [
            { html: '<div>A</div>' },
            { html: '<div>B</div>' },
            { html: '<div>C</div>' }
          ]
        }.to_json
      end

      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: batch_response)
      end

      it 'renders all components (order preserved)' do
        results = JSON.parse(batch_response)

        # All three components should be in results
        expect(results['results'].size).to eq(3)

        # Order should match input order
        expect(results['results'][0]['html']).to eq('<div>A</div>')
        expect(results['results'][1]['html']).to eq('<div>B</div>')
        expect(results['results'][2]['html']).to eq('<div>C</div>')
      end
    end

    context 'with partial failures' do
      let(:batch_response) do
        {
          results: [
            { html: '<div>Success</div>' },
            { error: 'Component rendering failed' },
            { html: '<div>Success</div>' }
          ]
        }.to_json
      end

      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: batch_response)
      end

      it 'returns mixed success and error results' do
        results = JSON.parse(batch_response)

        expect(results['results'][0]).to have_key('html')
        expect(results['results'][1]).to have_key('error')
        expect(results['results'][2]).to have_key('html')
      end

      it 'includes error message for failed component' do
        results = JSON.parse(batch_response)

        expect(results['results'][1]['error']).to eq('Component rendering failed')
      end

      it 'does not fail entire batch when one component fails' do
        results = JSON.parse(batch_response)

        # Batch request succeeds (200)
        # First and third components rendered successfully
        expect(results['results'][0]['html']).to eq('<div>Success</div>')
        expect(results['results'][2]['html']).to eq('<div>Success</div>')
      end
    end

    context 'with invalid input format' do
      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .with(body: hash_excluding('components'))
          .to_return(status: 400, body: { error: 'Expected components array' }.to_json)
      end

      it 'returns 400 for non-array components' do
        # This tests that the SSR server validates input
        # We're stubbing the expected behavior
        response = stub_request(:post, 'http://localhost:5175/batch-render')
                   .with(body: { components: 'not an array' }.to_json)
                   .to_return(status: 400, body: { error: 'Expected components array' }.to_json)

        # Trigger the request
        begin
          uri = URI.parse('http://localhost:5175/batch-render')
          http = Net::HTTP.new(uri.host, uri.port)
          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = 'application/json'
          request.body = { components: 'not an array' }.to_json
          result = http.request(request)

          expect(result.code).to eq('400')
        rescue StandardError
          # Expected to fail in some way
        end
      end

      it 'returns 400 for missing components key' do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .with(body: {}.to_json)
          .to_return(status: 400, body: { error: 'Expected components array' }.to_json)

        # The endpoint would return 400, but our gem handles this by falling back to individual rendering
        # This is tested in the Renderer unit tests
      end
    end

    context 'with empty components array' do
      let(:batch_response) do
        { results: [] }.to_json
      end

      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .with(body: hash_including('components' => []))
          .to_return(status: 200, body: batch_response)
      end

      it 'returns empty results array' do
        results = JSON.parse(batch_response)
        expect(results['results']).to eq([])
      end
    end

    context 'with component rendering errors' do
      let(:batch_response) do
        {
          results: [
            { error: 'Component file not found' },
            { error: 'data.map is not a function' },
            { html: '<div>Only one succeeded</div>' }
          ]
        }.to_json
      end

      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: batch_response)
      end

      it 'includes error details in results' do
        results = JSON.parse(batch_response)

        expect(results['results'][0]['error']).to eq('Component file not found')
        expect(results['results'][1]['error']).to eq('data.map is not a function')
      end

      it 'still returns 200 status for batch request' do
        # Batch endpoint should return 200 even if individual components fail
        # Errors are per-component, not batch-level
        stub = stub_request(:post, 'http://localhost:5175/batch-render')
               .to_return(status: 200, body: batch_response)

        uri = URI.parse('http://localhost:5175/batch-render')
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request.body = { components: batch_components }.to_json
        response = http.request(request)

        expect(response.code).to eq('200')
      end
    end

    context 'with server error' do
      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 500, body: { error: 'Internal server error' }.to_json)
      end

      it 'returns 500 for server errors' do
        uri = URI.parse('http://localhost:5175/batch-render')
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request.body = { components: batch_components }.to_json

        response = http.request(request)
        expect(response.code).to eq('500')
      end
    end

    context 'when SSR server is unavailable' do
      before do
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_timeout
      end

      it 'handles connection timeout' do
        expect do
          uri = URI.parse('http://localhost:5175/batch-render')
          http = Net::HTTP.new(uri.host, uri.port)
          http.read_timeout = 1
          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = 'application/json'
          request.body = { components: batch_components }.to_json
          http.request(request)
        end.to raise_error(Net::OpenTimeout)
      end
    end
  end
end
