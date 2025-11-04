# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views'

RSpec.describe ReactiveViews::PropsInference do
  before do
    # Clear cache before each test
    described_class.cache.clear

    ReactiveViews.configure do |config|
      config.props_inference_enabled = true
      config.ssr_url = 'http://localhost:5175'
      config.props_inference_cache_ttl_seconds = 60
    end
  end

  describe '.infer_props' do
    context 'with function declaration syntax' do
      it 'extracts props from destructured parameters' do
        tsx_content = <<~TSX
          export default function MyComponent({ name, age, email }: Props) {
            return <div>{name}</div>;
          }
        TSX

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 200, body: { keys: ['name', 'age', 'email'] }.to_json)

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq(['name', 'age', 'email'])
      end

      it 'handles empty destructuring' do
        tsx_content = <<~TSX
          export default function MyComponent() {
            return <div>No props</div>;
          }
        TSX

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 200, body: { keys: [] }.to_json)

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
      end
    end

    context 'with const arrow function syntax' do
      it 'extracts props from arrow function parameters' do
        tsx_content = <<~TSX
          const MyComponent = ({ title, description }: Props) => {
            return <div>{title}</div>;
          };
          export default MyComponent;
        TSX

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 200, body: { keys: ['title', 'description'] }.to_json)

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq(['title', 'description'])
      end
    end

    context 'with caching' do
      it 'caches results by content digest' do
        tsx_content = <<~TSX
          export default function MyComponent({ name }: Props) {
            return <div>{name}</div>;
          }
        TSX

        # First call should hit the server
        stub = stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 200, body: { keys: ['name'] }.to_json)

        keys1 = described_class.infer_props(tsx_content)
        expect(keys1).to eq(['name'])
        expect(stub).to have_been_requested.once

        # Second call with same content should use cache
        keys2 = described_class.infer_props(tsx_content)
        expect(keys2).to eq(['name'])
        expect(stub).to have_been_requested.once # Still only once
      end

      it 'uses different cache keys for different content' do
        tsx_content1 = 'export default function C1({ a }: P) { return <div />; }'
        tsx_content2 = 'export default function C2({ b }: P) { return <div />; }'

        stub1 = stub_request(:post, 'http://localhost:5175/infer-props')
          .with(body: hash_including('tsxContent' => tsx_content1))
          .to_return(status: 200, body: { keys: ['a'] }.to_json)

        stub2 = stub_request(:post, 'http://localhost:5175/infer-props')
          .with(body: hash_including('tsxContent' => tsx_content2))
          .to_return(status: 200, body: { keys: ['b'] }.to_json)

        keys1 = described_class.infer_props(tsx_content1)
        keys2 = described_class.infer_props(tsx_content2)

        expect(keys1).to eq(['a'])
        expect(keys2).to eq(['b'])
        expect(stub1).to have_been_requested.once
        expect(stub2).to have_been_requested.once
      end

    end

    context 'with error handling' do
      it 'returns empty array on server error' do
        tsx_content = 'export default function C({ x }: P) { return <div />; }'

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 500, body: 'Internal Server Error')

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
      end

      it 'returns empty array on connection refused' do
        tsx_content = 'export default function C({ x }: P) { return <div />; }'

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_raise(Errno::ECONNREFUSED)

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
      end

      it 'returns empty array on timeout' do
        tsx_content = 'export default function C({ x }: P) { return <div />; }'

        ReactiveViews.configure do |config|
          config.ssr_timeout = 0.01
        end

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_timeout

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
      end

      it 'returns empty array on invalid JSON response' do
        tsx_content = 'export default function C({ x }: P) { return <div />; }'

        stub_request(:post, 'http://localhost:5175/infer-props')
          .to_return(status: 200, body: 'not json')

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
      end
    end

    context 'when props_inference_enabled is false' do
      it 'returns empty array without making request' do
        ReactiveViews.configure do |config|
          config.props_inference_enabled = false
        end

        tsx_content = 'export default function C({ x }: P) { return <div />; }'

        stub = stub_request(:post, 'http://localhost:5175/infer-props')

        keys = described_class.infer_props(tsx_content)
        expect(keys).to eq([])
        expect(stub).not_to have_been_requested
      end
    end
  end
end
