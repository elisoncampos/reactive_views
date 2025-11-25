# frozen_string_literal: true

ReactiveViews.configure do |config|
  config.enabled = true
  config.full_page_enabled = true
  config.props_inference_enabled = true
  config.ssr_url = 'http://localhost:5175'
  # Increase timeout for test environment (bundling can take longer under load)
  config.ssr_timeout = 30
  config.batch_timeout = 45
  config.component_views_paths = [
    Rails.root.join('app', 'views', 'components').to_s
  ]
  config.component_js_paths = [
    Rails.root.join('app', 'javascript', 'components').to_s
  ]
end
