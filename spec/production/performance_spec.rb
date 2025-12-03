# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'
require 'benchmark'

RSpec.describe 'Performance', type: :production do
  before(:all) do
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'asset bundle size', :requires_production_build do
    let(:metrics) { ProductionHelpers.measure_asset_metrics }

    # Size thresholds in KB
    JS_THRESHOLD_KB = 500
    CSS_THRESHOLD_KB = 100
    TOTAL_THRESHOLD_KB = 600

    it "JavaScript bundle is under #{JS_THRESHOLD_KB}KB" do
      size_kb = metrics[:total_js_size] / 1024.0
      expect(size_kb).to be < JS_THRESHOLD_KB,
        "JS bundle size (#{size_kb.round(2)}KB) exceeds threshold (#{JS_THRESHOLD_KB}KB)"
    end

    it "CSS bundle is under #{CSS_THRESHOLD_KB}KB" do
      size_kb = metrics[:total_css_size] / 1024.0
      expect(size_kb).to be < CSS_THRESHOLD_KB,
        "CSS bundle size (#{size_kb.round(2)}KB) exceeds threshold (#{CSS_THRESHOLD_KB}KB)"
    end

    it "total bundle is under #{TOTAL_THRESHOLD_KB}KB" do
      size_kb = metrics[:total_size] / 1024.0
      expect(size_kb).to be < TOTAL_THRESHOLD_KB,
        "Total bundle size (#{size_kb.round(2)}KB) exceeds threshold (#{TOTAL_THRESHOLD_KB}KB)"
    end

    it 'reports bundle sizes' do
      puts "\n  Bundle Size Report:"
      puts "    Total JS:  #{(metrics[:total_js_size] / 1024.0).round(2)} KB"
      puts "    Total CSS: #{(metrics[:total_css_size] / 1024.0).round(2)} KB"
      puts "    Total:     #{(metrics[:total_size] / 1024.0).round(2)} KB"
      puts "    JS files:  #{metrics[:js_file_count]}"
      puts "    CSS files: #{metrics[:css_file_count]}"

      if metrics[:largest_js_file]
        largest_size = File.size(File.join(ProductionHelpers::VITE_OUTPUT_PATH, metrics[:largest_js_file]))
        puts "    Largest JS: #{metrics[:largest_js_file]} (#{(largest_size / 1024.0).round(2)} KB)"
      end
    end
  end

  describe 'SSR response time' do
    # SSR response time thresholds in seconds
    COLD_START_THRESHOLD = 5.0 # First render (includes bundling)
    WARM_THRESHOLD = 0.5 # Subsequent renders
    BATCH_THRESHOLD = 2.0 # Batch of 5 components

    before do
      skip 'SSR server not running' unless ssr_available?
    end

    let(:component_path) do
      File.join(ProductionHelpers::DUMMY_APP_PATH, 'app', 'views', 'components', 'Counter.tsx')
    end

    it 'cold start render is under threshold' do
      # Clear SSR cache first
      clear_ssr_cache

      time = Benchmark.realtime do
        ReactiveViews::Renderer.render(component_path, { initialCount: 0 })
      end

      expect(time).to be < COLD_START_THRESHOLD,
        "Cold start render (#{time.round(3)}s) exceeds threshold (#{COLD_START_THRESHOLD}s)"

      puts "\n  Cold start render: #{time.round(3)}s"
    end

    it 'warm render is under threshold' do
      # Warm up
      ReactiveViews::Renderer.render(component_path, { initialCount: 0 })

      # Measure warm render
      time = Benchmark.realtime do
        ReactiveViews::Renderer.render(component_path, { initialCount: 0 })
      end

      expect(time).to be < WARM_THRESHOLD,
        "Warm render (#{time.round(3)}s) exceeds threshold (#{WARM_THRESHOLD}s)"

      puts "\n  Warm render: #{time.round(3)}s"
    end

    it 'batch render is efficient' do
      # Warm up
      ReactiveViews::Renderer.render(component_path, {})

      components = 5.times.map { { componentPath: component_path, props: { initialCount: 0 } } }

      time = Benchmark.realtime do
        ReactiveViews::Renderer.batch_render(components)
      end

      expect(time).to be < BATCH_THRESHOLD,
        "Batch render of 5 (#{time.round(3)}s) exceeds threshold (#{BATCH_THRESHOLD}s)"

      per_component = time / 5
      puts "\n  Batch render (5 components): #{time.round(3)}s (#{per_component.round(3)}s per component)"
    end

    it 'reports SSR timing stats' do
      # Multiple runs for average
      times = []
      5.times do
        times << Benchmark.realtime do
          ReactiveViews::Renderer.render(component_path, { initialCount: 0 })
        end
      end

      avg = times.sum / times.size
      min = times.min
      max = times.max

      puts "\n  SSR Timing Stats (5 runs):"
      puts "    Average: #{avg.round(3)}s"
      puts "    Min:     #{min.round(3)}s"
      puts "    Max:     #{max.round(3)}s"
    end
  end

  describe 'hydration timing', type: :system, js: true do
    let(:render_timeout) { 20 }

    # Hydration should complete quickly
    HYDRATION_THRESHOLD_MS = 1000

    it 'hydration completes within threshold' do
      # Inject timing code before visit
      visit '/counter'

      # Wait for hydration to complete
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Check hydration timing (if tracked)
      # This depends on whether timing is instrumented in the boot script
      timing = page.evaluate_script(<<~JS)
        (function() {
          if (window.performance && window.performance.getEntriesByType) {
            var entries = window.performance.getEntriesByType('measure');
            var hydration = entries.find(function(e) { return e.name.includes('hydrat'); });
            return hydration ? hydration.duration : null;
          }
          return null;
        })()
      JS

      if timing
        puts "\n  Hydration timing: #{timing.round(2)}ms"
        expect(timing).to be < HYDRATION_THRESHOLD_MS,
          "Hydration (#{timing.round(2)}ms) exceeds threshold (#{HYDRATION_THRESHOLD_MS}ms)"
      else
        # If timing not instrumented, just verify hydration happened
        expect(page).to have_css('[data-reactive-hydrated="true"]')
      end
    end

    it 'reports performance metrics' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Get navigation timing
      timing = page.evaluate_script(<<~JS)
        (function() {
          if (window.performance && window.performance.timing) {
            var t = window.performance.timing;
            return {
              domContentLoaded: t.domContentLoadedEventEnd - t.navigationStart,
              domComplete: t.domComplete - t.navigationStart,
              loadEvent: t.loadEventEnd - t.navigationStart
            };
          }
          return null;
        })()
      JS

      if timing
        puts "\n  Page Load Metrics:"
        puts "    DOMContentLoaded: #{timing['domContentLoaded']}ms"
        puts "    DOM Complete:     #{timing['domComplete']}ms"
        puts "    Load Event:       #{timing['loadEvent']}ms"
      end
    end
  end

  describe 'memory usage', type: :system, js: true do
    let(:render_timeout) { 20 }

    it 'does not leak memory on repeated hydrations' do
      # Get baseline memory
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      initial_memory = get_js_heap_size

      # Navigate back and forth multiple times
      5.times do
        visit '/turbo_mixed'
        sleep 0.5
        visit '/counter'
        expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
      end

      final_memory = get_js_heap_size

      if initial_memory && final_memory
        growth = final_memory - initial_memory
        growth_percent = (growth.to_f / initial_memory * 100).round(2)

        puts "\n  Memory Report:"
        puts "    Initial: #{(initial_memory / 1024.0 / 1024.0).round(2)} MB"
        puts "    Final:   #{(final_memory / 1024.0 / 1024.0).round(2)} MB"
        puts "    Growth:  #{(growth / 1024.0 / 1024.0).round(2)} MB (#{growth_percent}%)"

        # Allow some growth but flag significant leaks
        expect(growth_percent).to be < 50,
          "Memory grew by #{growth_percent}% - possible memory leak"
      end
    end

    private

    def get_js_heap_size
      page.evaluate_script(<<~JS)
        (function() {
          if (window.performance && window.performance.memory) {
            return window.performance.memory.usedJSHeapSize;
          }
          return null;
        })()
      JS
    end
  end

  private

  def ssr_available?
    require 'net/http'
    uri = URI.parse("http://localhost:#{TestServers::SSR_PORT}/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 2
    http.read_timeout = 2
    response = http.get(uri.request_uri)
    response.code.to_i == 200
  rescue StandardError
    false
  end

  def clear_ssr_cache
    require 'net/http'
    uri = URI.parse("http://localhost:#{TestServers::SSR_PORT}/clear-cache")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    request = Net::HTTP::Post.new(uri.request_uri)
    http.request(request)
  rescue StandardError
    # Ignore errors
  end
end

