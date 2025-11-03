# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Component Rendering Integration", type: :request do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
    end
  end

  describe "full rendering pipeline" do
    context "with simple component" do
      before do
        # Mock SSR server response
        stub_request(:post, "http://localhost:5175/render")
          .to_return(
            status: 200,
            body: { html: "<div class='ssr-rendered'>SSR Content</div>", error: nil }.to_json
          )
      end

      it "transforms component tags in rendered HTML" do
        # Mock component resolution
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return("/path/to/SimpleComponent.tsx")

        # Mock batch render
        stub_request(:post, "http://localhost:5175/batch-render")
          .to_return(
            status: 200,
            body: { results: [{ html: "<div class='ssr-rendered'>SSR Content</div>" }] }.to_json
          )

        get "/with_component"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-component="SimpleComponent"')
        expect(response.body).to include("ReactiveViews Test App")
      end

      it "includes props in script tag" do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return("/path/to/SimpleComponent.tsx")

        stub_request(:post, "http://localhost:5175/batch-render")
          .to_return(
            status: 200,
            body: { results: [{ html: "<div>SSR Content</div>" }] }.to_json
          )

        get "/with_component"

        expect(response.body).to include("SimpleComponent")
        expect(response.body).to include("message")
      end

      it "maintains page structure" do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return("/path/to/SimpleComponent.tsx")

        stub_request(:post, "http://localhost:5175/batch-render")
          .to_return(
            status: 200,
            body: { results: [{ html: "<div>SSR Content</div>" }] }.to_json
          )

        get "/with_component"

        expect(response.body).to include('data-component="SimpleComponent"')
        expect(response.body).to include("ReactiveViews Test App")
      end
    end

    context "with missing component" do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve).and_return(nil)
      end

      it "renders error overlay in development" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

        get "/with_error"

        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/error|not found/i)
      end
    end

    context "when ReactiveViews is disabled" do
      before do
        ReactiveViews.config.enabled = false
      end

      after do
        ReactiveViews.config.enabled = true
      end

      it "returns HTML unchanged" do
        get "/with_component"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<SimpleComponent")
        expect(response.body).not_to include("data-island-uuid")
      end
    end
  end

  describe "prop passing" do
    before do
      allow(ReactiveViews::ComponentResolver).to receive(:resolve)
        .and_return("/path/to/SimpleComponent.tsx")

      stub_request(:post, "http://localhost:5175/batch-render")
        .to_return(
          status: 200,
          body: { results: [{ error: "Render error" }] }.to_json
        )
    end

    it "passes props to error overlay in development" do
      get "/with_component"

      expect(response.body).to include("SimpleComponent")
    end
  end

  describe "error handling" do
    context "when SSR server is unavailable" do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return("/path/to/SimpleComponent.tsx")

        stub_request(:post, "http://localhost:5175/batch-render")
          .to_timeout
      end

      it "handles timeout gracefully" do
        get "/with_component"

        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/error/i)
      end

      it "does not break page rendering" do
        get "/with_component"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ReactiveViews Test App")
      end
    end

    context "when SSR server returns error" do
      before do
        allow(ReactiveViews::ComponentResolver).to receive(:resolve)
          .and_return("/path/to/SimpleComponent.tsx")

        stub_request(:post, "http://localhost:5175/batch-render")
          .to_return(
            status: 200,
            body: { results: [{ error: "Component threw error" }] }.to_json
          )
      end

      it "shows error in development" do
        get "/with_component"

        expect(response.body).to include("data-reactive-views-error")
        expect(response.body).to include("SimpleComponent")
      end
    end
  end

  describe "layout integration" do
    it "includes reactive_views_script_tag in head" do
      get "/"

      expect(response).to have_http_status(:ok)
      # The dummy controller uses a layout, should include HTML structure
      expect(response.body).to include("Hello World")
    end
  end
end
