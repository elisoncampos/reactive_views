# frozen_string_literal: true

namespace :reactive_views do
  desc "Build production assets with Vite"
  task :build do
    puts "[ReactiveViews] Building production assets..."

    # Check if vite is available
    unless system("which npx > /dev/null 2>&1") || system("which yarn > /dev/null 2>&1")
      puts "[ReactiveViews] Warning: npx/yarn not found, skipping Vite build"
      next
    end

    # Check if vite.config exists
    vite_config = %w[vite.config.mts vite.config.ts vite.config.js].find { |f| File.exist?(f) }
    unless vite_config
      puts "[ReactiveViews] Warning: No vite.config found, skipping Vite build"
      next
    end

    # Set production environment
    ENV["NODE_ENV"] ||= "production"

    # Run Vite build
    build_cmd = if File.exist?("node_modules/.bin/vite")
                  "node_modules/.bin/vite build"
    elsif system("which npx > /dev/null 2>&1")
                  "npx vite build"
    else
                  "yarn vite build"
    end

    puts "[ReactiveViews] Running: #{build_cmd}"

    success = system(build_cmd)

    if success
      puts "[ReactiveViews] ✓ Production assets built successfully"

      # Verify manifest exists
      manifest_path = "public/vite/.vite/manifest.json"
      alt_manifest_path = "public/vite/manifest.json"

      if File.exist?(manifest_path) || File.exist?(alt_manifest_path)
        puts "[ReactiveViews] ✓ Vite manifest generated"
      else
        puts "[ReactiveViews] Warning: Vite manifest not found at expected location"
      end
    else
      puts "[ReactiveViews] ✗ Vite build failed"
      exit 1
    end
  end

  desc "Start the ReactiveViews SSR server (for development)"
  task :ssr do
    gem_root = if defined?(Bundler)
      spec = Bundler.load.specs.find { |s| s.name == "reactive_views" }
      spec&.gem_dir
    end
    gem_root ||= Gem.loaded_specs["reactive_views"]&.gem_dir

    if gem_root.nil?
      puts "Error: Could not find reactive_views gem directory"
      exit 1
    end

    ssr_script = File.join(gem_root, "node", "ssr", "server.mjs")

    unless File.exist?(ssr_script)
      puts "Error: SSR server script not found at: #{ssr_script}"
      exit 1
    end

    # Find node executable
    node_path = `which node 2>/dev/null`.strip
    if node_path.empty?
      # Check common locations
      candidates = [
        File.expand_path("~/.asdf/shims/node"),
        File.expand_path("~/.nvm/current/bin/node"),
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        "/usr/bin/node",
        File.expand_path("~/.volta/bin/node")
      ]
      node_path = candidates.find { |p| File.executable?(p) }
    end

    if node_path.nil? || node_path.empty?
      puts "Error: Could not find node executable"
      puts "Make sure Node.js is installed and available in your PATH"
      exit 1
    end

    puts "[ReactiveViews] Starting SSR server..."
    exec(node_path, ssr_script)
  end
end

# Hook into assets:precompile if Rails is available and the task exists
if defined?(Rails) && Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance([ "reactive_views:build" ])
end

