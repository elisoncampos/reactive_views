# frozen_string_literal: true

require_relative 'lib/reactive_views/version'

Gem::Specification.new do |spec|
  spec.name = 'reactive_views'
  spec.version = ReactiveViews::VERSION
  spec.authors = ['Elison Campos']
  spec.email = ['elison.campos@gmail.com']

  spec.summary = 'Reactive, incremental React for Rails — SSR + hydration islands with optional SPA-like navigation.'
  spec.description = 'ReactiveViews brings React components to Rails with SSR and client-side hydration islands.'
  spec.homepage = 'https://github.com/elisoncampos/reactive_views'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'nokogiri', '>= 1.14'
  spec.add_dependency 'rails', '>= 6.1'
  spec.add_dependency 'vite_rails'

  spec.add_development_dependency 'capybara', '~> 3.39'
  spec.add_development_dependency 'combustion', '~> 1.4'
  spec.add_development_dependency 'puma', '~> 6.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-rails', '~> 6.0'
  spec.add_development_dependency 'selenium-webdriver', '~> 4.16'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'sqlite3', '~> 2.0'
  spec.add_development_dependency 'webmock', '~> 3.19'
end
