# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TSX ERB partial composition', type: :request do
  let(:views_root) { Rails.root.join('app', 'views') }
  let(:users_views) { views_root.join('users') }

  before do
    # Clear view lookup context before creating templates
    ActionView::LookupContext::DetailsKey.clear if defined?(ActionView::LookupContext::DetailsKey)

    FileUtils.mkdir_p(users_views) unless Dir.exist?(users_views)

    # Enable full-page rendering
    ReactiveViews.configure do |config|
      config.full_page_enabled = true
      config.enabled = true
      config.props_inference_enabled = false # Keep it simple for this test
      config.ssr_url = 'http://localhost:5175'
    end

    # Create a test controller using stub_const (same approach as full_page_rendering_spec)
    stub_const('UsersController', Class.new(ActionController::Base) do
      include ReactiveViewsHelper
      prepend_view_path Rails.root.join('app', 'views')

      def index
        @users = [ { id: 1, name: 'Alice' }, { id: 2, name: 'Bob' } ]
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
    # Do not remove users_views as they are needed for other tests
  end

  describe 'partial composition in .tsx.erb templates' do
    it 'evaluates ERB first and composes TSX with partial before SSR' do
      # Note: Files are already created in spec/dummy/app/views/users by setup
      # But we can overwrite them if needed or just assert on existing ones

      # Ensure partial content matches expectations
      partial_path = users_views.join('_filters.tsx.erb')
      File.write(partial_path, <<~TSX)
        export function UsersFilters() {
          return <section id="filters">Filters Section</section>;
        }
      TSX

      # Ensure index content matches expectations
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

      rendered_source = nil

      if ENV['REACTIVE_VIEWS_SKIP_SERVERS'] == '1'
        allow(ReactiveViews::Renderer).to receive(:render_path) do |path, _props|
          rendered_source = File.read(path)
          '<main><h1>Users List</h1><section id="filters">Filters Section</section></main>'
        end
      else
        allow(ReactiveViews::Renderer).to receive(:render_path).and_wrap_original do |method, path, props|
          rendered_source = File.read(path)
          method.call(path, props)
        end
      end

      get '/users'

      expect(response).to have_http_status(:ok)
      expect(rendered_source).not_to be_nil
      expect(rendered_source).to include('export function UsersFilters()')
      expect(rendered_source).to include('<UsersFilters />')
      expect(response.body).to include('Filters Section')
      expect(response.body).to include('Users List')
    end
  end

  describe 'content_for in .tsx.erb templates' do
    it 'evaluates content_for blocks and passes yielded content as props' do
      # Ensure show content matches expectations
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

      captured_props = nil

      if ENV['REACTIVE_VIEWS_SKIP_SERVERS'] == '1'
        allow(ReactiveViews::Renderer).to receive(:render_path) do |_path, props|
          captured_props = props
          <<~HTML
            <main>
              <h1>User Profile</h1>
              <div class="user-profile">
                <h2>Alice</h2>
                <p>Software Developer</p>
              </div>
            </main>
          HTML
        end
      else
        allow(ReactiveViews::Renderer).to receive(:render_path).and_wrap_original do |method, path, props|
          captured_props = props
          method.call(path, props)
        end
      end

      get '/users/1'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('User Profile')
      expect(response.body).to include('Software Developer')
      expect(captured_props).to include(:page_title)
      expect(captured_props[:page_title]).to eq('User Profile')
    end
  end
end
