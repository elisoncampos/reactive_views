# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactiveViews::PropsBuilder do
  let(:controller) do
    double('Controller').tap do |ctrl|
      allow(ctrl).to receive(:reactive_view_props).and_return(explicit_props)
    end
  end
  let(:explicit_props) { { extra: 'value' } }
  let(:assigns) { { 'user' => 'Alice', 'count' => 3 } }
  let(:view_context) do
    double('ViewContext',
           controller: controller,
           assigns: assigns)
  end
  let(:content) { '<Component user="user" count={count} />' }

  around do |example|
    original = ReactiveViews.config.props_inference_enabled
    example.run
    ReactiveViews.config.props_inference_enabled = original
  end

  describe '.build' do
    context 'when props inference is disabled' do
      before { ReactiveViews.config.props_inference_enabled = false }

      it 'returns assigns merged with explicit props' do
        props = described_class.build(view_context, content)
        expect(props).to include(user: 'Alice', count: 3, extra: 'value')
      end
    end

    context 'when props inference is enabled' do
      before do
        ReactiveViews.config.props_inference_enabled = true
        allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return(%w[user])
      end

      it 'filters assigns to inferred keys but keeps explicit props' do
        props = described_class.build(view_context, content)
        expect(props).to eq(user: 'Alice', extra: 'value')
      end

      it 'falls back to all assigns when inference returns no keys' do
        allow(ReactiveViews::PropsInference).to receive(:infer_props).and_return([])
        props = described_class.build(view_context, content)
        expect(props).to include(user: 'Alice', count: 3, extra: 'value')
      end
    end
  end
end
