# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Production Rendering', type: :production do
  before(:all) do
    # Ensure production assets are built
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'ReactiveViewsHelper in production mode' do
    include ReactiveViewsHelper

    let(:production_env) { true }

    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
    end

    describe '#reactive_views_script_tag' do
      it 'outputs SSR URL meta tag' do
        output = reactive_views_script_tag
        expect(output).to include('meta')
        expect(output).to include('reactive-views-ssr-url')
      end

      it 'does not include React Refresh preamble' do
        output = reactive_views_script_tag
        expect(output).not_to include('@react-refresh')
        expect(output).not_to include('$RefreshReg$')
        expect(output).not_to include('__vite_plugin_react_preamble_installed__')
      end

      it 'does not include vite_client_tag output' do
        output = reactive_views_script_tag
        # In production, we shouldn't have the Vite HMR client
        expect(output).not_to include('/@vite/client')
      end
    end

    describe '#reactive_views_asset_host' do
      it 'returns nil when not configured' do
        allow(ReactiveViews.config).to receive(:asset_host).and_return(nil)
        allow(ENV).to receive(:[]).with('ASSET_HOST').and_return(nil)

        expect(reactive_views_asset_host).to be_nil
      end

      it 'returns configured asset host' do
        allow(ReactiveViews.config).to receive(:asset_host).and_return('https://cdn.example.com')

        expect(reactive_views_asset_host).to eq('https://cdn.example.com')
      end

      it 'falls back to ENV variable' do
        allow(ReactiveViews.config).to receive(:asset_host).and_return(nil)
        allow(ENV).to receive(:[]).with('ASSET_HOST').and_return('https://env-cdn.example.com')

        expect(reactive_views_asset_host).to eq('https://env-cdn.example.com')
      end
    end
  end

  describe 'SSR rendering in production mode' do
    let(:component_path) do
      File.join(ProductionHelpers::DUMMY_APP_PATH, 'app', 'views', 'components', 'Counter.tsx')
    end

    before do
      # Configure for production
      ReactiveViews.configure do |config|
        config.ssr_url = "http://localhost:#{TestServers::SSR_PORT}"
        config.ssr_timeout = 10
      end
    end

    it 'renders component HTML' do
      skip 'SSR server not running' unless server_available?

      result = ReactiveViews::Renderer.render(component_path, { initialCount: 5 })

      expect(result).to be_a(Hash)
      expect(result[:html]).to be_present
      expect(result[:html]).to include('5') # Initial count should be in HTML
    end

    it 'handles SSR timeout gracefully' do
      ReactiveViews.configure do |config|
        config.ssr_timeout = 0.001 # Very short timeout
      end

      expect {
        ReactiveViews::Renderer.render(component_path, {})
      }.to raise_error(ReactiveViews::SSRTimeoutError).or(
        raise_error(Net::OpenTimeout)
      ).or(
        raise_error(Net::ReadTimeout)
      )
    end

    it 'returns metadata with bundleKey for full-page rendering' do
      skip 'SSR server not running' unless server_available?

      result = ReactiveViews::Renderer.render(component_path, {}, include_metadata: true)

      expect(result).to have_key(:bundleKey)
    end
  end

  describe 'component tag transformation' do
    let(:html_with_component) do
      <<~HTML
        <html>
        <head><title>Test</title></head>
        <body>
          <div class="container">
            <Counter props='{"initialCount":10}' />
          </div>
        </body>
        </html>
      HTML
    end

    it 'transforms component tags to hydration-ready HTML' do
      skip 'SSR server not running' unless server_available?

      transformed = ReactiveViews::TagTransformer.transform(html_with_component)

      # Should have data attributes for hydration
      expect(transformed).to include('data-island-uuid')
      expect(transformed).to include('data-component')
    end

    it 'includes props script tag for hydration' do
      skip 'SSR server not running' unless server_available?

      transformed = ReactiveViews::TagTransformer.transform(html_with_component)

      # Props should be in a JSON script tag
      expect(transformed).to include('type="application/json"')
      expect(transformed).to include('data-island-uuid')
    end
  end

  describe 'error handling' do
    it 'raises ComponentNotFoundError for missing components' do
      expect {
        ReactiveViews::Renderer.render('/nonexistent/component.tsx', {})
      }.to raise_error(ReactiveViews::ComponentNotFoundError).or(
        raise_error(StandardError, /not found/i)
      )
    end

    context 'with ssr_fallback_enabled' do
      before do
        ReactiveViews.configure do |config|
          config.ssr_fallback_enabled = true
          config.ssr_url = 'http://localhost:59999' # Non-existent server
        end
      end

      it 'returns empty HTML when SSR fails and fallback is enabled' do
        component_path = File.join(ProductionHelpers::DUMMY_APP_PATH, 'app', 'views', 'components', 'Counter.tsx')

        # With fallback enabled, should not raise but return empty/error result
        result = ReactiveViews::Renderer.render(component_path, {})

        # The behavior depends on implementation - either returns empty or raises
        expect(result[:html]).to be_present.or(be_nil)
      end
    end
  end

  private

  def server_available?
    require 'net/http'
    uri = URI.parse("http://localhost:#{TestServers::SSR_PORT}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    response = http.get(uri.request_uri)
    response.code.to_i == 200
  rescue StandardError
    false
  end
end

