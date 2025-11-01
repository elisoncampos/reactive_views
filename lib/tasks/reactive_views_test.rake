# frozen_string_literal: true

namespace :reactive_views do
  namespace :test do
    desc "Setup test environment (install dependencies)"
    task :setup do
      puts "Setting up ReactiveViews test environment..."

      # Install gem dependencies
      puts "Installing gem dependencies..."
      sh "bundle install"

      puts "✓ Test environment ready!"
    end

    desc "Run all tests (unit + integration)"
    task :all do
      puts "Running ReactiveViews test suite..."
      puts ""

      # Set test environment
      ENV["RAILS_ENV"] = "test"

      # Run RSpec
      begin
        sh "bundle exec rspec"
        puts ""
        puts "✓ All tests passed!"
      rescue => e
        puts ""
        puts "✗ Some tests failed. See output above for details."
        exit 1
      end
    end

    desc "Run unit tests only"
    task :unit do
      puts "Running unit tests..."
      ENV["RAILS_ENV"] = "test"
      sh "bundle exec rspec spec/reactive_views"
    end

    desc "Run integration tests only"
    task :integration do
      puts "Running integration tests..."
      ENV["RAILS_ENV"] = "test"
      sh "bundle exec rspec spec/integration"
    end

    desc "Clean test artifacts and coverage reports"
    task :clean do
      puts "Cleaning test artifacts..."

      FileUtils.rm_rf("coverage") if File.exist?("coverage")
      FileUtils.rm_rf("spec/dummy/tmp") if File.exist?("spec/dummy/tmp")
      FileUtils.rm_rf("spec/dummy/log") if File.exist?("spec/dummy/log")

      # Clean any leftover test component files
      test_fixtures = Dir.glob("spec/fixtures/components/**/*")
      generated_files = test_fixtures.select { |f| File.file?(f) && !f.end_with?("SimpleComponent.tsx") }
      generated_files.each { |f| FileUtils.rm(f) }

      puts "✓ Test artifacts cleaned!"
    end

    desc "Run tests with coverage report"
    task :coverage do
      puts "Running tests with coverage report..."
      ENV["RAILS_ENV"] = "test"
      ENV["COVERAGE"] = "true"

      Rake::Task["reactive_views:test:all"].invoke

      if File.exist?("coverage/index.html")
        puts ""
        puts "Coverage report generated at: coverage/index.html"
      end
    end
  end

  # Alias for convenience
  desc "Run all ReactiveViews tests (alias for test:all)"
  task test: ["test:all"]
end
