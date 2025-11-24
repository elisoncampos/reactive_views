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
      controller_name: 'users',
      action_name: 'index',
      respond_to?: false
    )
  end

  let(:view_context_double) do
    double('ViewContext').tap do |vc|
      # Stub lookup_context to return nil so we use the fallback path in tests
      allow(vc).to receive(:respond_to?).with(:lookup_context).and_return(false)
      allow(vc).to receive(:assigns).and_return(view_assigns)
    end
  end
  let(:view_assigns) { { 'users' => [ { id: 1, name: 'Alice' } ] } }
  let(:template_path) { '/path/to/template.tsx.erb' }
  let(:tsx_content) { 'export default function Page({ users }) { return <div />; }' }
  let(:temp_file) { ReactiveViews::TempFileManager::TempFile.new('/tmp/reactive_views_full_page/page.tsx') }
  let(:bundle_result) { { html: '<div>SSR</div>', bundle_key: 'bundle-123' } }

  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.props_inference_enabled = true
      config.ssr_url = 'http://ssr.test:5175'
    end

    allow(File).to receive(:read).with(template_path).and_return('export default function() {}')
    allow(view_context_double).to receive(:controller).and_return(controller_double)

    allow(ReactiveViews::TempFileManager).to receive(:write).and_return(temp_file)
    allow(temp_file).to receive(:delete)
    allow(SecureRandom).to receive(:uuid).and_return('test-uuid')
  end

  describe '.render' do
    it 'builds props from view assigns and calls SSR' do
      mock_template = double('Template')
      allow(ActionView::Template).to receive(:new).and_return(mock_template)
      allow(ActionView::Template).to receive(:handler_for_extension).with('erb').and_return(double)
      allow(mock_template).to receive(:render).and_return(tsx_content)

      allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return([ 'users' ])
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata).and_return(bundle_result)

      result = described_class.render(controller_double, template_full_path: template_path)

      expect(result).to include('data-reactive-page="true"')
      expect(result).to include('data-page-uuid="test-uuid"')
      expect(result).to include('<div data-reactive-page="true" data-page-uuid="test-uuid"><div>SSR</div></div>')

      script_match = result.match(/<script type="application\/json" data-page-uuid="test-uuid">(.*?)<\/script>/)
      expect(script_match).to be_present
      metadata = JSON.parse(script_match[1])
      expect(metadata['bundle']).to eq('bundle-123')
      expect(metadata['props']).to include('users')
      expect(ReactiveViews::Renderer).to have_received(:render_path_with_metadata).with(
        temp_file.path,
        hash_including(users: [ { id: 1, name: 'Alice' } ])
      )
    end

    it 'filters props based on inference' do
      view_assigns_with_extras = {
        'users' => [ { id: 1 } ],
        'secret' => 'should_not_pass'
      }
      allow(controller_double).to receive(:view_assigns).and_return(view_assigns_with_extras)

      mock_template = double('Template')
      allow(ActionView::Template).to receive(:new).and_return(mock_template)
      allow(ActionView::Template).to receive(:handler_for_extension).with('erb').and_return(double)
      allow(mock_template).to receive(:render).and_return(tsx_content)

      allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return([ 'users' ])

      received_props = nil
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata) do |_path, props|
        received_props = props
        { html: '<div />', bundle_key: 'bundle-123' }
      end

      described_class.render(controller_double, template_full_path: template_path)

      expect(received_props.keys).to eq([ :users ])
      expect(received_props.keys).not_to include(:secret)
    end

    it 'strips Rails annotation comments before SSR' do
      annotated = ActionView::OutputBuffer.new <<~TSX
        <!-- BEGIN app/views/users/index.tsx.erb -->
        export default function Page() { return <div>Hi</div>; }
        <!-- END app/views/users/index.tsx.erb -->
      TSX

      mock_template = double('Template')
      handler = double
      allow(ActionView::Template).to receive(:handler_for_extension).with('erb').and_return(handler)
      allow(ActionView::Template).to receive(:new).and_return(mock_template)
      allow(mock_template).to receive(:render).and_return(annotated)

      written_content = nil
      allow(ReactiveViews::TempFileManager).to receive(:write) do |content, **_|
        written_content = content
        temp_file
      end

      allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return([])
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata).and_return(bundle_result)

      described_class.render(controller_double, template_full_path: template_path)

      expect(written_content).not_to include('BEGIN app/views')
      expect(written_content).not_to include('END app/views')
      expect(written_content).to include('export default function Page')
    end
  end
end
