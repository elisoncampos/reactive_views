# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/reactive_views/tag_transformer'
require_relative '../../lib/reactive_views/configuration'
require_relative '../../lib/reactive_views/renderer'
require_relative '../../lib/reactive_views/error_overlay'
require_relative '../../lib/reactive_views'

RSpec.describe ReactiveViews::TagTransformer do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
    end
  end

  describe '.transform' do
    context 'when ReactiveViews is disabled' do
      it 'returns HTML unchanged' do
        ReactiveViews.config.enabled = false
        html = '<MyComponent />'
        expect(described_class.transform(html)).to eq(html)
      end
    end

    context 'when HTML is empty or nil' do
      it 'returns empty HTML unchanged' do
        expect(described_class.transform('')).to eq('')
      end

      it 'returns nil HTML unchanged' do
        expect(described_class.transform(nil)).to be_nil
      end
    end

    context 'with PascalCase component tags' do
      before do
        # Mock component resolution
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/component.tsx')

        allow(ReactiveViews::Renderer).to receive(:render)
          .and_return('<div>SSR Content</div>')
      end

      it 'transforms simple component tags' do
        # Mock batch render for batch rendering
        allow(ReactiveViews::Renderer).to receive(:batch_render).and_return([
                                                                              { html: '<div>SSR Content</div>' }
                                                                            ])

        html = '<html><body><MyComponent /></body></html>'
        result = described_class.transform(html)

        expect(result).to include('data-island-uuid')
        expect(result).to include('data-component="MyComponent"')
        expect(result).to include('SSR Content')
      end

      it 'preserves PascalCase component names' do
        html = "<HelloWorld message='test' />"
        result = described_class.transform(html)

        expect(result).to include('data-component="HelloWorld"')
      end

      it 'extracts props from attributes' do
        html = "<TestComponent name='React' count='42' />"

        allow(ReactiveViews::Renderer).to receive(:render) do |component, props|
          expect(component).to eq('TestComponent')
          expect(props['name']).to eq('React')
          expect(props['count']).to eq(42) # Should parse as number
          '<div>Rendered</div>'
        end

        described_class.transform(html)
      end

      it 'parses JSON props correctly' do
        html = %(<DataComponent items='["a","b","c"]' config='{"enabled":true}' />)

        allow(ReactiveViews::Renderer).to receive(:render) do |component, props|
          expect(props['items']).to eq(%w[a b c])
          expect(props['config']).to eq({ 'enabled' => true })
          '<div>Rendered</div>'
        end

        described_class.transform(html)
      end

      it 'creates script tag with props' do
        allow(ReactiveViews::Renderer).to receive(:batch_render).and_return([
                                                                              { html: '<div>Content</div>' }
                                                                            ])

        html = "<MyComponent data='test' />"
        result = described_class.transform(html)

        expect(result).to include('<script type="application/json"')
        expect(result).to include('data-island-uuid')
        expect(result).to include('"data":"test"')
      end

      it 'does not create script tag when component has no props' do
        allow(ReactiveViews::Renderer).to receive(:batch_render).and_return([
                                                                              { html: '<div>Content</div>' }
                                                                            ])

        html = '<MyComponent />'
        result = described_class.transform(html)

        # Should have the component container
        expect(result).to include('data-component="MyComponent"')
        expect(result).to include('data-island-uuid')

        # But should NOT have a script tag
        expect(result).not_to include('<script type="application/json"')
      end

      it 'aggregates scripts before closing body tag when body tag exists' do
        # Mock component resolution
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/component.tsx')

        # Mock batch render
        allow(ReactiveViews::Renderer).to receive(:batch_render).and_return([
                                                                              { html: '<div>Component 1</div>' },
                                                                              { html: '<div>Component 2</div>' }
                                                                            ])

        # NOTE: Nokogiri HTML5.fragment preserves body tags in some contexts
        # but the key is that scripts should be aggregated, not inline
        html = "<html><body><MyComponent data='test' /><Another prop='value' /></body></html>"
        result = described_class.transform(html)

        # Should have 2 script tags
        expect(result.scan(%r{<script type="application/json"}).size).to eq(2)

        # Components should be rendered
        expect(result).to include('Component 1')
        expect(result).to include('Component 2')

        # Scripts should be aggregated at the end (after components)
        # They should NOT be inline with the components
        component_1_pos = result.index('Component 1')
        component_2_pos = result.index('Component 2')
        first_script_pos = result.index('<script')

        # Scripts should come after both components
        expect(first_script_pos).to be > component_1_pos
        expect(first_script_pos).to be > component_2_pos
      end

      it 'handles multiple components' do
        # Nokogiri HTML5 parser treats self-closing custom elements specially
        # Use closing tags to ensure proper parsing
        html = '<div><ComponentA></ComponentA><ComponentB></ComponentB></div>'

        # Mock component resolution
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/component.tsx')

        # Stub batch render (batch rendering is used for multiple components)
        allow(ReactiveViews::Renderer).to receive(:batch_render).and_return([
                                                                              { html: '<div>SSR Content A</div>' },
                                                                              { html: '<div>SSR Content B</div>' }
                                                                            ])

        result = described_class.transform(html)

        # Both components should be transformed
        expect(result).to include('data-component="ComponentA"')
        expect(result).to include('SSR Content A')
        expect(result).to include('data-component="ComponentB"')
        expect(result).to include('SSR Content B')
      end
    end

    context 'with standard HTML tags' do
      it 'ignores standard HTML elements' do
        html = '<html><body><div><p>Hello</p></div></body></html>'
        result = described_class.transform(html)

        expect(result).to include('<p>Hello</p>')
        expect(result).not_to include('data-island-uuid')
      end
    end

    context 'when SSR fails' do
      before do
        # Mock component resolution to succeed
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/component.tsx')

        # Mock batch_render to return error
        allow(ReactiveViews::Renderer).to receive(:batch_render)
          .and_return([{ error: 'Component failed to render' }])
      end

      it 'generates error overlay in development' do
        env_double = double('environment', development?: true, production?: false)
        stub_const('Rails', Class.new do
          define_singleton_method(:env) { env_double }
        end)

        allow(ReactiveViews::ErrorOverlay).to receive(:generate)
          .and_return("<div class='error'>Error overlay</div>")

        html = '<FailingComponent />'
        result = described_class.transform(html)

        expect(result).to include('Error overlay')
      end

      it 'renders minimal error in production' do
        env_double = double('environment', development?: false, production?: true)
        stub_const('Rails', Class.new do
          define_singleton_method(:env) { env_double }
        end)

        html = '<FailingComponent />'
        result = described_class.transform(html)

        expect(result).to include('data-reactive-views-error="true"')
        expect(result).to include('display: none')
      end
    end

    context 'when transformation errors occur' do
      it 'returns original HTML on error' do
        html = '<ValidHTML><p>Content</p></ValidHTML>'

        allow(Nokogiri::HTML5).to receive(:fragment).and_raise(StandardError, 'Parse error')

        result = described_class.transform(html)
        expect(result).to eq(html)
      end

      it 'logs errors when Rails is defined' do
        html = '<Component />'
        logger = instance_double(Logger, error: nil)

        rails_stub = Class.new do
          class << self
            attr_accessor :logger
          end
        end
        rails_stub.logger = logger

        stub_const('Rails', rails_stub)

        allow(Nokogiri::HTML5).to receive(:fragment).and_raise(StandardError, 'Test error')

        described_class.transform(html)

        expect(logger).to have_received(:error).at_least(:once)
      end
    end
  end
end
