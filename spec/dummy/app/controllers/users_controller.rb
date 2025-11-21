# frozen_string_literal: true

class UsersController < ActionController::Base
  include ReactiveViewsHelper
  layout 'application'

  def index
    @users = [
      {
        id: 1,
        name: 'John Doe',
        email: 'john.doe@example.com'
      },
      {
        id: 2,
        name: 'Jane Doe',
        email: 'jane.doe@example.com'
      },
      {
        id: 3,
        name: 'Jim Doe',
        email: 'jim.doe@example.com'
      },
      {
        id: 4,
        name: 'Jill Doe',
        email: 'jill.doe@example.com'
      },
      {
        id: 5,
        name: 'Jack Doe',
        email: 'jack.doe@example.com'
      }
    ]
  end

  def show
    @user = { id: 1, name: 'Alice', bio: 'Software Developer' }
    @page_title = 'User Profile'
  end
end
