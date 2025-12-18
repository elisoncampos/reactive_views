# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views'

RSpec.describe ReactiveViews::Configuration do
  let(:config) { described_class.new }

  describe 'default values' do
    around do |example|
      # Isolate from CI environment variables
      original_rv = ENV.delete('RV_SSR_URL')
      original_legacy = ENV.delete('REACTIVE_VIEWS_SSR_URL')
      example.run
    ensure
      ENV['RV_SSR_URL'] = original_rv if original_rv
      ENV['REACTIVE_VIEWS_SSR_URL'] = original_legacy if original_legacy
    end

    it 'is enabled by default' do
      expect(config.enabled).to be true
    end

    it 'has default SSR URL' do
      expect(described_class.new.ssr_url).to eq('http://localhost:5175')
    end

    it 'has default component views paths' do
      expect(config.component_views_paths).to eq([ 'app/views/components' ])
    end

    it 'has default component js paths' do
      expect(config.component_js_paths).to eq([ 'app/javascript/components' ])
    end

    it 'has default SSR timeout' do
      expect(config.ssr_timeout).to eq(5)
    end

    it 'has no cache TTL by default' do
      expect(config.ssr_cache_ttl_seconds).to be_nil
    end
  end

  describe 'batch rendering configuration' do
    it 'has batch_rendering_enabled setting' do
      expect(config).to respond_to(:batch_rendering_enabled)
    end

    it 'batch rendering is enabled by default' do
      expect(config.batch_rendering_enabled).to be true
    end

    it 'has batch_timeout setting' do
      expect(config).to respond_to(:batch_timeout)
    end

    it 'batch timeout is longer than regular SSR timeout' do
      expect(config.batch_timeout).to be > config.ssr_timeout
    end

    it 'batch timeout defaults to 10 seconds' do
      expect(config.batch_timeout).to eq(10)
    end

    it 'allows setting batch_rendering_enabled' do
      config.batch_rendering_enabled = false
      expect(config.batch_rendering_enabled).to be false
    end

    it 'allows setting batch_timeout' do
      config.batch_timeout = 15
      expect(config.batch_timeout).to eq(15)
    end
  end

  describe 'configuring via ReactiveViews.configure' do
    before do
      ReactiveViews.configure do |c|
        c.batch_rendering_enabled = false
        c.batch_timeout = 20
      end
    end

    after do
      # Reset to defaults
      ReactiveViews.configure do |c|
        c.batch_rendering_enabled = true
        c.batch_timeout = 10
      end
    end

    it 'applies batch_rendering_enabled configuration' do
      expect(ReactiveViews.config.batch_rendering_enabled).to be false
    end

    it 'applies batch_timeout configuration' do
      expect(ReactiveViews.config.batch_timeout).to eq(20)
    end
  end

  describe 'batch rendering behavior when disabled' do
    before do
      ReactiveViews.configure do |c|
        c.batch_rendering_enabled = false
        c.ssr_url = 'http://localhost:5175'
      end

      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return('/path/to/Component.tsx')

      # Prevent auto-spawn from changing the SSR URL
      allow(ReactiveViews::SsrProcess).to receive(:ensure_running)
    end

    after do
      ReactiveViews.configure do |c|
        c.batch_rendering_enabled = true
      end
    end

    it 'falls back to individual rendering' do
      component_specs = [
        { uuid: '1', component_name: 'C1', props: {} },
        { uuid: '2', component_name: 'C2', props: {} }
      ]

      # Should NOT use batch endpoint
      stub_request(:post, 'http://localhost:5175/render')
        .to_return(status: 200, body: { html: '<div>Individual</div>' }.to_json)

      ReactiveViews::Renderer.batch_render(component_specs)

      # Should have used individual render endpoint
      expect(WebMock).to have_requested(:post, 'http://localhost:5175/render').twice
      expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/batch-render')
    end
  end

  describe 'environment variable configuration' do
    around do |example|
      # Isolate from CI environment variables
      original_rv = ENV.delete('RV_SSR_URL')
      original_legacy = ENV.delete('REACTIVE_VIEWS_SSR_URL')
      example.run
    ensure
      ENV['RV_SSR_URL'] = original_rv if original_rv
      ENV['REACTIVE_VIEWS_SSR_URL'] = original_legacy if original_legacy
    end

    it 'can read SSR URL from environment' do
      ENV['RV_SSR_URL'] = 'http://custom-ssr:9000'
      new_config = described_class.new

      expect(new_config.ssr_url).to eq('http://custom-ssr:9000')
    end

    it 'uses default SSR URL when env vars not set' do
      new_config = described_class.new

      # Default SSR URL when no env vars
      expect(new_config.ssr_url).to eq('http://localhost:5175')
    end
  end

  describe 'validation' do
    it 'allows valid timeout values' do
      expect { config.batch_timeout = 1 }.not_to raise_error
      expect { config.batch_timeout = 60 }.not_to raise_error
    end

    it 'allows boolean values for batch_rendering_enabled' do
      expect { config.batch_rendering_enabled = true }.not_to raise_error
      expect { config.batch_rendering_enabled = false }.not_to raise_error
    end
  end
end
