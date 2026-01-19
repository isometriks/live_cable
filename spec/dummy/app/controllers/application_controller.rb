# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include LiveCableHelper

  # Use a simple secret for testing
  before_action :set_csrf_token

  private

  def set_csrf_token
    session[:_csrf_token] ||= SecureRandom.base64(32)
  end
end
