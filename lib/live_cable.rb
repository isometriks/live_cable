module LiveCable
  extend ActiveSupport::Autoload

  autoload :Component
  autoload :Connection
  autoload :Container
end

require "live_cable/engine" if defined?(Rails::Engine)
