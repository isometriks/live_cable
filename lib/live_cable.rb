# frozen_string_literal: true

module LiveCable
  extend ActiveSupport::Autoload

  autoload :Error
  autoload :Component
  autoload :Connection
  autoload :Container
  autoload :CsrfChecker
end

module Live
  # For components to live in
end

require 'live_cable/engine' if defined?(Rails::Engine)
