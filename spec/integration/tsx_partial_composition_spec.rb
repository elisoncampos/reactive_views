# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TSX ERB partial composition', type: :request do
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
      config.props_inference_enabled = false # Keep it simple for this test
    end

    # Create a test controller using stub_const (same approach as full_page_rendering_spec)
    stub_const('UsersController', Class.new(ActionController::Base) do
      include ReactiveViewsHelper

      def index
        @users = [{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }]
        render :index
      end

      def show
        @user = { id: 1, name: 'Alice', bio: 'Software Developer' }
        @page_title = 'User Profile'
        render :show
      end
    end)

    # Define routes for this test
    Rails.application.routes.draw do
      get '/users' => 'users#index'
      get '/users/:id' => 'users#show', as: :user
    end
  end

  after do
    # Clean up
    Rails.application.reload_routes!
    ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)
    FileUtils.rm_rf(users_views)
  end

  describe 'partial composition in .tsx.erb templates' do
    it 'evaluates ERB first and composes TSX with partial before SSR' do
      # Create the partial
      partial_path = users_views.join('_filters.tsx.erb')
      File.write(partial_path, <<~TSX)
        export function UsersFilters() {
          return <section id="filters">Filters Section</section>;
        }
      TSX

      # Create the main template that uses the partial
      index_path = users_views.join('index.tsx.erb')
      File.write(index_path, <<~TSX)
        <%= render "users/filters" %>

        export default function UsersPage({ users }: { users: Array<{ id: number; name: string }> }) {
          return (
            <main>
              <h1>Users List</h1>
              <UsersFilters />
              <ul>
                {users.map(user => (
                  <li key={user.id}>{user.name}</li>
                ))}
              </ul>
            </main>
          );
        }
      TSX

      # Stub infer-props
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: ['users'] }.to_json)

      # Intercept SSR call and assert the generated TSX file includes the partial content
      rendered_source = nil
      stub_request(:post, 'http://localhost:5175/render').to_return do |request|
        payload = JSON.parse(request.body)
        tsx_path = payload['componentPath']
        source = File.read(tsx_path)
        rendered_source = source

        # Verify that ERB was processed and partial was included
        expect(source).to include('export function UsersFilters()')
        expect(source).to include('<UsersFilters />')

        { status: 200, body: { html: '<div>SSR OK</div>' }.to_json }
      end

      get '/users'

      expect(response).to have_http_status(:ok)
      expect(rendered_source).not_to be_nil
      expect(response.body).to include('SSR OK')
    end
  end

  describe 'content_for in .tsx.erb templates' do
    it 'evaluates content_for blocks and passes yielded content as props' do
      # Create the template with content_for
      File.write(users_views.join('show.tsx.erb'), <<~TSX)
        <% content_for :page_title, @page_title %>
        <% content_for :meta_description, "User profile for \#{@user[:name]}" %>

        export default function UserProfile({
          user,
          page_title
        }: {
          user: { id: number; name: string; bio: string };
          page_title: string;
        }) {
          return (
            <main>
              <h1>{page_title}</h1>
              <div className="user-profile">
                <h2>{user.name}</h2>
                <p>{user.bio}</p>
                <p>User ID: {user.id}</p>
              </div>
            </main>
          );
        }
      TSX

      # Stub infer-props
      stub_request(:post, 'http://localhost:5175/infer-props')
        .to_return(status: 200, body: { keys: %w[user page_title] }.to_json)

      # Intercept SSR call
      stub_request(:post, 'http://localhost:5175/render').to_return do |request|
        payload = JSON.parse(request.body)
        props = payload['props']

        # Verify content_for was processed and included in props
        expect(props['page_title']).to eq('User Profile')

        { status: 200, body: { html: '<div>User Profile Rendered</div>' }.to_json }
      end

      get '/users/1'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('User Profile Rendered')
    end
  end
end
