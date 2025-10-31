# frozen_string_literal: true

require "rails/generators/base"

module ReactiveViews
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :skip_vite, type: :boolean, default: false, desc: "Skip Vite installation"
      class_option :skip_react, type: :boolean, default: false, desc: "Skip React setup"
      class_option :skip_procfile, type: :boolean, default: false, desc: "Do not create/append Procfile.dev"
      class_option :boot_path, type: :string, default: nil, desc: "Override default boot module path in initializer"
      class_option :with_example, type: :boolean, default: false, desc: "Generate example component and ERB usage hint"

      def display_intro
        say "\n[ReactiveViews] Generating install files...", :green
        say "If any file already exists, you'll be prompted to overwrite or skip it. This provides full safety and control for your app setup!", :cyan
        say ""
      end

      def install_vite
        return if options[:skip_vite]

        run "bundle exec vite install"
      end

      def configure_vite_port
        vite_config_path = "config/vite.json"
        
        if File.exist?(vite_config_path)
          begin
            config = JSON.parse(File.read(vite_config_path))
            config["development"] ||= {}
            
            # Only set port if not already configured
            unless config["development"]["port"]
              config["development"]["port"] = 5174
              File.write(vite_config_path, JSON.pretty_generate(config))
              say_status :update, "#{vite_config_path} (set default Vite port to 5174)", :green
            end
          rescue JSON::ParserError
            say_status :error, "Could not parse #{vite_config_path}", :red
          end
        else
          create_file vite_config_path, JSON.pretty_generate({
            "all" => {
              "sourceCodeDir" => "app/javascript",
              "watchAdditionalPaths" => []
            },
            "development" => {
              "autoBuild" => true,
              "publicOutputDir" => "vite-dev",
              "port" => 5174
            },
            "test" => {
              "autoBuild" => true,
              "publicOutputDir" => "vite-test",
              "port" => 5175
            }
          })
        end
      end

      def ensure_react_setup
        return if options[:skip_react]

        # Check if React is already installed
        react_installed = false
        if File.exist?("package.json")
          begin
            package_json = JSON.parse(File.read("package.json"))
            deps = package_json["dependencies"] || {}
            dev_deps = package_json["devDependencies"] || {}
            react_installed = deps.key?("react") || dev_deps.key?("react")
          rescue JSON::ParserError
            # If package.json is invalid, continue with prompt
          end
        end

        if react_installed
          say_status :skip, "React already installed"
        else
          say "\nReactiveViews requires React to work.", :yellow
          response = ask("Install React dependencies now? [Yn] ", :yellow)
          # Default to yes if no response (non-interactive mode or empty input)
          if response.nil? || response.to_s.match?(/^y|^$/i)
            say_status :run, "Installing React dependencies"
            run "npm install react react-dom @types/react @types/react-dom @vitejs/plugin-react", verbose: false
          else
            say "\n⚠️  Please install React manually when ready:", :yellow
            say "   npm install react react-dom @types/react @types/react-dom @vitejs/plugin-react", :cyan
            say "\nWithout React, ReactiveViews components won't hydrate on the client.", :yellow
          end
        end

        # Handle vite.config.ts - vite install may have created it
        vite_config_path = "vite.config.ts"
        if File.exist?(vite_config_path)
          config_content = File.read(vite_config_path)
          # Check if React plugin is already present
          if config_content.include?("@vitejs/plugin-react") || config_content.include?("plugin-react")
            say_status :skip, "vite.config.ts already has React plugin"
          else
            response = ask("vite.config.ts exists. Modify it to add React plugin? [Yn] ", :yellow)
            if response.nil? || response.to_s.match?(/^y|^$/i)
              # Prompt before modifying existing vite.config.ts
              say_status :update, "vite.config.ts (adding React plugin)"
              # Add react import after vite import
              config_content = config_content.sub(
                /(import.*from ['"]vite['"])/,
                "\\1\nimport react from '@vitejs/plugin-react'"
              )
              # Add server.port configuration if not present
              unless config_content.include?("server:")
                config_content = config_content.sub(
                  /(export default defineConfig\(\{)/,
                  "\\1\n  server: {\n    port: parseInt(process.env.RV_VITE_PORT || '5174'),\n  },"
                )
              end
              # Add react() to plugins array
              if config_content.include?("RubyPlugin()")
                config_content = config_content.sub(
                  /RubyPlugin\(\)/,
                  "RubyPlugin(),\n      react()"
                )
              elsif config_content.include?("plugins:")
                config_content = config_content.sub(
                  /plugins:\s*\[([^\]]*)\]/,
                  "plugins: [\\1,\n      react()]"
                )
              end
              create_file vite_config_path, config_content, force: true
            else
              say_status :skip, "vite.config.ts (skipped modification)"
            end
          end
        else
          # Create new vite.config.ts with React plugin
          react_config = <<~JS
            import { defineConfig } from 'vite'
            import RubyPlugin from 'vite-plugin-ruby'
            import react from '@vitejs/plugin-react'

            export default defineConfig({
              server: {
                port: parseInt(process.env.RV_VITE_PORT || '5174'),
              },
              plugins: [
                RubyPlugin(),
                react(),
              ],
            })
          JS
          create_file vite_config_path, react_config
        end
      end

      def write_initializer
        template "initializer.rb.tt", "config/initializers/reactive_views.rb"
      end

      def create_vite_entrypoint
        # Create or update app/javascript/entrypoints/application.js to import the boot script
        # ViteRails uses entrypoints/ subdirectory by convention
        entrypoint_path = "app/javascript/entrypoints/application.js"
        
        if File.exist?(entrypoint_path)
          # Check if it already imports the boot script
          content = File.read(entrypoint_path)
          unless content.include?("reactive_views/boot")
            # Append the import
            append_to_file entrypoint_path, "\n// Import the ReactiveViews boot logic\nimport \"../reactive_views/boot.ts\";\n"
            say_status :update, "#{entrypoint_path} (added ReactiveViews boot import)", :green
          end
        elsif File.exist?("app/javascript/application.js")
          # Fallback to root application.js if entrypoints doesn't exist
          content = File.read("app/javascript/application.js")
          unless content.include?("reactive_views/boot")
            append_to_file "app/javascript/application.js", "\n// Import the ReactiveViews boot logic\nimport \"./reactive_views/boot.ts\";\n"
            say_status :update, "app/javascript/application.js (added ReactiveViews boot import)", :green
          end
        else
          # Create new application.js from template in the root
          template "application.js.tt", "app/javascript/application.js"
          say_status :create, "app/javascript/application.js", :green
        end
      end

      def copy_boot_script
        # Copy the TypeScript boot source from the gem to app/javascript
        # This allows Vite to bundle it with React
        empty_directory "app/javascript/reactive_views"

        # Find the gem directory to locate the boot script
        gem_dir = Gem.loaded_specs["reactive_views"]&.gem_dir

        if gem_dir.nil?
          boot_file = Gem.find_files("reactive_views/boot").first
          gem_dir = File.expand_path("../..", boot_file) if boot_file
        end

        unless gem_dir
          say_status :error, "Could not find reactive_views gem directory", :red
          return
        end

        # Use the TypeScript source file
        boot_source = File.join(gem_dir, "app", "frontend", "reactive_views", "boot.ts")

        unless File.exist?(boot_source)
          say_status :error, "Boot script source not found at: #{boot_source}", :red
          return
        end

        # Copy the TypeScript source to the app for Vite to bundle
        copy_file boot_source, "app/javascript/reactive_views/boot.ts"
        say "✓ Copied ReactiveViews boot script to app/javascript/reactive_views/", :green
      end

      def example_component
        return unless options[:with_example]

        empty_directory "app/views/components"
        template "example_component.tsx.tt", "app/views/components/example_hello.tsx"
        say "Add to an ERB view to test: <ExampleHello name=\"Rails\" />", :green
      end

      def update_application_layout
        layout_path = "app/views/layouts/application.html.erb"

        if File.exist?(layout_path)
          layout_content = File.read(layout_path)

          # Check if reactive_views_script_tag is already present
          if layout_content.include?("reactive_views_script_tag")
            say_status :skip, "#{layout_path} (already includes reactive_views_script_tag)", :yellow
            return
          end

          # Check for old vite tags that should be replaced
          has_old_tags = layout_content.include?("vite_client_tag") || layout_content.include?("vite_javascript_tag")

          if has_old_tags
            say "\n⚠️  Your layout includes old vite_client_tag or vite_javascript_tag calls.", :yellow
            say "These should be replaced with the single reactive_views_script_tag helper.", :yellow

            response = ask("\nWould you like to automatically update #{layout_path}? [Yn] ", :yellow)
            if response.nil? || response.to_s.match?(/^y|^$/i)
              # Remove old Vite tags and add new helper
              layout_content.gsub!(/\s*<%=\s*vite_client_tag\s*%>\s*\n?/, "")
              layout_content.gsub!(/\s*<%=\s*vite_javascript_tag\s+['"]application['"]\s*%>\s*\n?/, "")
              layout_content.gsub!(/\s*<%=\s*vite_typescript_tag\s+['"]application['"]\s*%>\s*\n?/, "")

              # Add reactive_views_script_tag before </head>
              unless layout_content.include?("reactive_views_script_tag")
                layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
              end

              File.write(layout_path, layout_content)
              say_status :update, layout_path, :green
              say "✓ Replaced old Vite tags with reactive_views_script_tag", :green
            else
              say_status :skip, "#{layout_path} (manual update required)", :yellow
              say "\nPlease add this to your layout's <head> section:", :yellow
              say "  <%= reactive_views_script_tag %>", :cyan
            end
          else
            # No old tags, just offer to add the new helper
            if layout_content.include?("</head>")
              say "\nAdding reactive_views_script_tag to your layout...", :cyan
              layout_content.sub!(/<\/head>/, "    <%= reactive_views_script_tag %>\n  </head>")
              File.write(layout_path, layout_content)
              say_status :update, layout_path, :green
            else
              say_status :skip, "#{layout_path} (couldn't find </head> tag)", :yellow
              say "\nPlease add this to your layout's <head> section:", :yellow
              say "  <%= reactive_views_script_tag %>", :cyan
            end
          end
        else
          # Create new layout from template
          template "application.html.erb.tt", layout_path
        end
      end

      def add_procfile
        return if options[:skip_procfile]

        procfile_path = "Procfile.dev"
        
        if File.exist?(procfile_path)
          content = File.read(procfile_path)
          processes = parse_procfile(content)
          
          # Track what needs updating
          updates_needed = []

          # Check if Rails web process exists and ensure it uses correct port
          if processes["web"]
            # Check if it's using the old default (5000) or not specifying port
            unless processes["web"].include?("RAILS_PORT") || processes["web"].match?(/server\s+-p\s+3000/)
              processes["web"] = "bundle exec rails server -p ${RAILS_PORT:-3000}"
              updates_needed << "web"
            end
          else
            # Add Rails web process
            processes["web"] = "bundle exec rails server -p ${RAILS_PORT:-3000}"
            updates_needed << "web"
          end

          # Check if Vite process exists
          if processes["vite"]
            say_status :skip, "Vite already in Procfile.dev"
          else
            processes["vite"] = "bin/vite dev"
            updates_needed << "vite"
          end

          # Check if SSR has old/broken path
          has_old_broken_path = processes["ssr"]&.include?("node/ssr_server.js")

          # Fix SSR if broken
          if has_old_broken_path
            response = ask("Procfile.dev contains a broken SSR path. Fix it? [Yn] ", :yellow)
            if response.nil? || response.to_s.match?(/^y|^$/i)
              processes["ssr"] = "bundle exec rake reactive_views:ssr"
              updates_needed << "ssr"
            end
          elsif !processes["ssr"]
            # Add SSR if missing
            processes["ssr"] = "bundle exec rake reactive_views:ssr"
            updates_needed << "ssr"
          end

          # Write updated Procfile if changes were made
          if updates_needed.any?
            new_content = processes.map { |name, cmd| "#{name}: #{cmd}" }.join("\n") + "\n"
            create_file procfile_path, new_content, force: true
            say_status :update, "Procfile.dev (added: #{updates_needed.join(', ')})", :green
          else
            say_status :skip, "Procfile.dev already configured"
          end
        else
          # Create new Procfile
          create_file procfile_path, <<~PROCFILE
            web: bundle exec rails server -p ${RAILS_PORT:-3000}
            vite: bin/vite dev
            ssr: bundle exec rake reactive_views:ssr
          PROCFILE
        end
      end

      def add_rake_task
        rakefile_path = "lib/tasks/reactive_views.rake"
        
        # Create rake task for SSR
        create_file rakefile_path, <<~RAKE
          namespace :reactive_views do
            desc "Start the ReactiveViews SSR server"
            task :ssr do
              require "reactive_views"
              
              gem_root = Gem.loaded_specs["reactive_views"]&.gem_dir
              if gem_root.nil?
                puts "Error: Could not find reactive_views gem directory"
                exit 1
              end

              ssr_script = File.join(gem_root, "node", "ssr", "server.mjs")
              
              unless File.exist?(ssr_script)
                puts "Error: SSR server script not found at: \#{ssr_script}"
                exit 1
              end

              puts "Starting ReactiveViews SSR server..."
              exec("node", ssr_script)
            end
          end
        RAKE
      end

      def check_ssr_dependencies
        gem_root = Gem.loaded_specs["reactive_views"]&.gem_dir
        return unless gem_root

        node_modules = File.join(gem_root, "node", "node_modules")
        if Dir.exist?(node_modules)
          say_status :skip, "SSR dependencies already installed in gem"
        else
          say "\n⚠️  SSR server dependencies not installed.", :yellow
          say "The gem needs React and esbuild in node/ for SSR.", :yellow
          say "Run: cd #{gem_root}/node && npm install", :cyan
        end
      end

      def update_bin_dev
        bin_dev_path = "bin/dev"
        
        # Create enhanced bin/dev script with cleanup
        enhanced_script = <<~BASH
          #!/usr/bin/env sh

          # Exit on error
          set -e

          echo "🧹 Cleaning up stale processes..."

          # Function to kill process on port
          kill_port() {
            PORT=$1
            PID=$(lsof -ti:$PORT 2>/dev/null || true)
            if [ -n "$PID" ]; then
              echo "  Killing process $PID on port $PORT"
              kill -9 $PID 2>/dev/null || true
            fi
          }

          # Kill processes on configured ports
          kill_port ${RAILS_PORT:-3000}
          kill_port ${RV_VITE_PORT:-5174}
          kill_port ${RV_SSR_PORT:-5175}

          # Clean up PID files
          rm -f tmp/pids/*.pid 2>/dev/null || true

          # Start foreman
          if ! command -v foreman &> /dev/null; then
            echo "Installing foreman..."
            gem install foreman
          fi

          exec foreman start -f Procfile.dev "$@"
        BASH

        create_file bin_dev_path, enhanced_script, force: true
        chmod bin_dev_path, 0755
      end

      private

      def parse_procfile(content)
        processes = {}
        content.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")
          
          if line =~ /^([^:]+):\s*(.+)$/
            processes[$1.strip] = $2.strip
          end
        end
        processes
      end
    end
  end
end
