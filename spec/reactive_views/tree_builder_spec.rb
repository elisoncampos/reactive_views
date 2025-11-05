# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ReactiveViews::TagTransformer Tree Building' do
  describe '.build_component_tree' do
    def preprocess_html(html)
      # Apply same preprocessing as transform method
      html.gsub(%r{<([A-Z][a-zA-Z0-9]*)\s*([^>]*?)/\s*>}, '<\1 \2></\1>')
    end

    it 'identifies root components correctly' do
      html = '<div><Component1></Component1><Component2><Component3></Component3></Component2></div>'
      processed_html = preprocess_html(html)
      doc = Nokogiri::HTML5.fragment(processed_html)
      component_name_map = { 'component1' => 'Component1', 'component2' => 'Component2', 'component3' => 'Component3' }

      tree_result = ReactiveViews::TagTransformer.send(:build_component_tree, doc, component_name_map)

      # Only Component1 and Component2 are roots (Component3 is nested)
      expect(tree_result[:nodes].size).to eq(2)
      expect(tree_result[:has_nesting]).to be true
    end

    it 'builds nested component tree' do
      html = '<div><Component1></Component1><Component2><Component3></Component3></Component2></div>'
      processed_html = preprocess_html(html)
      doc = Nokogiri::HTML5.fragment(processed_html)
      component_name_map = { 'component1' => 'Component1', 'component2' => 'Component2', 'component3' => 'Component3' }

      tree_result = ReactiveViews::TagTransformer.send(:build_component_tree, doc, component_name_map)

      # Find Component2 in tree
      component2_node = tree_result[:nodes].find { |node| node[:component_name] == 'Component2' }

      expect(component2_node).not_to be_nil
      expect(component2_node[:children].size).to eq(1)
      expect(component2_node[:children][0][:component_name]).to eq('Component3')
    end

    it 'detects nesting correctly' do
      nested_html = '<Component1><Component2></Component2></Component1>'
      processed_html = preprocess_html(nested_html)
      nested_doc = Nokogiri::HTML5.fragment(processed_html)
      component_name_map = { 'component1' => 'Component1', 'component2' => 'Component2' }

      tree_result = ReactiveViews::TagTransformer.send(:build_component_tree, nested_doc, component_name_map)

      expect(tree_result[:has_nesting]).to be true
    end

    it 'reports no nesting for flat layouts' do
      flat_html = '<Component1></Component1><Component2></Component2>'
      processed_html = preprocess_html(flat_html)
      flat_doc = Nokogiri::HTML5.fragment(processed_html)
      component_name_map = { 'component1' => 'Component1', 'component2' => 'Component2' }

      tree_result = ReactiveViews::TagTransformer.send(:build_component_tree, flat_doc, component_name_map)

      expect(tree_result[:has_nesting]).to be false
    end

    it 'preserves HTML children' do
      html_with_content = '<Component1><div>Hello</div></Component1>'
      processed_html = preprocess_html(html_with_content)
      doc_with_content = Nokogiri::HTML5.fragment(processed_html)
      component_name_map = { 'component1' => 'Component1' }

      tree_result = ReactiveViews::TagTransformer.send(:build_component_tree, doc_with_content, component_name_map)

      component1_node = tree_result[:nodes][0]
      expect(component1_node[:html_children]).not_to be_empty
    end
  end

  describe '.calculate_tree_depth' do
    it 'returns 0 for empty tree' do
      depth = ReactiveViews::TagTransformer.send(:calculate_tree_depth, [])
      expect(depth).to eq(0)
    end

    it 'returns 1 for flat components' do
      tree_nodes = [
        { component_name: 'Component1', children: [] },
        { component_name: 'Component2', children: [] }
      ]

      depth = ReactiveViews::TagTransformer.send(:calculate_tree_depth, tree_nodes)
      expect(depth).to eq(1)
    end

    it 'calculates depth for nested components' do
      tree_nodes = [
        {
          component_name: 'Component1',
          children: [
            {
              component_name: 'Component2',
              children: [
                { component_name: 'Component3', children: [] }
              ]
            }
          ]
        }
      ]

      depth = ReactiveViews::TagTransformer.send(:calculate_tree_depth, tree_nodes)
      expect(depth).to eq(3)
    end
  end

  describe '.build_tree_spec' do
    it 'builds spec for component without children' do
      tree_node = {
        component_name: 'Component1',
        props: { title: 'Hello' },
        children: [],
        html_children: []
      }

      spec = ReactiveViews::TagTransformer.send(:build_tree_spec, tree_node)

      expect(spec[:component_name]).to eq('Component1')
      expect(spec[:props]).to eq({ title: 'Hello' })
      expect(spec[:children]).to eq([])
      expect(spec[:html_children]).to eq('')
    end

    it 'builds spec for component with children' do
      tree_node = {
        component_name: 'Outer',
        props: {},
        children: [
          {
            component_name: 'Inner',
            props: {},
            children: [],
            html_children: []
          }
        ],
        html_children: []
      }

      spec = ReactiveViews::TagTransformer.send(:build_tree_spec, tree_node)

      expect(spec[:component_name]).to eq('Outer')
      expect(spec[:children].size).to eq(1)
      expect(spec[:children][0][:component_name]).to eq('Inner')
    end
  end
end
