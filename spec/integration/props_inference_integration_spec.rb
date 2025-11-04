# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Props inference integration', type: :request do
  let(:views_root) { Rails.root.join('app', 'views') }
  let(:users_views) { views_root.join('users') }

  before do
    FileUtils.mkdir_p(users_views)

    # Enable full-page rendering with props inference
    ReactiveViews.configure do |config|
      config.full_page_enabled = true
      config.enabled = true
      config.props_inference_enabled = true
    end

    stub_const('UsersController', Class.new(ActionController::Base) do
      include ReactiveViewsHelper

      def index
        @users = [{ id: 1, name: 'Alice' }]
        @secret = 'should_not_leak'
        reactive_view_props(admin: true, current_user: { id: 1, name: 'Admin' })
        render :index
      end
    end)

    Rails.application.routes.draw do
      get '/users' => 'users#index'
    end
  end

  after do
    Rails.application.reload_routes!
    ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)
    FileUtils.rm_rf(users_views)
  end

  it 'passes only inferred keys plus explicit reactive_view_props to SSR' do
    File.write(users_views.join('index.tsx.erb'), <<~TSX)
      type User = { id: number; name: string };

      export default function UsersPage({ users, current_user }: { users: User[]; current_user: User }) {
        return <div id="users-page">Users: {users.length} - {current_user.name}</div>;
      }
    TSX

    # Stub inference to return only the used keys
    stub_request(:post, 'http://localhost:5175/infer-props')
      .to_return(status: 200, body: { keys: %w[users current_user] }.to_json)

    captured_props = nil
    stub_request(:post, 'http://localhost:5175/render').to_return do |request|
      payload = JSON.parse(request.body)
      captured_props = payload['props']
      { status: 200, body: { html: '<div>SSR Inferred</div>' }.to_json }
    end

    get '/users'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('SSR Inferred')

    # Ensure only the inferred keys plus explicit extras were sent
    expect(captured_props.keys.map(&:to_s)).to include('users', 'current_user', 'admin')
    expect(captured_props.keys.map(&:to_s)).not_to include('secret')
  end
end
