# frozen_string_literal: true

require "rails/generators/base"

module ReactiveViews
  module Generators
    # Generator for Kubernetes deployment manifests
    # Creates deployment, service, configmap, and HPA for SSR server
    #
    # Usage:
    #   rails generate reactive_views:kubernetes
    #   rails generate reactive_views:kubernetes --namespace=production
    #
    class KubernetesGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :namespace, type: :string, default: "default",
                               desc: "Kubernetes namespace"
      class_option :replicas, type: :numeric, default: 2,
                              desc: "Initial number of SSR replicas"
      class_option :image, type: :string, default: "reactive-views-ssr:latest",
                           desc: "Docker image for SSR server"
      class_option :port, type: :string, default: "5175",
                          desc: "SSR server port"
      class_option :memory_limit, type: :string, default: "512Mi",
                                  desc: "Memory limit per pod"
      class_option :cpu_limit, type: :string, default: "500m",
                               desc: "CPU limit per pod"
      class_option :output_dir, type: :string, default: "k8s",
                                desc: "Output directory for manifests"

      def create_output_directory
        empty_directory options[:output_dir]
      end

      def create_namespace
        template "namespace.yaml.tt", "#{options[:output_dir]}/namespace.yaml"
        say "✓ Created namespace manifest", :green
      end

      def create_configmap
        template "configmap.yaml.tt", "#{options[:output_dir]}/configmap.yaml"
        say "✓ Created ConfigMap manifest", :green
      end

      def create_deployment
        template "deployment.yaml.tt", "#{options[:output_dir]}/deployment.yaml"
        say "✓ Created Deployment manifest", :green
      end

      def create_service
        template "service.yaml.tt", "#{options[:output_dir]}/service.yaml"
        say "✓ Created Service manifest", :green
      end

      def create_hpa
        template "hpa.yaml.tt", "#{options[:output_dir]}/hpa.yaml"
        say "✓ Created HorizontalPodAutoscaler manifest", :green
      end

      def create_kustomization
        template "kustomization.yaml.tt", "#{options[:output_dir]}/kustomization.yaml"
        say "✓ Created kustomization.yaml", :green
      end

      def show_next_steps
        say ""
        say "=" * 60, :green
        say "Kubernetes manifests created in #{options[:output_dir]}/", :green
        say "=" * 60, :green
        say ""
        say "Next steps:", :cyan
        say ""
        say "1. Build and push the SSR Docker image:", :cyan
        say "   docker build -f Dockerfile.ssr -t #{options[:image]} .", :yellow
        say "   docker push #{options[:image]}", :yellow
        say ""
        say "2. Configure your Rails app to use the SSR service:", :cyan
        say "   # In your Rails deployment:", :yellow
        say "   env:", :yellow
        say "     - name: REACTIVE_VIEWS_SSR_URL", :yellow
        say "       value: http://reactive-views-ssr:#{options[:port]}", :yellow
        say ""
        say "3. Apply the manifests:", :cyan
        say "   kubectl apply -k #{options[:output_dir]}/", :yellow
        say ""
        say "4. Verify the deployment:", :cyan
        say "   kubectl get pods -n #{options[:namespace]} -l app=reactive-views-ssr", :yellow
        say "   kubectl logs -n #{options[:namespace]} -l app=reactive-views-ssr", :yellow
        say ""
      end
    end
  end
end
