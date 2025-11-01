# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/reactive_views"

RSpec.describe ReactiveViews::Renderer do
  let(:component_name) { "TestComponent" }
  let(:props) { { message: "Hello", count: 42 } }

  before do
    ReactiveViews.configure do |config|
      config.ssr_url = "http://localhost:5175"
      config.ssr_timeout = 5
      config.component_views_paths = ["app/views/components"]
      config.component_js_paths = ["app/javascript/components"]
    end
  end

  describe ".render" do
    context "when component cannot be resolved" do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(nil)
      end

      it "returns error marker" do
        result = described_class.render(component_name, props)
        expect(result).to start_with("___REACTIVE_VIEWS_ERROR___")
      end

      it "includes error message in marker with searched paths" do
        result = described_class.render(component_name, props)
        expect(result).to include("not found")
        expect(result).to include("Searched in:")
      end
    end

    context "when SSR server is available" do
      let(:component_path) { "/path/to/TestComponent.tsx" }
      let(:ssr_response) { { "html" => "<div>SSR Content</div>", "error" => nil }.to_json }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, "http://localhost:5175/render")
          .with(
            body: hash_including(
              "componentPath" => component_path,
              "props" => props
            )
          )
          .to_return(status: 200, body: ssr_response)
      end

      it "makes POST request to SSR server" do
        described_class.render(component_name, props)

        expect(WebMock).to have_requested(:post, "http://localhost:5175/render")
      end

      it "sends component path and props" do
        described_class.render(component_name, props)

        expect(WebMock).to have_requested(:post, "http://localhost:5175/render")
          .with(body: hash_including("componentPath" => component_path))
      end

      it "returns rendered HTML" do
        result = described_class.render(component_name, props)
        expect(result).to eq("<div>SSR Content</div>")
      end
    end

    context "when SSR server returns error" do
      let(:component_path) { "/path/to/TestComponent.tsx" }
      let(:error_response) { { "html" => nil, "error" => "Render failed" }.to_json }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, "http://localhost:5175/render")
          .to_return(status: 200, body: error_response)
      end

      it "returns error marker" do
        result = described_class.render(component_name, props)
        expect(result).to start_with("___REACTIVE_VIEWS_ERROR___")
      end

      it "includes server error message" do
        result = described_class.render(component_name, props)
        expect(result).to include("Render failed")
      end
    end

    context "when SSR server is unavailable" do
      let(:component_path) { "/path/to/TestComponent.tsx" }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, "http://localhost:5175/render")
          .to_timeout
      end

      it "returns error marker" do
        result = described_class.render(component_name, props)
        expect(result).to start_with("___REACTIVE_VIEWS_ERROR___")
      end

      it "includes timeout error" do
        result = described_class.render(component_name, props)
        expect(result).to match(/timed out|timeout|unavailable/i)
      end
    end

    context "when SSR server returns non-200 status" do
      let(:component_path) { "/path/to/TestComponent.tsx" }

      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(component_path)

        stub_request(:post, "http://localhost:5175/render")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it "returns error marker" do
        result = described_class.render(component_name, props)
        expect(result).to start_with("___REACTIVE_VIEWS_ERROR___")
      end
    end
  end
end
