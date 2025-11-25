# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Full-page TSX.ERB rendering', type: :request do
  let(:views_root) { Rails.root.join('app', 'views') }
  let(:users_views) { views_root.join('users') }

  before do
    # Clear view lookup context before creating templates
    ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)

    FileUtils.mkdir_p(users_views)

    # Enable full-page rendering
    ReactiveViews.configure do |config|
      config.full_page_enabled = true
      config.enabled = true
      config.props_inference_enabled = true
      config.ssr_url = 'http://localhost:5175'
    end

    stub_const('UsersController', Class.new(ActionController::Base) do
      include ReactiveViewsHelper
      # Explicitly set view_paths to the dummy app's view path
      # This ensures lookups happen in the correct place even if the controller is dynamically defined
      prepend_view_path Rails.root.join('app', 'views')

      def index
        @users = [ { id: 1, name: 'Alice' }, { id: 2, name: 'Bob' } ]
        @page_title = 'All Users'
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

      # Always stub SSR for integration tests - temp templates aren't in Vite's build pipeline
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata).and_return(
        { html: '<main><h1>Users List</h1><ul><li>Alice</li><li>Bob</li></ul></main>', bundle_key: nil }
      )

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

      captured_props = nil

      # Always stub SSR for integration tests - temp templates aren't in Vite's build pipeline
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata) do |_path, props|
        captured_props = props
        { html: '<div><h1>All Users</h1><p>Count: 2</p></div>', bundle_key: nil }
      end

      get '/users'

      expect(response).to have_http_status(:ok)
      normalized = response.body.gsub('<!-- -->', '')
      expect(normalized).to include('All Users')
      expect(normalized).to include('Count: 2')
      expect(captured_props).to include(:users)
      expect(captured_props[:users].length).to eq(2)
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

      captured_props = nil

      # Always stub SSR for integration tests - temp templates aren't in Vite's build pipeline
      allow(ReactiveViews::Renderer).to receive(:render_path_with_metadata) do |_path, props|
        captured_props = props
        { html: '<div><p>Welcome, Admin User</p><p>Users: 2</p></div>', bundle_key: nil }
      end

      get '/users'

      normalized = response.body.gsub('<!-- -->', '')
      expect(normalized).to include('Welcome, Admin User')
      expect(captured_props).to include(:users, :current_user)
      expect(captured_props[:current_user]).to include(name: 'Admin User')
    end
  end

  describe 'when full_page_enabled is false' do
    it 'does not fallback to .tsx.erb' do
      ReactiveViews.configure do |config|
        config.full_page_enabled = false
      end

      File.write(users_views.join('index.tsx.erb'), 'export default function() { return <div>Test</div>; }')

      # When full_page_enabled is false, the MissingTemplate exception is re-raised
      # (Because render override won't add :tsx/:jsx to formats)
      expect { get '/users' }.to raise_error(ActionView::MissingTemplate)
    end
  end
end
