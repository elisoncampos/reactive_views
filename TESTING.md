# ReactiveViews Testing Guide

This document describes the testing infrastructure for the ReactiveViews gem.

## Test Structure

```
spec/
├── spec_helper.rb          # Base RSpec configuration
├── rails_helper.rb         # Rails integration configuration
├── support/                # Shared test utilities
│   ├── shared_contexts.rb  # Reusable test contexts
│   └── webmock.rb          # HTTP mocking configuration
├── fixtures/               # Test fixtures
│   └── components/         # Sample React components
├── dummy/                  # Lightweight Rails app for integration tests
│   ├── app/
│   │   ├── controllers/
│   │   └── views/
│   └── config/
├── reactive_views/         # Unit tests
│   ├── tag_transformer_spec.rb
│   ├── component_resolver_spec.rb
│   ├── renderer_spec.rb
│   ├── error_overlay_spec.rb
│   └── helpers_spec.rb
└── integration/            # Integration tests
    ├── component_rendering_spec.rb
    └── generator_spec.rb
```

## Running Tests

### All Tests
```bash
bundle exec rake reactive_views:test:all
# or simply
bundle exec rake spec
```

### Unit Tests Only
```bash
bundle exec rake reactive_views:test:unit
```

### Integration Tests Only
```bash
bundle exec rake reactive_views:test:integration
```

### With Coverage Report
```bash
bundle exec rake reactive_views:test:coverage
```

### Clean Test Artifacts
```bash
bundle exec rake reactive_views:test:clean
```

## Test Dependencies

The following gems are required for testing (automatically installed via gemspec):

- `rspec` and `rspec-rails` - Testing framework
- `combustion` - Lightweight Rails app for integration tests
- `webmock` - HTTP request mocking for SSR server tests
- `capybara` - Browser automation for system tests (future)
- `selenium-webdriver` - WebDriver for browser tests (future)
- `simplecov` - Code coverage reporting
- `sqlite3` - Database for test dummy app

## Test Coverage

Run tests with coverage:

```bash
COVERAGE=true bundle exec rspec
```

View coverage report: `open coverage/index.html`

## Writing Tests

### Unit Tests

Unit tests should test individual components in isolation:

```ruby
require "spec_helper"

RSpec.describe ReactiveViews::TagTransformer do
  describe ".transform" do
    it "transforms PascalCase tags" do
      html = "<MyComponent prop='value' />"
      result = described_class.transform(html)
      expect(result).to include("data-island-uuid")
    end
  end
end
```

### Integration Tests

Integration tests use the dummy Rails app:

```ruby
require "rails_helper"

RSpec.describe "Component Rendering", type: :request do
  it "renders components end-to-end" do
    get "/with_component"
    expect(response.body).to include("data-island-uuid")
  end
end
```

### Mocking SSR Server

Use WebMock to mock SSR server responses:

```ruby
before do
  stub_request(:post, "http://localhost:5175/render")
    .to_return(
      status: 200,
      body: { html: "<div>SSR Content</div>", error: nil }.to_json
    )
end
```

## Continuous Integration

Tests can be run in CI environments. Set up your CI to:

1. Install dependencies: `bundle install`
2. Run tests: `bundle exec rake spec`
3. (Optional) Upload coverage to Codecov

## Test Environment Configuration

The test dummy app is configured via:
- `spec/dummy/config/initializers/reactive_views.rb`
- `spec/rails_helper.rb`

Combustion is used to load only the necessary Rails components:
- action_controller
- action_view

No ActiveRecord is loaded by default (use `:memory:` SQLite if needed).

## Troubleshooting

### Tests fail with "cannot load such file"

Run: `bundle install` to ensure all dependencies are installed.

### Combustion errors

Ensure the dummy app structure is correct:
```bash
ls -la spec/dummy/
```

### WebMock errors

Ensure network requests are properly stubbed or disable net connect:
```ruby
WebMock.disable_net_connect!(allow_localhost: true)
```

## Future Enhancements

- [ ] System tests with Capybara for full browser testing
- [ ] Multi-version Rails testing (7.0, 7.1, 8.0)
- [ ] Multi-version Ruby testing (3.1, 3.2, 3.3)
- [ ] Performance benchmarks
- [ ] Visual regression testing

