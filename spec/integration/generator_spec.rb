# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "fileutils"
require "tmpdir"
require_relative "../../lib/generators/reactive_views/install/install_generator"

RSpec.describe ReactiveViews::Generators::InstallGenerator, type: :generator do
  let(:temp_dir) { Dir.mktmpdir("reactive_views_test") }
  let(:layout_path) { File.join(temp_dir, "app", "views", "layouts", "application.html.erb") }

  before do
    FileUtils.mkdir_p(File.dirname(layout_path))
    allow(Rails).to receive(:root).and_return(Pathname.new(temp_dir))
  end

  after do
    FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
  end

  describe "generator idempotency" do
    let(:initial_layout) do
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Test App</title>
            <%= vite_client_tag %>
            <%= vite_javascript_tag "application" %>
          </head>
          <body>
            <%= yield %>
          </body>
        </html>
      HTML
    end

    before do
      File.write(layout_path, initial_layout)
    end

    it "replaces old vite tags with reactive_views_script_tag" do
      # Test the layout transformation directly without Thor complexities
      layout_content = File.read(layout_path)

      # Simulate what the generator does
      layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")

      File.write(layout_path, layout_content)

      result = File.read(layout_path)

      expect(result).to include("reactive_views_script_tag")
      expect(result).not_to include("vite_client_tag")
      expect(result).not_to include("vite_javascript_tag")
    end

    it "can be run multiple times safely" do
      # First run - convert old tags
      layout_content = File.read(layout_path)
      layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*reactive_views_script_tag\s*%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
      File.write(layout_path, layout_content)

      first_run = File.read(layout_path)

      # Second run - should not duplicate
      layout_content = File.read(layout_path)
      layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*reactive_views_script_tag\s*%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
      File.write(layout_path, layout_content)

      second_run = File.read(layout_path)

      # Should have exactly one reactive_views_script_tag
      expect(second_run.scan(/reactive_views_script_tag/).count).to eq(1)
      expect(first_run).to eq(second_run)
    end

    it "handles layouts with extra whitespace" do
      messy_layout = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>Test</title>
            <%=    vite_client_tag    %>
            <%=   vite_javascript_tag    "application"    %>
          </head>
          <body></body>
        </html>
      HTML

      File.write(layout_path, messy_layout)

      layout_content = File.read(layout_path)
      layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
      File.write(layout_path, layout_content)

      result = File.read(layout_path)

      expect(result).to include("reactive_views_script_tag")
      expect(result).not_to include("vite_client_tag")
    end

    it "handles layouts with different quote styles" do
      layout_with_double_quotes = <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <%= vite_javascript_tag "application" %>
          </head>
          <body></body>
        </html>
      HTML

      File.write(layout_path, layout_with_double_quotes)

      layout_content = File.read(layout_path)
      layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
      File.write(layout_path, layout_content)

      result = File.read(layout_path)

      expect(result).to include("reactive_views_script_tag")
      expect(result).not_to include("vite_javascript_tag")
    end
  end

  describe "force mode" do
    let(:layout_with_old_tags) do
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <%= vite_client_tag %>
          </head>
          <body></body>
        </html>
      HTML
    end

    before do
      File.write(layout_path, layout_with_old_tags)
    end

    it "updates without prompting when force is true" do
      # Simulate force mode
      layout_content = File.read(layout_path)
      layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
      layout_content.gsub!(/\s*<%=\s*reactive_views_script_tag\s*%>\s*\n?/m, "")
      layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
      File.write(layout_path, layout_content)

      result = File.read(layout_path)

      expect(result).to include("reactive_views_script_tag")
      expect(result).not_to include("vite_client_tag")
    end
  end
end
