# frozen_string_literal: true

require_relative "lib/reactive_views/version"

Gem::Specification.new do |spec|
  spec.name = "reactive_views"
  spec.version = ReactiveViews::VERSION
  spec.authors = ["Elison Campos"]
  spec.email = ["your.email@example.com"]

  spec.summary = "Reactive, incremental React for Rails — SSR + hydration islands with optional SPA-like navigation."
  spec.description = "ReactiveViews brings React components to Rails with SSR and client-side hydration islands."
  spec.homepage = "https://github.com/yourusername/reactive_views"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
      # Note: node/ssr/ files are included for SSR server runtime
    end
  end

  # The TypeScript source will be copied during installation, no pre-built files needed
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "nokogiri", ">= 1.14"
  spec.add_dependency "rails", ">= 6.1"
  spec.add_dependency "vite_rails"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "capybara", "~> 3.39"
  spec.add_development_dependency "selenium-webdriver", "~> 4.16"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "combustion", "~> 1.4"
  spec.add_development_dependency "sqlite3", "~> 2.0"
end
