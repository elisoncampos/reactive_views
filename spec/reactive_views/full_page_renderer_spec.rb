# frozen_string_literal: true

require 'spec_helper'
require 'active_support/core_ext/hash'
require 'action_view'
require_relative '../../lib/reactive_views'
require_relative '../../lib/reactive_views/full_page_renderer'

RSpec.describe ReactiveViews::FullPageRenderer do
  let(:controller_double) do
    double(
      'Controller',
      view_context: view_context_double,
      view_assigns: view_assigns,
      controller_path: 'users',
      action_name: 'index',
      respond_to?: false
    )
  end

  let(:view_context_double) do
    double('ViewContext').tap do |vc|
      # Stub lookup_context to return nil so we use the fallback path in tests
      allow(vc).to receive(:respond_to?).with(:lookup_context).and_return(false)
    end
  end
  let(:view_assigns) { { 'users' => [{ id: 1, name: 'Alice' }] } }
  let(:template_path) { '/path/to/template.tsx.erb' }
  let(:tsx_content) { 'export default function Page({ users }) { return <div />; }' }

  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.props_inference_enabled = true
    end

    allow(File).to receive(:read).with(template_path).and_return('export default function() {}')
    allow(File).to receive(:write)
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:delete)
  end

  describe '.render' do
    it 'builds props from view assigns and calls SSR' do
      mock_template = double('Template')
      allow(ActionView::Template).to receive(:new).and_return(mock_template)
      allow(ActionView::Template).to receive(:handler_for_extension).with('erb').and_return(double)
      allow(mock_template).to receive(:render).and_return(tsx_content)

      allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return(['users'])
      allow(ReactiveViews::Renderer).to receive(:render_path).and_return('<div>SSR</div>')

      result = described_class.render(controller_double, template_full_path: template_path)

      expect(result).to eq('<div>SSR</div>')
      expect(ReactiveViews::Renderer).to have_received(:render_path).with(
        a_string_matching(/\.tsx$/),
        hash_including(users: [{ id: 1, name: 'Alice' }])
      )
    end

    it 'filters props based on inference' do
      view_assigns_with_extras = {
        'users' => [{ id: 1 }],
        'secret' => 'should_not_pass'
      }
      allow(controller_double).to receive(:view_assigns).and_return(view_assigns_with_extras)

      mock_template = double('Template')
      allow(ActionView::Template).to receive(:new).and_return(mock_template)
      allow(ActionView::Template).to receive(:handler_for_extension).with('erb').and_return(double)
      allow(mock_template).to receive(:render).and_return(tsx_content)

      allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return(['users'])

      received_props = nil
      allow(ReactiveViews::Renderer).to receive(:render_path) do |_path, props|
        received_props = props
        '<div />'
      end

      described_class.render(controller_double, template_full_path: template_path)

      expect(received_props.keys).to eq([:users])
      expect(received_props.keys).not_to include(:secret)
    end
  end
end
