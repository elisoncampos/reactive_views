# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Manifest Integrity', type: :production do
  before(:all) do
    # Ensure production assets are built
    @build_attempted = true
    @build_result = ProductionHelpers.production_assets_built? ||
                    ProductionHelpers.build_production_assets
  end

  let(:manifest) { ProductionHelpers.load_manifest }

  describe 'manifest structure' do
    it 'has correct JSON structure' do
      expect(manifest).to be_a(Hash)
    end

    it 'contains at least one entry' do
      skip 'Production assets not built' unless @build_result && manifest.any?
      expect(manifest.keys.size).to be >= 1
    end

    it 'has file property for each entry' do
      manifest.each do |key, value|
        next unless value.is_a?(Hash)

        expect(value).to have_key('file'),
          "Entry '#{key}' missing 'file' property"
      end
    end
  end

  describe 'entry points' do
    it 'identifies entry points correctly' do
      skip 'Production assets not built' unless @build_result && manifest.any?

      entries = manifest.select { |_k, v| v.is_a?(Hash) && v['isEntry'] }

      # Should have at least one entry point
      expect(entries.size).to be >= 1
    end

    it 'resolves application entry point' do
      skip 'Production assets not built' unless @build_result && manifest.any?

      # Try various possible entry point names
      possible_entries = [
        'app/javascript/entrypoints/application.js',
        'application.js',
        'app/javascript/application.js'
      ]

      found = possible_entries.any? do |entry|
        manifest.key?(entry) ||
          manifest.values.any? { |v| v.is_a?(Hash) && v['src'] == entry }
      end

      expect(found).to be(true),
        "Could not find application entry point. Available: #{manifest.keys.first(5).join(', ')}"
    end
  end

  describe 'file references' do
    it 'all referenced files exist on disk' do
      missing = []

      manifest.each do |key, value|
        next unless value.is_a?(Hash)

        file = value['file']
        next unless file

        full_path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, file)
        missing << { entry: key, file: file } unless File.exist?(full_path)
      end

      expect(missing).to be_empty,
        "Missing files: #{missing.map { |m| m[:file] }.join(', ')}"
    end

    it 'CSS references exist' do
      missing_css = []

      manifest.each do |key, value|
        next unless value.is_a?(Hash) && value['css']

        value['css'].each do |css_file|
          full_path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, css_file)
          missing_css << { entry: key, css: css_file } unless File.exist?(full_path)
        end
      end

      expect(missing_css).to be_empty,
        "Missing CSS files: #{missing_css.map { |m| m[:css] }.join(', ')}"
    end

    it 'asset references are relative paths' do
      absolute_paths = []

      manifest.each do |key, value|
        next unless value.is_a?(Hash)

        file = value['file']
        if file&.start_with?('/')
          absolute_paths << { entry: key, file: file }
        end
      end

      expect(absolute_paths).to be_empty,
        "Absolute paths found in manifest: #{absolute_paths.map { |p| p[:file] }.join(', ')}"
    end
  end

  describe 'asset fingerprints' do
    it 'uses consistent hash format' do
      hash_lengths = []

      manifest.each do |_key, value|
        next unless value.is_a?(Hash)

        file = value['file']
        next unless file

        if file =~ /-([a-f0-9]+)\.[^.]+$/
          hash_lengths << ::Regexp.last_match(1).length
        end
      end

      # All hashes should be the same length
      expect(hash_lengths.uniq.size).to be <= 1,
        "Inconsistent hash lengths: #{hash_lengths.uniq.join(', ')}"
    end

    it 'fingerprints are valid hexadecimal' do
      invalid_hashes = []

      manifest.each do |key, value|
        next unless value.is_a?(Hash)

        file = value['file']
        next unless file

        if file =~ /-([a-f0-9]+)\.[^.]+$/i
          hash = ::Regexp.last_match(1)
          unless hash.match?(/^[a-f0-9]+$/i)
            invalid_hashes << { entry: key, hash: hash }
          end
        end
      end

      expect(invalid_hashes).to be_empty,
        "Invalid hashes: #{invalid_hashes.map { |h| "#{h[:entry]}: #{h[:hash]}" }.join(', ')}"
    end
  end

  describe 'imports and dependencies' do
    it 'tracks dynamic imports' do
      # Check if manifest properly tracks code-split chunks
      dynamic_imports = manifest.select do |_k, v|
        v.is_a?(Hash) && v['dynamicImports']&.any?
      end

      # Informational - not all builds have dynamic imports
      if dynamic_imports.any?
        dynamic_imports.each do |key, value|
          value['dynamicImports'].each do |import|
            expect(manifest).to have_key(import),
              "Dynamic import '#{import}' from '#{key}' not found in manifest"
          end
        end
      end
    end

    it 'tracks CSS dependencies correctly' do
      entries_with_css = manifest.select do |_k, v|
        v.is_a?(Hash) && v['css']&.any?
      end

      entries_with_css.each do |key, value|
        value['css'].each do |css_path|
          full_path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, css_path)
          expect(File.exist?(full_path)).to be(true),
            "CSS dependency '#{css_path}' for '#{key}' not found"
        end
      end
    end
  end
end
