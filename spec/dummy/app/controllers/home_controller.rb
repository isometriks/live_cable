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
          </ul>
        </body>
      </html>
    HTML
  end

  def counter; end
  def children; end
end
