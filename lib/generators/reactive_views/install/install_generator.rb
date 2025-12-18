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
      class_option :component_views_path, type: :string, default: "app/views/components",
                                          desc: "Path for React components in views (default: app/views/components)"
      class_option :component_js_path, type: :string, default: "app/javascript/components",
                                       desc: "Path for React components in JavaScript (default: app/javascript/components)"

      def initialize(*args)
        super
        @package_manager = detect_package_manager
      end

      def display_intro
        say "\n[ReactiveViews] Generating install files...", :green
        say "If any file already exists, you'll be prompted to overwrite or skip it. This provides full safety and control for your app setup!",
            :cyan
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
            config["production"] ||= {}

            updated = false

            # Set default development port if not already configured
            unless config["development"]["port"]
              config["development"]["port"] = 5174
              updated = true
            end

            # Ensure production config exists with proper settings
            unless config["production"]["publicOutputDir"]
              config["production"]["autoBuild"] = false
              config["production"]["publicOutputDir"] = "vite"
              config["production"]["port"] = 5174
              updated = true
            end

            if updated
              File.write(vite_config_path, JSON.pretty_generate(config))
              say_status :update, "#{vite_config_path} (added production config)", :green
            end
          rescue JSON::ParserError
            say_status :error, "Could not parse #{vite_config_path}", :red
          end
        else
          # Use the component views path for watching
          watch_path = options[:component_views_path]

          create_file vite_config_path, JSON.pretty_generate({
                                                               "all" => {
                                                                 "sourceCodeDir" => "app/javascript",
                                                                 "watchAdditionalPaths" => [ watch_path ]
                                                               },
                                                               "development" => {
                                                                 "autoBuild" => true,
                                                                 "publicOutputDir" => "vite-dev",
                                                                 "port" => 5174
                                                               },
                                                               "test" => {
                                                                 "autoBuild" => true,
                                                                 "publicOutputDir" => "vite-test",
                                                                 "port" => 5174
                                                               },
                                                               "production" => {
                                                                 "autoBuild" => false,
                                                                 "publicOutputDir" => "vite",
                                                                 "port" => 5174
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
          say ""
          say "ReactiveViews requires React to work.", :yellow
          response = ask("Install React dependencies now? [Yn] ", :yellow)
          # Default to yes if no response (non-interactive mode or empty input)
          if response.nil? || response.to_s.match?(/^y|^$/i)
            say_status :run, "Installing React dependencies"
            install_cmd = install_command_for(@package_manager)
            run "#{@package_manager} #{install_cmd} react react-dom @types/react @types/react-dom @vitejs/plugin-react",
                verbose: false
          else
            say ""
            say "⚠️  Please install React manually when ready:", :yellow
            install_cmd = install_command_for(@package_manager)
            say "   #{@package_manager} #{install_cmd} react react-dom @types/react @types/react-dom @vitejs/plugin-react",
                :cyan
            say ""
            say "Without React, ReactiveViews components won't hydrate on the client.", :yellow
          end
        end

        # Handle vite.config - prefer .mts (ESM) format for Vite 7.x compatibility
        # Check for existing configs in order of preference
        existing_config = %w[vite.config.mts vite.config.ts].find { |f| File.exist?(f) }

        if existing_config
          config_content = File.read(existing_config)
          # Check if React plugin is already present
          if config_content.include?("@vitejs/plugin-react") || config_content.include?("plugin-react")
            say_status :skip, "#{existing_config} already has React plugin"
          else
            response = ask("#{existing_config} exists. Modify it to add React plugin? [Yn] ", :yellow)
            if response.nil? || response.to_s.match?(/^y|^$/i)
              say_status :update, "#{existing_config} (adding React plugin)"
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
                  "RubyPlugin()",
                  "RubyPlugin(),\n      react()"
                )
              elsif config_content.include?("plugins:")
                config_content = config_content.sub(
                  /plugins:\s*\[([^\]]*)\]/,
                  "plugins: [\\1,\n      react()]"
                )
              end
              create_file existing_config, config_content, force: true
            else
              say_status :skip, "#{existing_config} (skipped modification)"
            end
          end
        else
          # Create new vite.config.mts with ESM format for Vite 7.x compatibility
          # Uses import.meta.dirname (Node 20.11+) instead of __dirname
          react_config = <<~JS
            import { defineConfig, loadEnv } from 'vite'
            import RubyPlugin from 'vite-plugin-ruby'
            import react from '@vitejs/plugin-react'
            import path from 'path'

            const port = parseInt(process.env.RV_VITE_PORT || '5174')

            export default defineConfig(({ mode }) => {
              const env = loadEnv(mode, process.cwd(), '')
              const isProduction = mode === 'production'

              return {
                plugins: [
                  RubyPlugin(),
                  react(),
                ],

                // Base path for assets - can be overridden via ASSET_HOST env var for CDN
                base: isProduction && env.ASSET_HOST ? `${env.ASSET_HOST}/vite/` : undefined,

                server: {
                  port,
                  strictPort: true,
                },

                resolve: {
                  alias: {
                    '@components': path.resolve(import.meta.dirname, '#{options[:component_views_path]}'),
                    '@js-components': path.resolve(import.meta.dirname, '#{options[:component_js_path]}'),
                  },
                },

                build: {
                  // Modern browsers only in production for smaller bundles
                  target: isProduction ? 'es2022' : 'esnext',

                  // Generate manifest for Rails integration
                  manifest: true,

                  // Single CSS file for simpler loading order
                  cssCodeSplit: false,

                  // Source maps in production for debugging (can be disabled via env)
                  sourcemap: env.VITE_SOURCEMAP !== 'false',

                  rollupOptions: {
                    output: {
                      // Consistent naming with content hashes for cache busting
                      entryFileNames: 'assets/[name]-[hash].js',
                      chunkFileNames: 'assets/[name]-[hash].js',
                      assetFileNames: 'assets/[name]-[hash][extname]',
                    },
                  },

                  // Increase chunk size warning threshold
                  chunkSizeWarningLimit: 1000,
                },

                // CSS configuration
                css: {
                  // Enable CSS modules for .module.css files
                  modules: {
                    localsConvention: 'camelCase',
                  },
                },

                // Optimize deps for faster dev server startup
                optimizeDeps: {
                  include: ['react', 'react-dom'],
                },
              }
            })
          JS
          create_file "vite.config.mts", react_config
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
            append_to_file entrypoint_path,
                           "\n// Import the ReactiveViews boot logic\nimport \"../reactive_views/boot.ts\";\n"
            say_status :update, "#{entrypoint_path} (added ReactiveViews boot import)", :green
          end
        elsif File.exist?("app/javascript/application.js")
          # Fallback to root application.js if entrypoints doesn't exist
          content = File.read("app/javascript/application.js")
          unless content.include?("reactive_views/boot")
            append_to_file "app/javascript/application.js",
                           "\n// Import the ReactiveViews boot logic\nimport \"./reactive_views/boot.ts\";\n"
            say_status :update, "app/javascript/application.js (added ReactiveViews boot import)", :green
          end
        else
          # Create new application.js from template in the root
          template "application.js.tt", "app/javascript/application.js"
          say_status :create, "app/javascript/application.js", :green
        end
      end

      def copy_boot_script
        # Generate the TypeScript boot source from template to app/javascript
        # This allows Vite to bundle it with React and configures component paths
        empty_directory "app/javascript/reactive_views"

        # Calculate glob patterns based on component paths
        # The boot.ts file is located at app/javascript/reactive_views/boot.ts
        # so we need relative paths from there

        views_path = options[:component_views_path]
        js_path = options[:component_js_path]

        # Calculate relative glob patterns from app/javascript/reactive_views/
        # to the component directories
        @component_views_path = views_path
        @component_js_path = js_path
        @component_views_glob = calculate_glob_pattern(views_path, "app/javascript/reactive_views")
        @component_js_glob = calculate_glob_pattern(js_path, "app/javascript/reactive_views")
        @component_views_glob_prefix = @component_views_glob.sub("**/*.{tsx,jsx,ts,js}", "")
        @component_js_glob_prefix = @component_js_glob.sub("**/*.{tsx,jsx,ts,js}", "")

        template "boot.ts.tt", "app/javascript/reactive_views/boot.ts"
        say "✓ Generated ReactiveViews boot script at app/javascript/reactive_views/boot.ts", :green
        say "  Component paths configured:", :cyan
        say "    Views: #{views_path}", :cyan
        say "    JavaScript: #{js_path}", :cyan
      end

      def example_component
        return unless options[:with_example]

        component_dir = options[:component_views_path]
        empty_directory component_dir
        template "example_component.tsx.tt", "#{component_dir}/example_hello.tsx"
        say 'Add to an ERB view to test: <ExampleHello name="Rails" />', :green
      end

      def update_application_layout
        layout_path = "app/views/layouts/application.html.erb"

        if File.exist?(layout_path)
          layout_content = File.read(layout_path)

          # Check for old vite tags that should be replaced
          # Use more robust regex patterns to catch all variations
          has_old_tags = layout_content.match?(/<%=\s*vite_client_tag.*?%>/m) ||
                         layout_content.match?(/<%=\s*vite_javascript_tag.*?%>/m) ||
                         layout_content.match?(/<%=\s*vite_typescript_tag.*?%>/m)

          # Check if reactive_views_script_tag is already present (with flexible whitespace)
          has_reactive_views_tag = layout_content.match?(/<%=\s*reactive_views_script_tag\s*%>/)

          if has_reactive_views_tag && !has_old_tags
            say_status :skip, "#{layout_path} (already includes reactive_views_script_tag)", :yellow
            return
          end

          if has_old_tags || !has_reactive_views_tag
            # In force mode or when explicitly updating
            if options[:force] || has_old_tags
              if has_old_tags
                say ""
                say "⚠️  Your layout includes old vite_client_tag or vite_javascript_tag calls.", :yellow
                say "These should be replaced with the single reactive_views_script_tag helper.", :yellow
                say ""
              end

              should_update = options[:force]
              unless should_update
                response = ask("Would you like to automatically update #{layout_path}? [Yn] ", :yellow)
                should_update = response.nil? || response.to_s.match?(/^y|^$/i)
              end

              if should_update
                # Remove all old Vite tags with robust regex patterns (multiline mode)
                layout_content.gsub!(/\s*<%=\s*vite_client_tag.*?%>\s*\n?/m, "")
                layout_content.gsub!(/\s*<%=\s*vite_javascript_tag.*?%>\s*\n?/m, "")
                layout_content.gsub!(/\s*<%=\s*vite_typescript_tag.*?%>\s*\n?/m, "")

                # Also remove any existing reactive_views_script_tag to avoid duplicates
                layout_content.gsub!(/\s*<%=\s*reactive_views_script_tag\s*%>\s*\n?/m, "")

                # Add reactive_views_script_tag before </head>
                if layout_content.include?("</head>")
                  layout_content.sub!(%r{</head>}, "    <%= reactive_views_script_tag %>\n  </head>")
                  File.write(layout_path, layout_content)
                  say_status :update, layout_path, :green
                  say "✓ Updated layout with reactive_views_script_tag", :green
                else
                  say_status :skip, "#{layout_path} (couldn't find </head> tag)", :yellow
                  say ""
                  say "Please add this to your layout's <head> section:", :yellow
                  say "  <%= reactive_views_script_tag %>", :cyan
                end
              else
                say_status :skip, "#{layout_path} (manual update required)", :yellow
                say ""
                say "Please add this to your layout's <head> section:", :yellow
                say "  <%= reactive_views_script_tag %>", :cyan
              end
            elsif layout_content.include?("</head>")
              # No old tags, just offer to add the new helper
              say ""
              say "Adding reactive_views_script_tag to your layout...", :cyan
              layout_content.sub!(%r{</head>}, "    <%= reactive_views_script_tag %>\n  </head>")
              File.write(layout_path, layout_content)
              say_status :update, layout_path, :green
            else
              say_status :skip, "#{layout_path} (couldn't find </head> tag)", :yellow
              say ""
              say "Please add this to your layout's <head> section:", :yellow
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

      def check_ssr_dependencies
        # Check if SSR dependencies are already installed in the project
        ssr_deps_installed = false
        if File.exist?("package.json")
          begin
            package_json = JSON.parse(File.read("package.json"))
            deps = package_json["dependencies"] || {}
            dev_deps = package_json["devDependencies"] || {}

            # Check if react, react-dom, and esbuild are present
            has_react = deps.key?("react") || dev_deps.key?("react")
            has_react_dom = deps.key?("react-dom") || dev_deps.key?("react-dom")
            has_esbuild = deps.key?("esbuild") || dev_deps.key?("esbuild")

            ssr_deps_installed = has_react && has_react_dom && has_esbuild
          rescue JSON::ParserError
            # If package.json is invalid, continue with prompt
          end
        end

        if ssr_deps_installed
          say_status :skip, "SSR dependencies already installed"
        else
          say ""
          say "⚠️  SSR server dependencies not installed.", :yellow
          say "The SSR server needs react, react-dom, and esbuild to render components.", :yellow
          say ""
          response = ask("Install SSR dependencies now? [Yn] ", :yellow)

          if response.nil? || response.to_s.match?(/^y|^$/i)
            say_status :run, "Installing SSR dependencies"
            install_cmd = install_command_for(@package_manager)
            # Install as dev dependencies since they're for build/SSR
            case @package_manager
            when "npm", "pnpm"
              run "#{@package_manager} #{install_cmd} --save-dev esbuild", verbose: false
            when "yarn"
              run "#{@package_manager} #{install_cmd} --dev esbuild", verbose: false
            end
            say "✓ SSR dependencies installed", :green
          else
            say ""
            say "⚠️  Please install SSR dependencies manually when ready:", :yellow
            install_cmd = install_command_for(@package_manager)
            case @package_manager
            when "npm", "pnpm"
              say "   #{@package_manager} #{install_cmd} --save-dev esbuild", :cyan
            when "yarn"
              say "   #{@package_manager} #{install_cmd} --dev esbuild", :cyan
            end
            say ""
            say "Without these dependencies, the SSR server won't be able to render components.", :yellow
          end
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
        chmod bin_dev_path, 0o755
      end

      private

      # Calculate the relative glob pattern from boot.ts location to component directory
      # e.g., from "app/javascript/reactive_views" to "app/views/components"
      # returns "../../views/components/**/*.{tsx,jsx,ts,js}"
      def calculate_glob_pattern(component_path, boot_dir)
        # Split paths into parts
        boot_parts = boot_dir.split("/")
        component_parts = component_path.split("/")

        # Find common prefix
        common_length = 0
        boot_parts.each_with_index do |part, i|
          break unless component_parts[i] == part

          common_length = i + 1
        end

        # Calculate how many levels up we need to go
        levels_up = boot_parts.length - common_length
        up_path = "../" * levels_up

        # Get the remaining path after common prefix
        remaining_path = component_parts[common_length..].join("/")

        "#{up_path}#{remaining_path}/**/*.{tsx,jsx,ts,js}"
      end

      def parse_procfile(content)
        processes = {}
        content.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          processes[::Regexp.last_match(1).strip] = ::Regexp.last_match(2).strip if line =~ /^([^:]+):\s*(.+)$/
        end
        processes
      end

      def detect_package_manager
        if File.exist?("pnpm-lock.yaml")
          "pnpm"
        elsif File.exist?("yarn.lock")
          "yarn"
        elsif File.exist?("package-lock.json")
          "npm"
        else
          # No lock file found, prompt user
          say ""
          say "No package manager lock file detected.", :yellow
          response = ask("Which package manager would you like to use? (npm/yarn/pnpm) [npm]: ", :yellow)
          response = response.to_s.strip.downcase
          response.empty? ? "npm" : response
        end
      end

      def install_command_for(package_manager)
        case package_manager
        when "yarn"
          "add"
        else
          "install"
        end
      end
    end
  end
end
