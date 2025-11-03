# frozen_string_literal: true

require "rails_helper"
require "vite_rails"

RSpec.describe ReactiveViewsHelper, type: :helper do
  # Include ViteRails helpers so our wrapper has something to wrap
  before do
    helper.extend(ViteRails::TagHelpers)
  end

  describe "#reactive_views_script_tag" do
    context "when vite methods are available" do
      before do
        # Stub the vite_rails methods that our helper wraps
        allow(helper).to receive(:vite_client_tag).and_return("<script>vite client</script>".html_safe)
        allow(helper).to receive(:vite_javascript_tag).and_return("<script>vite js for application</script>".html_safe)
      end

      it "includes vite_client_tag" do
        result = helper.reactive_views_script_tag
        expect(result).to include("vite client")
      end

      it "includes vite_javascript_tag for application" do
        result = helper.reactive_views_script_tag
        expect(result).to include("vite js for application")
      end

      it "returns combined script tags" do
        result = helper.reactive_views_script_tag
        expect(result).to include("vite client")
        expect(result).to include("vite js")
      end

      it "joins output with newlines" do
        result = helper.reactive_views_script_tag
        expect(result).to include("\n")
      end
    end

    context "when vite methods are not available" do
      before do
        # Make respond_to? return false for vite methods
        allow(helper).to receive(:respond_to?).and_call_original
        allow(helper).to receive(:respond_to?).with(:vite_client_tag).and_return(false)
        allow(helper).to receive(:respond_to?).with(:vite_javascript_tag).and_return(false)
      end

      it "returns empty safe string when methods not available" do
        result = helper.reactive_views_script_tag
        expect(result).to eq("".html_safe)
      end

      it "does not raise errors" do
        expect { helper.reactive_views_script_tag }.not_to raise_error
      end
    end
  end

  describe "#reactive_views_boot (deprecated)" do
    it "warns about deprecation" do
      expect { helper.reactive_views_boot }.to output(/DEPRECATION/).to_stderr
    end

    it "returns javascript_include_tag" do
      result = helper.reactive_views_boot
      expect(result).to include("script")
    end
  end
end
