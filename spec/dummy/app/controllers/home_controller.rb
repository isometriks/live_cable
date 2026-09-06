# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    render inline: <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>LiveCable Test App</title>
          <meta name="csrf-token" content="<%= form_authenticity_token %>">
          <%= javascript_importmap_tags %>
        </head>
        <body>
          <h1>LiveCable Integration Tests</h1>
          <ul>
            <li><a href="/counter">Counter Component Test</a></li>
            <li><a href="/children">Children Components Test</a></li>
            <li><a href="/recursive">Recursive Component Test</a></li>
          </ul>
        </body>
      </html>
    HTML
  end

  def counter; end
  def children; end
  def recursive; end
  def form_test; end
  def error_test; end
  def error_on_subscribe_test; end
  def local_vars; end
  def compound; end
  def plain_erb; end
  def render_component; end
  def loading; end
  def event_test; end

  # Rotates the session's CSRF token the way Devise does on sign-in
  # (clean_up_csrf_token_on_authentication) and answers with the token a page
  # rendered from the new session would carry. Lets a system test leave an
  # open socket behind the session without a full sign-in flow.
  def rotate_csrf
    session[:_csrf_token] = SecureRandom.base64(32)
    render json: { token: form_authenticity_token }
  end
end
