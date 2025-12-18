# frozen_string_literal: true

require 'webmock/rspec'

# Allow localhost connections by default (for real SSR server)
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  # Reset WebMock and HTTP client state between tests to prevent pollution
  config.after(:each) do
    WebMock.reset!
    # Re-enable localhost after reset
    WebMock.disable_net_connect!(allow_localhost: true)

    # Shutdown the HTTP client to clear any stale connections
    if ReactiveViews.const_defined?(:Renderer)
      ReactiveViews::Renderer.send(:shutdown_client) if ReactiveViews::Renderer.respond_to?(:shutdown_client, true)
    end
  end
end
