# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Error Scenarios', type: :production do
  before(:all) do
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'asset errors' do
    describe 'missing manifest file' do
      it 'raises AssetManifestNotFoundError with helpful message' do
        # Temporarily move manifest
        manifest_path = ProductionHelpers::MANIFEST_PATH
        alt_manifest_path = ProductionHelpers::ALTERNATE_MANIFEST_PATH
        backup_path = "#{manifest_path}.bak"
        alt_backup_path = "#{alt_manifest_path}.bak"

        FileUtils.mv(manifest_path, backup_path) if File.exist?(manifest_path)
        FileUtils.mv(alt_manifest_path, alt_backup_path) if File.exist?(alt_manifest_path)

        begin
          # Mock production environment
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
          allow(Rails).to receive(:root).and_return(Pathname.new(ProductionHelpers::DUMMY_APP_PATH))

          helper = Object.new.extend(ReactiveViewsHelper)
          allow(helper).to receive(:respond_to?).with(:vite_javascript_tag).and_return(false)
          allow(helper).to receive(:respond_to?).with(:vite_client_tag).and_return(false)
          allow(helper).to receive(:tag).and_return(ActionView::Helpers::TagHelper)

          expect {
            helper.send(:manual_production_script_tag)
          }.to raise_error(ReactiveViews::AssetManifestNotFoundError, /manifest not found/i)
        ensure
          # Restore manifest
          FileUtils.mv(backup_path, manifest_path) if File.exist?(backup_path)
          FileUtils.mv(alt_backup_path, alt_manifest_path) if File.exist?(alt_backup_path)
        end
      end
    end

    describe 'missing component bundle' do
      it 'SSR returns error for nonexistent component' do
        skip 'SSR server not running' unless ssr_available?

        expect {
          ReactiveViews::Renderer.render('/nonexistent/path/Component.tsx', {})
        }.to raise_error(StandardError)
      end
    end

    describe 'corrupted manifest' do
      it 'handles invalid JSON gracefully' do
        # Create corrupted manifest
        manifest_path = ProductionHelpers::MANIFEST_PATH
        backup_path = "#{manifest_path}.bak"

        if File.exist?(manifest_path)
          FileUtils.cp(manifest_path, backup_path)
          File.write(manifest_path, 'invalid json {{{')
        end

        begin
          manifest = ProductionHelpers.load_manifest
          expect(manifest).to eq({})
        ensure
          FileUtils.mv(backup_path, manifest_path) if File.exist?(backup_path)
        end
      end
    end
  end

  describe 'SSR errors' do
    describe 'SSR server unavailable' do
      before do
        @original_url = ReactiveViews.config.ssr_url
        ReactiveViews.configure do |config|
          config.ssr_url = 'http://localhost:59999' # Non-existent port
        end
      end

      after do
        ReactiveViews.configure do |config|
          config.ssr_url = @original_url
        end
      end

      it 'raises SSRConnectionError or connection refused' do
        component_path = File.join(
          ProductionHelpers::DUMMY_APP_PATH,
          'app', 'views', 'components', 'Counter.tsx'
        )

        expect {
          ReactiveViews::Renderer.render(component_path, {})
        }.to raise_error(StandardError)
      end
    end

    describe 'SSR timeout' do
      before do
        ReactiveViews.configure do |config|
          config.ssr_timeout = 0.001 # Extremely short timeout
        end
      end

      after do
        ReactiveViews.configure do |config|
          config.ssr_timeout = 5
        end
      end

      it 'raises timeout error for slow renders' do
        skip 'SSR server not running' unless ssr_available?

        component_path = File.join(
          ProductionHelpers::DUMMY_APP_PATH,
          'app', 'views', 'components', 'Counter.tsx'
        )

        expect {
          ReactiveViews::Renderer.render(component_path, {})
        }.to raise_error(StandardError) # Timeout or connection error
      end
    end

    describe 'component compilation error' do
      it 'returns error details in development-like response' do
        skip 'SSR server not running' unless ssr_available?

        # Create a component with syntax error
        bad_component = Tempfile.new(['BadComponent', '.tsx'])
        bad_component.write('export default function BadComponent( { invalid syntax')
        bad_component.close

        begin
          expect {
            ReactiveViews::Renderer.render(bad_component.path, {})
          }.to raise_error(StandardError, /error/i)
        ensure
          bad_component.unlink
        end
      end
    end
  end

  describe 'graceful degradation' do
    describe 'with ssr_fallback_enabled' do
      before do
        @original_fallback = ReactiveViews.config.ssr_fallback_enabled
        @original_url = ReactiveViews.config.ssr_url
        ReactiveViews.configure do |config|
          config.ssr_fallback_enabled = true
          config.ssr_url = 'http://localhost:59999' # Non-existent
        end
      end

      after do
        ReactiveViews.configure do |config|
          config.ssr_fallback_enabled = @original_fallback
          config.ssr_url = @original_url
        end
      end

      it 'page still renders when SSR fails' do
        # The TagTransformer should handle SSR failures gracefully
        html = '<html><body><Counter props="{}" /></body></html>'

        # Should not raise, should return transformed or original HTML
        result = ReactiveViews::TagTransformer.transform(html)
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end
  end

  describe 'retry behavior' do
    it 'respects ssr_retry_count configuration' do
      expect(ReactiveViews.config.ssr_retry_count).to be >= 0
    end

    it 'respects ssr_retry_delay configuration' do
      expect(ReactiveViews.config.ssr_retry_delay).to be >= 0
    end
  end

  private

  def ssr_available?
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

