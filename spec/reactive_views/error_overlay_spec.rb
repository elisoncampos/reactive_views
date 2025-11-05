# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views/error_overlay'

RSpec.describe ReactiveViews::ErrorOverlay do
  describe '.generate' do
    let(:component_name) { 'FailingComponent' }
    let(:props) { { message: 'Hello', count: 42 } }
    let(:error_message) { 'Component not found' }

    it 'returns HTML string' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to be_a(String)
      expect(result).to include('<div')
    end

    it 'includes component name in error' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to include(component_name)
    end

    it 'includes error message' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to include(error_message)
    end

    it 'includes props information' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to include('message')
      expect(result).to include('Hello')
    end

    it 'escapes HTML in error messages' do
      malicious_error = "<script>alert('xss')</script>"
      result = described_class.generate(
        component_name: component_name,
        props: {},
        error: malicious_error
      )

      expect(result).not_to include('<script>alert')
      expect(result).to include('&lt;script&gt;')
    end

    it 'handles complex props' do
      complex_props = {
        items: %w[a b c],
        config: { nested: true }
      }

      result = described_class.generate(
        component_name: component_name,
        props: complex_props,
        error: error_message
      )

      expect(result).to include('items')
      expect(result).to include('config')
    end

    it 'includes ReactiveViews branding' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to include('ReactiveViews')
    end

    it 'applies error styling' do
      result = described_class.generate(
        component_name: component_name,
        props: props,
        error: error_message
      )

      expect(result).to match(/style=.*background|color|border/i)
    end
  end
end
