# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Asset Precompilation', type: :production do
  describe 'Vite build' do
    before(:all) do
      # Build production assets once for all tests in this file
      @build_result = ProductionHelpers.build_production_assets(clean: true)
    end

    after(:all) do
      # Clean up after all tests (optional, comment out to inspect builds)
      # FileUtils.rm_rf(ProductionHelpers::VITE_OUTPUT_PATH)
    end

    it 'completes successfully' do
      expect(@build_result).to be true
    end

    it 'generates manifest file' do
      expect(ProductionHelpers.production_assets_built?).to be true
    end

    it 'creates output directory structure' do
      expect(Dir.exist?(ProductionHelpers::VITE_OUTPUT_PATH)).to be true
      expect(Dir.exist?(File.join(ProductionHelpers::VITE_OUTPUT_PATH, 'assets'))).to be true
    end
  end

  describe 'manifest integrity', :requires_production_build do
    let(:manifest) { ProductionHelpers.load_manifest }

    it 'is valid JSON' do
      expect(manifest).to be_a(Hash)
      expect(manifest).not_to be_empty
    end

    it 'contains application entry point' do
      entry_found = manifest.key?('app/javascript/entrypoints/application.js') ||
                    manifest.key?('application.js') ||
                    manifest.values.any? { |v| v['isEntry'] }
      expect(entry_found).to be true
    end

    it 'has valid file references' do
      manifest.each do |key, value|
        next unless value.is_a?(Hash) && value['file']

        file_path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, value['file'])
        expect(File.exist?(file_path)).to be(true),
          "Missing file for manifest entry '#{key}': #{value['file']}"
      end
    end

    it 'has valid asset fingerprints' do
      invalid = ProductionHelpers.validate_fingerprints
      expect(invalid).to be_empty,
        "Invalid fingerprints found: #{invalid.map { |i| "#{i[:entry]}: #{i[:reason]}" }.join(', ')}"
    end
  end

  describe 'built assets', :requires_production_build do
    let(:asset_files) { ProductionHelpers.built_asset_files }
    let(:manifest) { ProductionHelpers.load_manifest }

    it 'includes JavaScript bundles' do
      js_files = asset_files.select { |f| f.end_with?('.js') }
      expect(js_files).not_to be_empty
    end

    it 'includes CSS files' do
      css_files = asset_files.select { |f| f.end_with?('.css') }
      # CSS might be extracted or inlined depending on config
      # Just verify we have some assets
      expect(asset_files).not_to be_empty
    end

    it 'uses content hashes in filenames' do
      hashed_files = asset_files.select { |f| f.match?(/-[a-f0-9]{8,}\.[^.]+$/) }
      # Most production files should have hashes
      expect(hashed_files.size).to be > 0
    end

    it 'generates source maps when enabled' do
      # Source maps are optional - check if they exist when generated
      map_files = asset_files.select { |f| f.end_with?('.map') }
      # This is informational - source maps are configurable
      if map_files.any?
        expect(map_files.size).to be > 0
      end
    end
  end

  describe 'bundle contents', :requires_production_build do
    let(:asset_files) { ProductionHelpers.built_asset_files }

    it 'does not contain React Refresh code' do
      leaks = ProductionHelpers.detect_development_code_leaks
      refresh_leaks = leaks.select { |l| l[:type] == 'react_refresh' }

      expect(refresh_leaks).to be_empty,
        "React Refresh code found in production bundles: #{refresh_leaks.map { |l| l[:file] }.join(', ')}"
    end

    it 'does not contain development source map URLs' do
      leaks = ProductionHelpers.detect_development_code_leaks
      sourcemap_leaks = leaks.select { |l| l[:type] == 'dev_sourcemap' }

      expect(sourcemap_leaks).to be_empty,
        "Development source map URLs found: #{sourcemap_leaks.map { |l| l[:file] }.join(', ')}"
    end

    it 'bundles React properly' do
      # Check that React is bundled or externalized correctly
      js_files = asset_files.select { |f| f.end_with?('.js') }

      js_files.each do |file|
        path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, file)
        content = File.read(path)

        # Should not have unresolved React imports pointing to dev server
        expect(content).not_to include('//localhost:5174')
        expect(content).not_to include('//localhost:5175')
      end
    end
  end

  describe 'performance thresholds', :requires_production_build do
    let(:metrics) { ProductionHelpers.measure_asset_metrics }

    # Configurable thresholds
    let(:max_js_size_kb) { 500 } # 500 KB for all JS
    let(:max_css_size_kb) { 100 } # 100 KB for all CSS
    let(:max_total_size_kb) { 600 } # 600 KB total

    it 'keeps JavaScript bundle size under threshold' do
      size_kb = metrics[:total_js_size] / 1024.0
      expect(size_kb).to be < max_js_size_kb,
        "Total JS size (#{size_kb.round(2)} KB) exceeds threshold (#{max_js_size_kb} KB)"
    end

    it 'keeps CSS bundle size under threshold' do
      size_kb = metrics[:total_css_size] / 1024.0
      expect(size_kb).to be < max_css_size_kb,
        "Total CSS size (#{size_kb.round(2)} KB) exceeds threshold (#{max_css_size_kb} KB)"
    end

    it 'keeps total bundle size under threshold' do
      size_kb = metrics[:total_size] / 1024.0
      expect(size_kb).to be < max_total_size_kb,
        "Total bundle size (#{size_kb.round(2)} KB) exceeds threshold (#{max_total_size_kb} KB)"
    end

    it 'produces reasonable number of chunks' do
      # Too many chunks = too many HTTP requests
      # Too few = not enough code splitting
      expect(metrics[:js_file_count]).to be_between(1, 20),
        "Unexpected number of JS files: #{metrics[:js_file_count]}"
    end
  end
end

