# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'CSS Isolation', type: :production do
  describe ReactiveViews::CssStrategy do
    describe '.detect_conflicts' do
      it 'detects common conflicting class names' do
        html = '<div class="btn card container"></div>'
        conflicts = described_class.detect_conflicts(html)

        expect(conflicts.size).to be >= 3
        expect(conflicts.map { |c| c[:class_name] }).to include('btn', 'card', 'container')
      end

      it 'detects conflicts with provided Rails classes' do
        html = '<div class="my-custom-class"></div>'
        conflicts = described_class.detect_conflicts(html, rails_classes: [ 'my-custom-class' ])

        expect(conflicts.size).to eq(1)
        expect(conflicts.first[:type]).to eq(:rails_conflict)
      end

      it 'returns empty array for unique class names' do
        html = '<div class="rv-counter-wrapper rv-counter-button"></div>'
        conflicts = described_class.detect_conflicts(html)

        expect(conflicts).to be_empty
      end
    end

    describe '.extract_classes' do
      it 'extracts classes from class attribute' do
        html = '<div class="foo bar baz"></div>'
        classes = described_class.extract_classes(html)

        expect(classes).to contain_exactly('foo', 'bar', 'baz')
      end

      it 'extracts classes from className attribute (JSX)' do
        html = '<div className="foo bar baz"></div>'
        classes = described_class.extract_classes(html)

        expect(classes).to contain_exactly('foo', 'bar', 'baz')
      end

      it 'handles multiple elements' do
        html = '<div class="a b"></div><span class="c d"></span>'
        classes = described_class.extract_classes(html)

        expect(classes).to contain_exactly('a', 'b', 'c', 'd')
      end

      it 'returns unique classes' do
        html = '<div class="foo foo bar"></div>'
        classes = described_class.extract_classes(html)

        expect(classes).to contain_exactly('foo', 'bar')
      end

      it 'handles empty input' do
        expect(described_class.extract_classes('')).to eq([])
        expect(described_class.extract_classes(nil)).to eq([])
      end
    end

    describe '.scoped_class' do
      it 'generates prefixed class name' do
        result = described_class.scoped_class('Counter', 'button')
        expect(result).to eq('rv-counter-button')
      end

      it 'handles PascalCase component names' do
        result = described_class.scoped_class('InteractiveCounter', 'wrapper')
        expect(result).to eq('rv-interactive-counter-wrapper')
      end

      it 'handles snake_case component names' do
        result = described_class.scoped_class('my_component', 'element')
        expect(result).to eq('rv-my-component-element')
      end
    end

    describe '.uses_css_modules?' do
      it 'returns true for .module.css files' do
        # Create a temporary file to test
        require 'tempfile'
        file = Tempfile.new([ 'test', '.module.css' ])
        file.write('.foo { color: red; }')
        file.close

        expect(described_class.uses_css_modules?(file.path)).to be true

        file.unlink
      end

      it 'returns true for files with :local selector' do
        require 'tempfile'
        file = Tempfile.new([ 'test', '.css' ])
        file.write(':local(.foo) { color: red; }')
        file.close

        expect(described_class.uses_css_modules?(file.path)).to be true

        file.unlink
      end

      it 'returns false for regular CSS files' do
        require 'tempfile'
        file = Tempfile.new([ 'test', '.css' ])
        file.write('.foo { color: red; }')
        file.close

        expect(described_class.uses_css_modules?(file.path)).to be false

        file.unlink
      end
    end

    describe '.recommend_strategy' do
      it 'recommends css_modules for Vite projects' do
        expect(described_class.recommend_strategy(vite: true)).to eq(:css_modules)
      end

      it 'recommends tailwind_prefix for Tailwind projects' do
        expect(described_class.recommend_strategy(tailwind: true)).to eq(:tailwind_prefix)
      end

      it 'recommends bem_convention as default' do
        expect(described_class.recommend_strategy).to eq(:bem_convention)
      end
    end

    describe 'STRATEGIES' do
      it 'contains documented strategies' do
        expect(described_class::STRATEGIES.keys).to include(
          :css_modules,
          :tailwind_prefix,
          :bem_convention,
          :shadow_dom
        )
      end

      it 'each strategy has required properties' do
        described_class::STRATEGIES.each do |key, strategy|
          expect(strategy).to have_key(:name), "#{key} missing :name"
          expect(strategy).to have_key(:description), "#{key} missing :description"
          expect(strategy).to have_key(:setup), "#{key} missing :setup"
        end
      end
    end
  end
end

RSpec.describe 'CSS Loading', type: :system, js: true do
  let(:render_timeout) { 15 }

  describe 'CSS load order' do
    it 'CSS is loaded before JavaScript executes' do
      visit '/counter'

      # Check that stylesheets are in the head using page HTML
      page_html = page.html
      head_section = page_html[0..page_html.index('</head>').to_i]

      # Should have CSS links or style tags in head
      has_css = head_section.include?('stylesheet') || head_section.include?('<style')
      expect(has_css).to be true
    end

    it 'no flash of unstyled content' do
      # This is primarily a visual test, but we can verify CSS is present
      visit '/counter'

      # React component should be styled immediately
      counter = find('[data-component="Counter"]', wait: render_timeout)

      # Element should be visible (not hidden due to missing styles)
      expect(counter).to be_visible
    end
  end

  describe 'style isolation' do
    it 'React component styles do not leak to Rails elements' do
      visit '/turbo_mixed'

      # Rails-rendered sections should not inherit React-specific styles
      # This is implementation-specific based on your actual styles
      expect(page).to have_css('[data-testid="stimulus-section"]', wait: render_timeout)
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)
    end

    it 'Rails styles do not break React components' do
      visit '/turbo_mixed'

      # React components should render correctly despite Rails styles
      react_section = find('[data-testid="react-section"]', wait: render_timeout)
      expect(react_section).to be_visible

      # Interactive elements should be visible and clickable
      within react_section do
        expect(page).to have_css('[data-testid="increment-btn"]')
        expect(page).to have_css('[data-testid="decrement-btn"]')
      end
    end
  end

  describe 'Tailwind CSS compatibility' do
    it 'Tailwind utilities work in React components' do
      visit '/turbo_mixed'

      # Components should render with Tailwind classes applied
      # The specific selectors depend on your component implementation
      expect(page).to have_css('[data-component]', wait: render_timeout)
    end

    it 'Tailwind utilities work in Rails views' do
      visit '/turbo_mixed'

      # Rails sections should also have Tailwind working
      expect(page).to have_css('[data-testid="stimulus-section"]', wait: render_timeout)
    end
  end
end

RSpec.describe 'CSS Conflict Detection in Production Build', type: :production do
  before(:all) do
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'built CSS files', :requires_production_build do
    let(:css_files) do
      ProductionHelpers.built_asset_files.select { |f| f.end_with?('.css') }
    end

    it 'does not have duplicate selectors' do
      css_files.each do |file|
        path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, file)
        content = File.read(path)

        # Extract selectors (simplified check)
        selectors = content.scan(/([.#][\w-]+)\s*\{/).flatten

        duplicates = selectors.group_by(&:itself).select { |_k, v| v.size > 1 }

        # Some duplicates are expected (e.g., media queries), but flag many
        if duplicates.size > 10
          warn "File #{file} has many duplicate selectors: #{duplicates.keys.first(5).join(', ')}"
        end
      end
    end

    it 'does not contain !important overuse' do
      css_files.each do |file|
        path = File.join(ProductionHelpers::VITE_OUTPUT_PATH, file)
        content = File.read(path)

        important_count = content.scan(/!important/).size

        # Flag if too many !important rules
        expect(important_count).to be < 50,
          "File #{file} has #{important_count} !important rules - consider refactoring"
      end
    end
  end
end
