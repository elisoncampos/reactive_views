# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views'

RSpec.describe ReactiveViews::ErrorOverlay do
  let(:component_name) { 'FailingComponent' }
  let(:props) { { message: 'Hello', count: 42 } }
  let(:error_message) { 'Component not found' }

  before do
    ReactiveViews.configure do |config|
      config.ssr_url = 'http://localhost:5175'
    end
  end

  describe '.generate (inline overlay)' do
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

  describe '.generate_fullscreen' do
    let(:errors) { [ { message: 'Test error message' } ] }

    it 'returns injectable HTML that can be embedded in a page' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      # Should NOT be a complete HTML document - just injectable HTML
      expect(result).not_to include('<!DOCTYPE html>')
      expect(result).not_to include('<html')
      # Should contain the scoped error root container
      expect(result).to include('<div id="rv-error-root">')
      expect(result).to include('<style>')
      expect(result).to include('</style>')
    end

    it 'includes fullscreen overlay styles' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('position: fixed')
      expect(result).to include('inset: 0')
      expect(result).to include('z-index: 99999')
    end

    it 'includes the error overlay container' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('rv-overlay')
      expect(result).to include('rv-backdrop')
    end

    it 'includes the error badge' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('rv-badge')
      expect(result).to include('1 error')
    end

    it 'includes error count for multiple errors' do
      multiple_errors = [
        { message: 'Error 1' },
        { message: 'Error 2' },
        { message: 'Error 3' }
      ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: multiple_errors
      )

      expect(result).to include('3 errors')
    end

    it 'includes tabs for multiple errors' do
      multiple_errors = [
        { message: 'Error 1' },
        { message: 'Error 2' }
      ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: multiple_errors
      )

      expect(result).to include('rv-tabs')
      expect(result).to include('rv-tab')
      expect(result).to include('data-tab="0"')
      expect(result).to include('data-tab="1"')
    end

    it 'does not include tabs for single error' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: [ { message: 'Single error' } ]
      )

      # Check that the actual tabs div is not present (CSS will still have the class)
      expect(result).not_to include('<div class="rv-tabs"')
    end

    it 'includes keyboard shortcut support' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('Escape')
      expect(result).to include('keydown')
    end

    it 'includes error suggestions' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: [ { message: 'Component not found' } ]
      )

      expect(result).to include('Suggestions')
      expect(result).to include('component file exists')
    end

    it 'escapes HTML in error messages' do
      malicious_errors = [ { message: "<script>alert('xss')</script>" } ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: {},
        errors: malicious_errors
      )

      expect(result).not_to include("<script>alert('xss')</script>")
      expect(result).to include('&lt;script&gt;')
    end

    it 'includes component name in error panel' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include(component_name)
    end

    it 'includes props section when props provided' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('Component Props')
      expect(result).to include('message')
    end

    it 'handles empty props gracefully' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: {},
        errors: errors
      )

      # Should not show actual props content element (CSS will still have the class)
      expect(result).not_to include('<pre class="rv-props-content"')
    end

    it 'includes stack trace section when stack is provided' do
      errors_with_stack = [ {
        message: 'Error message',
        stack: "at Component (/app/views/components/test.tsx:10:5)\nat render"
      } ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors_with_stack
      )

      expect(result).to include('Call Stack')
      expect(result).to include('rv-stack-trace')
    end

    it 'includes JavaScript for overlay interactivity' do
      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: props,
        errors: errors
      )

      expect(result).to include('window.RVOverlay')
      expect(result).to include('show')
      expect(result).to include('hide')
      expect(result).to include('switchTab')
    end

    it 'generates appropriate suggestions for syntax errors' do
      syntax_error = [ { message: 'SyntaxError: Unexpected token' } ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: {},
        errors: syntax_error
      )

      expect(result).to include('syntax error')
    end

    it 'generates appropriate suggestions for connection errors' do
      connection_error = [ { message: 'Could not connect to SSR server' } ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: {},
        errors: connection_error
      )

      expect(result).to include("bin/dev")
    end

    it 'generates appropriate suggestions for timeout errors' do
      timeout_error = [ { message: 'Request timed out' } ]

      result = described_class.generate_fullscreen(
        component_name: component_name,
        props: {},
        errors: timeout_error
      )

      expect(result).to include('overloaded')
    end
  end
end
