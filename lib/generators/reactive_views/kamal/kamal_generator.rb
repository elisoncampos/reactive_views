# frozen_string_literal: true

require "rails/generators/base"

module ReactiveViews
  module Generators
    # Generator for Kamal 2 deployment configuration
    # Adds SSR server as a Kamal accessory for production deployment
    #
    # Usage:
    #   rails generate reactive_views:kamal
    #   rails generate reactive_views:kamal --ssr-host=ssr.example.com
    #
    class KamalGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :ssr_host, type: :string, default: nil,
                              desc: "Host for SSR server (default: same as web)"
      class_option :ssr_port, type: :string, default: "5175",
                              desc: "Port for SSR server"
      class_option :registry, type: :string, default: nil,
                              desc: "Docker registry for SSR image"
      class_option :image_name, type: :string, default: "reactive-views-ssr",
                                desc: "Name for SSR Docker image"

      def check_kamal_installed
        unless File.exist?("config/deploy.yml")
          say "⚠️  Kamal not detected. Run 'kamal init' first.", :yellow
          say "This generator adds SSR server configuration to your existing Kamal setup.", :yellow
          say ""
          response = ask("Continue anyway? [yN] ", :yellow)
          exit unless response.to_s.match?(/^y/i)
        end
      end

      def create_ssr_dockerfile
        template "Dockerfile.ssr.tt", "Dockerfile.ssr"
        say "✓ Created Dockerfile.ssr for SSR server", :green
      end

      def create_ssr_package_json
        template "package.ssr.json.tt", "package.ssr.json"
        say "✓ Created package.ssr.json for SSR dependencies", :green
      end

      def update_deploy_yml
        deploy_path = "config/deploy.yml"

        if File.exist?(deploy_path)
          content = File.read(deploy_path)

          if content.include?("accessories:") && content.include?("ssr:")
            say_status :skip, "SSR accessory already configured in deploy.yml"
            return
          end

          say ""
          say "Add the following to your config/deploy.yml:", :cyan
          say ""
          say accessory_config, :yellow
          say ""
          say "Or run with --force to append automatically.", :cyan
        else
          template "deploy.yml.tt", deploy_path
          say "✓ Created config/deploy.yml with SSR accessory", :green
        end
      end

      def create_dockerignore
        dockerignore_path = ".dockerignore.ssr"
        template "dockerignore.ssr.tt", dockerignore_path
        say "✓ Created #{dockerignore_path}", :green
      end

      def show_next_steps
        say ""
        say "=" * 60, :green
        say "Next steps for Kamal deployment:", :green
        say "=" * 60, :green
        say ""
        say "1. Review and customize Dockerfile.ssr", :cyan
        say ""
        say "2. Add SSR accessory to config/deploy.yml:", :cyan
        say accessory_config, :yellow
        say ""
        say "3. Set environment variables:", :cyan
        say "   REACTIVE_VIEWS_SSR_URL=http://ssr:#{options[:ssr_port]}", :yellow
        say ""
        say "4. Build and push SSR image:", :cyan
        say "   docker build -f Dockerfile.ssr -t #{image_tag} .", :yellow
        say "   docker push #{image_tag}", :yellow
        say ""
        say "5. Deploy with Kamal:", :cyan
        say "   kamal setup", :yellow
        say "   kamal deploy", :yellow
        say ""
      end

      private

      def ssr_host
        options[:ssr_host] || "<your-ssr-host>"
      end

      def ssr_port
        options[:ssr_port]
      end

      def image_tag
        registry = options[:registry]
        image = options[:image_name]

        registry ? "#{registry}/#{image}:latest" : "#{image}:latest"
      end

      def accessory_config
        <<~YAML
          accessories:
            ssr:
              image: #{image_tag}
              host: #{ssr_host}
              port: #{ssr_port}
              env:
                clear:
                  RV_SSR_PORT: "#{ssr_port}"
                  NODE_ENV: production
                  PROJECT_ROOT: /rails
              volumes:
                - /rails/app:/rails/app:ro
              healthcheck:
                path: /health
                interval: 10s
        YAML
      end
    end
  end
end

