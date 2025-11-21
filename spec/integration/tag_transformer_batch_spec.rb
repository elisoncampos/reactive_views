# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TagTransformer Batch Rendering Integration', type: :request do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = 'http://localhost:5175'
    end
  end

  describe 'batch rendering multiple components' do
    let(:html_with_multiple_components) do
      <<~HTML
        <div>
          <Component1 title="First" />
          <Component2 count="42" />
          <Component3 data='["a", "b", "c"]' />
        </div>
      HTML
    end

    context 'when all components render successfully' do
      before do
        # Resolve all components
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component1').and_return('/path/to/Component1.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component2').and_return('/path/to/Component2.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component3').and_return('/path/to/Component3.tsx')

        # Stub batch render endpoint
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: {
            results: [
              { html: '<div>Component 1 rendered</div>' },
              { html: '<div>Component 2 rendered</div>' },
              { html: '<div>Component 3 rendered</div>' }
            ]
          }.to_json)
      end

      it 'makes only ONE HTTP request for all components' do
        ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
        expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/render')
      end

      it 'renders all components' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('data-component="Component1"')
        expect(result).to include('data-component="Component2"')
        expect(result).to include('data-component="Component3"')
      end

      it 'includes SSR HTML for each component' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('Component 1 rendered')
        expect(result).to include('Component 2 rendered')
        expect(result).to include('Component 3 rendered')
      end

      it 'creates island containers for each component' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # Count island containers (divs + script tags)
        island_count = result.scan('data-island-uuid').size
        expect(island_count).to eq(6) # 3 divs + 3 script tags
      end

      it 'creates props script tags for each component' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # Should have 3 script tags with props
        script_tags = result.scan(%r{<script type="application/json"}).size
        expect(script_tags).to eq(3)
      end

      it 'places all scripts at the end, aggregated together' do
        html_with_body = <<~HTML
          <html><body><div>
            <Component1 title="First" />
            <Component2 count="42" />
            <Component3 data='["a", "b", "c"]' />
          </div></body></html>
        HTML

        result = ReactiveViews::TagTransformer.transform(html_with_body)

        # Should have 3 script tags
        script_count = result.scan('<script').size
        expect(script_count).to eq(3)

        # Scripts should be aggregated at the end (after all components)
        last_component_pos = result.rindex('data-component=')
        first_script_pos = result.index('<script')
        expect(first_script_pos).to be > last_component_pos

        # All three scripts should be adjacent (no components between them)
        scripts_section = result[first_script_pos..]
        expect(scripts_section).not_to include('data-component=')
      end

      it 'preserves component order' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # Extract data-component attributes in order
        components = result.scan(/data-component="([^"]+)"/).flatten

        expect(components).to eq(%w[Component1 Component2 Component3])
      end

      it 'assigns unique UUIDs to each island' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # Extract all UUIDs
        uuids = result.scan(/data-island-uuid="([^"]+)"/).flatten

        # Should have 6 UUID references (3 divs + 3 scripts)
        expect(uuids.size).to eq(6)

        # Should only have 3 unique UUIDs (each used twice)
        expect(uuids.uniq.size).to eq(3)
      end
    end

    context 'when one component fails to render' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component1').and_return('/path/to/Component1.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component2').and_return('/path/to/Component2.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component3').and_return('/path/to/Component3.tsx')

        # Second component fails
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: {
            results: [
              { html: '<div>Success</div>' },
              { error: 'Component 2 failed: data.map is not a function' },
              { html: '<div>Success</div>' }
            ]
          }.to_json)
      end

      it 'still renders successful components' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('data-component="Component1"')
        expect(result).to include('data-component="Component3"')
      end

      it 'shows error overlay for failed component in development' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('ReactiveViews SSR Error')
        expect(result).to include('Component2')
        expect(result).to include('data.map is not a function')
      end

      it 'does not break rendering of subsequent components' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # First component should render
        expect(result).to include('Success')

        # Second shows error
        expect(result).to include('SSR Error')

        # Third still renders
        expect(result).to include('data-component="Component3"')
      end

      it 'makes only one batch request despite errors' do
        ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once
      end
    end

    context 'when one component cannot be resolved' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component1').and_return('/path/to/Component1.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component2').and_return(nil) # Cannot be resolved
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Component3').and_return('/path/to/Component3.tsx')

        # Only 2 components sent to batch render (the resolved ones)
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: {
            results: [
              { html: '<div>Component 1</div>' },
              { html: '<div>Component 3</div>' }
            ]
          }.to_json)
      end

      it 'shows error for unresolved component' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('ReactiveViews SSR Error')
        expect(result).to include('Component2')
        expect(result).to include('not found')
      end

      it 'still renders other components' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('data-component="Component1"')
        expect(result).to include('data-component="Component3"')
      end
    end

    context 'with many components on page' do
      let(:html_with_many_components) do
        <<~HTML
          <div>
            <C1 />
            <C2 />
            <C3 />
            <C4 />
            <C5 />
          </div>
        HTML
      end

      before do
        (1..5).each do |i|
          allow(ReactiveViews::ComponentResolver).to receive(:resolve)
            .with("C#{i}").and_return("/path/to/C#{i}.tsx")
        end

        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 200, body: {
            results: (1..5).map { |i| { html: "<div>C#{i}</div>" } }
          }.to_json)
      end

      it 'renders all 5 components in one request' do
        result = ReactiveViews::TagTransformer.transform(html_with_many_components)

        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once

        (1..5).each do |i|
          expect(result).to include("data-component=\"C#{i}\"")
        end
      end

      it 'is more efficient than individual requests' do
        # This test documents the performance benefit
        ReactiveViews::TagTransformer.transform(html_with_many_components)

        # Only ONE request for 5 components
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once

        # Would have been 5 requests without batch rendering
        expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/render')
      end
    end

    context 'when batch request fails entirely' do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return('/path/to/Component.tsx')

        # Batch endpoint fails
        stub_request(:post, 'http://localhost:5175/batch-render')
          .to_return(status: 500, body: 'Server Error')

        # Fallback to individual rendering
        stub_request(:post, 'http://localhost:5175/render')
          .to_return(status: 200, body: {
            html: '<div>Individual render</div>'
          }.to_json)
      end

      it 'falls back to individual rendering' do
        ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        # Tried batch first
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/batch-render').once

        # Then fell back to individual for each component
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render').times(3)
      end

      it 'still renders all components via fallback' do
        result = ReactiveViews::TagTransformer.transform(html_with_multiple_components)

        expect(result).to include('data-component="Component1"')
        expect(result).to include('data-component="Component2"')
        expect(result).to include('data-component="Component3"')
      end
    end

    context 'with nested components' do
      let(:html_with_nested) do
        <<~HTML
          <div>
            <Outer>
              <Inner />
            </Outer>
          </div>
        HTML
      end

      it 'transforms nested components using tree rendering' do
        # Mock resolution for both components
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Outer').and_return('/path/to/Outer.tsx')
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .with('Inner').and_return('/path/to/Inner.tsx')

        # Nested components use tree rendering endpoint
        stub_request(:post, 'http://localhost:5175/render-tree')
          .to_return(status: 200, body: {
            html: '<div>Outer with Inner content</div>'
          }.to_json)

        result = ReactiveViews::TagTransformer.transform(html_with_nested)

        # Only outer component should have island marker (tree is rendered as one)
        expect(result).to include('data-component="Outer"')
        expect(result).to include('Outer with Inner content')

        # Should use tree rendering, not batch rendering
        expect(WebMock).to have_requested(:post, 'http://localhost:5175/render-tree').once
        expect(WebMock).not_to have_requested(:post, 'http://localhost:5175/batch-render')
      end
    end
  end
end
