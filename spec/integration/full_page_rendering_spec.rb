# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Full-page TSX.ERB rendering', type: :request do
  let(:views_root) { Rails.root.join('app', 'views') }
  let(:users_views) { views_root.join('users') }

  before do
    FileUtils.mkdir_p(users_views)

    # Enable full-page rendering
    ReactiveViews.configure do |config|
      config.full_page_enabled = true
      config.enabled = true
      config.props_inference_enabled = true
    end

    stub_const('UsersController', Class.new(ActionController::Base) do
      include ReactiveViewsHelper

      def index
        @users = [{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }]
        reactive_view_props(current_user: { name: 'Admin User' })
        render :index
      end
    end)

    Rails.application.routes.draw do
      get '/users' => 'users#index'
    end
  end

  after do
    Rails.application.reload_routes!
    # Clear ActionView template cache
    ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)
    FileUtils.rm_rf(users_views)
  end

  describe 'when no .html.erb template exists' do
    it 'falls back to .tsx.erb template and SSRs it' do
      File.write(users_views.join('index.tsx.erb'), <<~TSX)
        export default function UsersIndex({ users }) {
          return (
            <main>
              <h1>Users List</h1>
              <ul>
                {users.map(user => (
                  <li key={user.id}>{user.name}</li>
                ))}
              </ul>
            </main>
          );
        }
      TSX

      # Stub props inference
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: ['users'] }.to_json)

      # Stub SSR response
      stub_request(:post, 'http://localhost:5175/render')
        .to_return(status: 200, body: {
          html: '<main><h1>Users List</h1><ul><li>Alice</li><li>Bob</li></ul></main>'
        }.to_json)

      get '/users'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<h1>Users List</h1>')
      expect(response.body).to include('<li>Alice</li>')
      expect(response.body).to include('<li>Bob</li>')
    end

    it 'passes instance variables as props' do
      File.write(users_views.join('index.tsx.erb'), <<~TSX)
        export default function UsersIndex({ users, page_title }) {
          return (
            <div>
              <h1>{page_title}</h1>
              <p>Count: {users.length}</p>
            </div>
          );
        }
      TSX

      # Stub props inference
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: %w[users page_title] }.to_json)

      # Capture the props sent to SSR
      received_props = nil
      stub_request(:post, 'http://localhost:5175/render')
        .to_return do |request|
          body = JSON.parse(request.body)
          received_props = body['props']
          { status: 200, body: { html: '<div>Rendered</div>' }.to_json }
        end

      get '/users'

      expect(received_props).to include('users')
      expect(received_props['users']).to be_an(Array)
      expect(received_props['users'].length).to eq(2)
    end
  end

  describe 'when .html.erb template exists' do
    it 'uses .html.erb and does not fall back to .tsx.erb' do
      File.write(users_views.join('index.html.erb'), '<h1>HTML Template</h1>')
      File.write(users_views.join('index.tsx.erb'), 'export default function() { return <h1>TSX Template</h1>; }')

      # Stub SSR in case TagTransformer runs (it shouldn't for plain HTML, but just in case)
      stub_request(:post, 'http://localhost:5175/render')
        .to_return(status: 200, body: { html: '<div>Should not be called</div>' }.to_json)
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: [] }.to_json)

      get '/users'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('HTML Template')
      expect(response.body).not_to include('TSX Template')
      expect(response.body).not_to include('Should not be called')
    end
  end

  describe 'with reactive_view_props helper' do
    it 'merges explicit props with instance variables' do
      File.write(users_views.join('index.tsx.erb'), <<~TSX)
        export default function UsersIndex({ users, current_user }) {
          return (
            <div>
              <p>Welcome, {current_user.name}</p>
              <p>Users: {users.length}</p>
            </div>
          );
        }
      TSX

      # Stub props inference
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: %w[users current_user] }.to_json)

      received_props = nil
      stub_request(:post, 'http://localhost:5175/render')
        .to_return do |request|
          body = JSON.parse(request.body)
          received_props = body['props']
          { status: 200, body: { html: '<div>Rendered</div>' }.to_json }
        end

      get '/users'

      expect(received_props).to include('users', 'current_user')
      expect(received_props['current_user']).to include('name' => 'Admin User')
    end
  end

  describe 'when full_page_enabled is false' do
    it 'does not fallback to .tsx.erb' do
      ReactiveViews.configure do |config|
        config.full_page_enabled = false
      end

      File.write(users_views.join('index.tsx.erb'), 'export default function() { return <div>Test</div>; }')

      # When full_page_enabled is false, the MissingTemplate exception is re-raised
      expect { get '/users' }.to raise_error(ActionView::MissingTemplate)
    end
  end
end
