# frozen_string_literal: true

module LiveCable
  extend ActiveSupport::Autoload

  autoload :Error
  autoload :Component
  autoload :Connection
  autoload :Container
  autoload :CsrfChecker
  autoload :Delegator
  autoload :ModelObserver
  autoload :Observer
  autoload :ObserverTracking
  autoload :RenderContext

  def self.instance_from_string(string, id)
    klass = Live
    klass_string = string.camelize

    begin
      klass_string.split('::').each do |part|
        unless klass.const_defined?(part)
          raise Error, "Component Live::#{klass_string} not found, make sure it is located in the Live:: module"
        end

        klass = klass.const_get(part)
      end
    rescue NameError
      raise LiveCable::Error, "Invalid component name \"#{string}\" - Live::#{klass_string} not found"
    end

    klass = "Live::#{klass_string}".safe_constantize

    unless klass < LiveCable::Component
      raise 'Components must extend LiveCable::Component'
    end

    klass.new(id)
  end
end

module Live
  # For components to live in
end

require 'live_cable/engine' if defined?(Rails::Engine)
