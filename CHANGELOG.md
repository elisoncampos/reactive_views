# Changelog

All notable changes to the ReactiveViews gem will be documented in this file.

## [Unreleased]

### Fixed
- **Generator Idempotency**: The install generator can now be run multiple times safely. It properly detects and removes old `vite_client_tag` and `vite_javascript_tag` calls, replacing them with the unified `reactive_views_script_tag` helper.
- **Helper Robustness**: The `reactive_views_script_tag` helper now gracefully handles cases where `vite_rails` is not available or misconfigured, showing helpful error messages in development and failing silently in production.
- **Layout Transformation**: Improved regex patterns to catch all variations of Vite tags (extra whitespace, different quote styles, multiline).

### Added
- **Comprehensive Test Suite**: Full RSpec test coverage including:
  - Unit tests for TagTransformer, Renderer, ComponentResolver, ErrorOverlay, and Helpers
  - Integration tests for component rendering pipeline and generator
  - Dummy Rails app for integration testing using Combustion
  - WebMock for SSR server mocking
  - SimpleCov for code coverage reporting
- **Rake Tasks**: New rake tasks for test management:
  - `rake reactive_views:test:all` - Run all tests
  - `rake reactive_views:test:unit` - Run unit tests only
  - `rake reactive_views:test:integration` - Run integration tests only
  - `rake reactive_views:test:coverage` - Run with coverage report
  - `rake reactive_views:test:clean` - Clean test artifacts
- **Testing Documentation**: Comprehensive testing guide in `TESTING.md`
- **Generator Force Mode**: The install generator now respects `--force` flag to skip prompts during automated setups

### Changed
- **Generator Update Logic**: The `update_application_layout` method now:
  - Uses multiline regex patterns (`/m` flag) for robust tag detection
  - Removes existing `reactive_views_script_tag` before adding new one to prevent duplicates
  - Better handles edge cases like extra whitespace and comment blocks
  - Provides clearer status messages during updates

### Development
- Added development dependencies:
  - rspec-rails ~> 6.0
  - capybara ~> 3.39
  - selenium-webdriver ~> 4.16
  - webdrivers ~> 5.3
  - webmock ~> 3.19
  - simplecov ~> 0.22
  - combustion ~> 1.4
  - sqlite3 ~> 1.4

## [Previous Versions]

See git history for changes in previous versions.

