# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReactiveViewsHelper, type: :helper do
  describe "#reactive_views_script_tag" do
    context "when vite_rails is available" do
      before do
        stub_const("ViteRails", Module.new)
        # Create a test helper class that implements the vite methods
        helper.singleton_class.class_eval do
          def vite_client_tag
            "<script>vite client</script>".html_safe
          end

          def vite_javascript_tag(name)
            "<script>vite js for #{name}</script>".html_safe
          end
        end
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

    context "when vite_rails is not available" do
      before do
        hide_const("ViteRails")
      end

      it "returns empty safe string in production" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        result = helper.reactive_views_script_tag
        expect(result).to eq("".html_safe)
      end

      it "returns warning div in development" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        result = helper.reactive_views_script_tag
        expect(result).to include("ReactiveViews requires vite_rails gem")
        expect(result).to be_html_safe
      end
    end

    context "when vite helpers raise errors" do
      before do
        stub_const("ViteRails", Module.new)
        allow(helper).to receive(:respond_to?).and_call_original
        allow(helper).to receive(:respond_to?).with(:vite_client_tag).and_return(true)
        allow(helper).to receive(:respond_to?).with(:vite_client_tag, true).and_return(true)
        allow(helper).to receive(:respond_to?).with(:vite_javascript_tag).and_return(true)
        allow(helper).to receive(:respond_to?).with(:vite_javascript_tag, true).and_return(true)
        allow(helper).to receive(:vite_client_tag).and_raise(NoMethodError, "vite_client_tag not available")
        allow(helper).to receive(:vite_javascript_tag).and_raise(NoMethodError, "vite_javascript_tag not available")
      end

      it "handles errors gracefully" do
        expect { helper.reactive_views_script_tag }.not_to raise_error
      end

      it "returns error message in development" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        result = helper.reactive_views_script_tag
        expect(result).to include("vite_javascript_tag failed")
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
