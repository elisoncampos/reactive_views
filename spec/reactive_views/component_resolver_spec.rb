# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/reactive_views"

RSpec.describe ReactiveViews::ComponentResolver do
  let(:test_dir) { File.join(__dir__, "..", "fixtures", "components") }

  before do
    ReactiveViews.configure do |config|
      config.component_views_paths = [test_dir]
      config.component_js_paths = []
    end

    FileUtils.mkdir_p(test_dir)
  end

  after do
    FileUtils.rm_rf(test_dir) if File.exist?(test_dir)
  end

  describe ".resolve" do
    context "when component exists" do
      let(:component_name) { "TestComponent" }
      let(:component_path) { File.join(test_dir, "#{component_name}.tsx") }

      before do
        File.write(component_path, "export default function TestComponent() {}")
      end

      it "returns the component path" do
        result = described_class.resolve(component_name)
        expect(result).to eq(component_path)
      end

      it "handles .tsx extension" do
        expect(described_class.resolve(component_name)).to end_with(".tsx")
      end

      it "handles .jsx extension" do
        jsx_path = File.join(test_dir, "JsxComponent.jsx")
        File.write(jsx_path, "export default function JsxComponent() {}")

        result = described_class.resolve("JsxComponent")
        expect(result).to end_with(".jsx")
      end

      it "handles .ts extension" do
        ts_path = File.join(test_dir, "TsComponent.ts")
        File.write(ts_path, "export default function TsComponent() {}")

        result = described_class.resolve("TsComponent")
        expect(result).to end_with(".ts")
      end

      it "handles .js extension" do
        js_path = File.join(test_dir, "JsComponent.js")
        File.write(js_path, "export default function JsComponent() {}")

        result = described_class.resolve("JsComponent")
        expect(result).to end_with(".js")
      end
    end

    context "when component does not exist" do
      it "returns nil" do
        result = described_class.resolve("NonExistentComponent")
        expect(result).to be_nil
      end
    end

    context "with multiple component paths" do
      let(:other_dir) { File.join(__dir__, "..", "fixtures", "other_components") }

      before do
        FileUtils.mkdir_p(other_dir)
        ReactiveViews.configure do |config|
          config.component_views_paths = [test_dir]
          config.component_js_paths = [other_dir]
        end
      end

      after do
        FileUtils.rm_rf(other_dir) if File.exist?(other_dir)
      end

      it "searches in all configured paths (both views and js)" do
        component_path = File.join(other_dir, "OtherComponent.tsx")
        File.write(component_path, "export default function OtherComponent() {}")

        result = described_class.resolve("OtherComponent")
        expect(result).to eq(component_path)
      end

      it "returns first match when component exists in multiple paths" do
        File.write(File.join(test_dir, "Duplicate.tsx"), "version 1")
        File.write(File.join(other_dir, "Duplicate.tsx"), "version 2")

        result = described_class.resolve("Duplicate")
        expect(result).to eq(File.join(test_dir, "Duplicate.tsx"))
      end
    end

    context "with subdirectories" do
      let(:sub_dir) { File.join(test_dir, "nested", "deep") }

      before do
        FileUtils.mkdir_p(sub_dir)
        ReactiveViews.configure do |config|
          config.component_views_paths = [test_dir]
          config.component_js_paths = []
        end
      end

      it "finds components in subdirectories" do
        component_path = File.join(sub_dir, "DeepComponent.tsx")
        File.write(component_path, "export default function DeepComponent() {}")

        result = described_class.resolve("DeepComponent")
        expect(result).to eq(component_path)
      end
    end

    context "with different naming conventions" do
      before do
        ReactiveViews.configure do |config|
          config.component_views_paths = [test_dir]
          config.component_js_paths = []
        end
      end

      it "finds PascalCase components" do
        component_path = File.join(test_dir, "HelloWorld.tsx")
        File.write(component_path, "export default function HelloWorld() {}")

        result = described_class.resolve("HelloWorld")
        expect(result).to eq(component_path)
      end

      it "finds snake_case components when searching with PascalCase" do
        component_path = File.join(test_dir, "hello_world.tsx")
        File.write(component_path, "export default function HelloWorld() {}")

        result = described_class.resolve("HelloWorld")
        expect(result).to eq(component_path)
      end

      it "finds camelCase components when searching with PascalCase" do
        component_path = File.join(test_dir, "helloWorld.tsx")
        File.write(component_path, "export default function HelloWorld() {}")

        result = described_class.resolve("HelloWorld")
        expect(result).to eq(component_path)
      end

      it "finds kebab-case components when searching with PascalCase" do
        component_path = File.join(test_dir, "hello-world.tsx")
        File.write(component_path, "export default function HelloWorld() {}")

        result = described_class.resolve("HelloWorld")
        expect(result).to eq(component_path)
      end

      it "prioritizes exact match over variants" do
        exact_match = File.join(test_dir, "HelloWorld.tsx")
        snake_case = File.join(test_dir, "hello_world.tsx")

        File.write(exact_match, "exact")
        File.write(snake_case, "snake")

        result = described_class.resolve("HelloWorld")
        expect(result).to eq(exact_match)
      end

      it "finds snake_case components in nested directories" do
        nested_dir = File.join(test_dir, "auth")
        FileUtils.mkdir_p(nested_dir)
        component_path = File.join(nested_dir, "login_form.tsx")
        File.write(component_path, "export default function LoginForm() {}")

        result = described_class.resolve("LoginForm")
        expect(result).to eq(component_path)
      end

      it "handles multi-word components correctly" do
        component_path = File.join(test_dir, "user_profile_card.tsx")
        File.write(component_path, "export default function UserProfileCard() {}")

        result = described_class.resolve("UserProfileCard")
        expect(result).to eq(component_path)
      end
    end
  end
end
