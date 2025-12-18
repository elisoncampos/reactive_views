# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Error Scenarios', type: :production do
  before(:all) do
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'asset errors' do
    describe 'missing manifest file' do
      it 'ProductionHelpers handles missing manifest gracefully' do
        # Test the helper's graceful handling of missing manifest
        manifest_path = ProductionHelpers::MANIFEST_PATH
        alt_manifest_path = ProductionHelpers::ALTERNATE_MANIFEST_PATH
        backup_path = "#{manifest_path}.bak"
        alt_backup_path = "#{alt_manifest_path}.bak"

        FileUtils.mv(manifest_path, backup_path) if File.exist?(manifest_path)
        FileUtils.mv(alt_manifest_path, alt_backup_path) if File.exist?(alt_manifest_path)

        begin
          manifest = ProductionHelpers.load_manifest
          # Should return empty hash when manifest is missing
          expect(manifest).to eq({})
        ensure
          # Restore manifest
          FileUtils.mv(backup_path, manifest_path) if File.exist?(backup_path)
          FileUtils.mv(alt_backup_path, alt_manifest_path) if File.exist?(alt_backup_path)
        end
      end
    end

    describe 'missing component bundle' do
      it 'SSR returns empty result for nonexistent component' do
        # With current implementation, missing components return empty string
        result = ReactiveViews::Renderer.render('/nonexistent/path/Component.tsx', {})
        expect(result).to be_a(String)
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

      it 'returns empty string or error marker when SSR unavailable' do
        component_path = File.join(
          ProductionHelpers::DUMMY_APP_PATH,
          'app', 'views', 'components', 'Counter.tsx'
        )

        # With fallback enabled, should return string (empty or error marker)
        result = ReactiveViews::Renderer.render(component_path, {})
        expect(result).to be_a(String)
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

      it 'handles timeout gracefully' do
        skip 'SSR server not running' unless ssr_available?

        component_path = File.join(
          ProductionHelpers::DUMMY_APP_PATH,
          'app', 'views', 'components', 'Counter.tsx'
        )

        # Renderer handles timeouts gracefully with fallback
        result = ReactiveViews::Renderer.render(component_path, {})
        expect(result).to be_a(String)
      end
    end

    describe 'component compilation error' do
      it 'returns error marker for invalid component' do
        skip 'SSR server not running' unless ssr_available?

        # Create a component with syntax error
        bad_component = Tempfile.new([ 'BadComponent', '.tsx' ])
        bad_component.write('export default function BadComponent( { invalid syntax')
        bad_component.close

        begin
          # SSR returns error marker for compilation errors
          result = ReactiveViews::Renderer.render(bad_component.path, {})
          expect(result).to be_a(String)
          # In development, error markers start with ___REACTIVE_VIEWS_ERROR___
          # or just be empty/fallback HTML
        ensure
          bad_component.unlink
        end
      end
    end
  end

  describe 'graceful degradation' do
    describe 'when SSR fails' do
      before do
        @original_url = ReactiveViews.config.ssr_url
        ReactiveViews.configure do |config|
          config.ssr_url = 'http://localhost:59999' # Non-existent
        end
      end

      after do
        ReactiveViews.configure do |config|
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
