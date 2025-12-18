# frozen_string_literal: true

require 'rails_helper'
require 'vite_rails'

RSpec.describe ReactiveViewsHelper, type: :helper do
  # Include ViteRails helpers so our wrapper has something to wrap
  before do
    helper.extend(ViteRails::TagHelpers)
  end

  describe '#reactive_views_script_tag' do
    # In test mode (Rails.env.test?), the helper emits direct script tags
    # instead of relying on vite_rails helpers. This tests that behavior.
    context 'in test mode' do
      it 'includes SSR meta tag' do
        result = helper.reactive_views_script_tag
        expect(result).to include('reactive-views-ssr-url')
      end

      it 'includes @vite/client script' do
        result = helper.reactive_views_script_tag
        expect(result).to include('@vite/client')
      end

      it 'includes React refresh preamble' do
        result = helper.reactive_views_script_tag
        expect(result).to include('@react-refresh')
        expect(result).to include('__vite_plugin_react_preamble_installed__')
      end

      it 'includes entrypoints/application.js script' do
        result = helper.reactive_views_script_tag
        expect(result).to include('entrypoints/application.js')
      end

      it 'joins output with newlines' do
        result = helper.reactive_views_script_tag
        expect(result).to include("\n")
      end
    end

    context 'in development mode (non-test)' do
      before do
        # Stub Rails.env to development (not test)
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        # Stub the vite_rails methods that our helper wraps
        allow(helper).to receive(:vite_client_tag).and_return('<script>vite client</script>'.html_safe)
        allow(helper).to receive(:vite_javascript_tag).and_return('<script>vite js for application</script>'.html_safe)
        allow(ViteRuby).to receive_message_chain(:config, :public_output_dir).and_return('vite-dev')
      end

      it 'includes vite_client_tag' do
        result = helper.reactive_views_script_tag
        expect(result).to include('vite client')
      end

      it 'includes vite_javascript_tag for application' do
        result = helper.reactive_views_script_tag
        expect(result).to include('vite js for application')
      end

      it 'includes React refresh preamble' do
        result = helper.reactive_views_script_tag
        expect(result).to include('@react-refresh')
      end
    end

    context 'when vite methods are not available (development mode)' do
      before do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
        # Make respond_to? return false for vite methods
        allow(helper).to receive(:respond_to?).and_call_original
        allow(helper).to receive(:respond_to?).with(:vite_client_tag).and_return(false)
        allow(helper).to receive(:respond_to?).with(:vite_javascript_tag).and_return(false)
      end

      it 'returns only SSR meta tag when vite methods not available' do
        result = helper.reactive_views_script_tag
        expect(result).to include('reactive-views-ssr-url')
        # Still includes React refresh preamble even without vite helpers
        expect(result).to include('@react-refresh')
      end

      it 'does not raise errors' do
        expect { helper.reactive_views_script_tag }.not_to raise_error
      end
    end
  end

  describe '#reactive_views_boot (deprecated)' do
    it 'warns about deprecation' do
      expect { helper.reactive_views_boot }.to output(/DEPRECATION/).to_stderr
    end

    it 'returns javascript_include_tag' do
      result = helper.reactive_views_boot
      expect(result).to include('script')
    end
  end
end
