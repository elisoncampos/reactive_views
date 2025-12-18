# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Component Rendering Integration', type: :request do
  before do
    ReactiveViews.configure do |config|
      config.enabled = true
    end
  end

  describe 'full rendering pipeline' do
    context 'when ReactiveViews is disabled' do
      before do
        ReactiveViews.config.enabled = false
      end

      after do
        ReactiveViews.config.enabled = true
      end

      it 'returns HTML unchanged' do
        get '/with_component'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('<SimpleComponent')
        expect(response.body).not_to include('data-island-uuid')
      end
    end

    context 'with missing component' do
      it 'renders page without breaking' do
        get '/with_error'

        expect(response).to have_http_status(:ok)
        # Page should still render even if component resolution fails
        expect(response.body).to include('ReactiveViews Test App')
      end
    end
  end

  describe 'layout integration' do
    it 'includes reactive_views_script_tag in head' do
      get '/'

      expect(response).to have_http_status(:ok)
      # In test mode, direct script tags are emitted
      expect(response.body).to include('@vite/client')
      expect(response.body).to include('entrypoints/application.js')
    end

    it 'includes SSR URL meta tag' do
      get '/'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('reactive-views-ssr-url')
    end
  end
end
