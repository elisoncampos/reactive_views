# frozen_string_literal: true

RSpec.shared_context "with test component" do
  let(:component_name) { "TestComponent" }
  let(:component_path) { File.join(test_components_dir, "#{component_name}.tsx") }
  let(:test_components_dir) { File.join(__dir__, "..", "fixtures", "components") }

  let(:simple_component_code) do
    <<~TSX
      import React from 'react';

      interface Props {
        message: string;
      }

      export default function TestComponent({ message }: Props) {
        return <div className="test-component">{message}</div>;
      }
    TSX
  end

  before do
    FileUtils.mkdir_p(test_components_dir)
    File.write(component_path, simple_component_code) unless File.exist?(component_path)
  end
end

RSpec.shared_context "with rails controller" do
  let(:controller) do
    Class.new(ActionController::Base) do
      include ReactiveViewsHelper

      def index
        render inline: "<html><head></head><body><TestComponent message='hello' /></body></html>"
      end
    end
  end
end

RSpec.shared_context "with mock ssr server" do
  before do
    allow(ReactiveViews::Renderer).to receive(:render).and_return("<div>Mocked SSR</div>")
  end
end
