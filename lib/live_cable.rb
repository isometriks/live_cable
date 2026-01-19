# frozen_string_literal: true

require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.setup

# Require helpers explicitly (Zeitwerk doesn't autoload app/ directory)
require_relative '../app/helpers/live_cable_helper'

module LiveCable
  def self.instance_from_string(string, id)
    klass = Live
    klass_string = string.camelize

    begin
      klass_string.split('::').each do |part|
        unless klass.const_defined?(part)
          raise LiveCable::Error,
            "Component Live::#{klass_string} not found, make sure it is located in the Live:: module"
        end

        klass = klass.const_get(part)
      end
    rescue NameError
      raise LiveCable::Error, "Invalid component name \"#{string}\" - Live::#{klass_string} not found"
    end

    klass = "Live::#{klass_string}".safe_constantize

    unless klass < LiveCable::Component
      raise LiveCable::Error, 'Components must extend LiveCable::Component'
    end

    klass.new(id)
  end
end

module Live
  # For components to live in
end

require 'live_cable/engine' if defined?(Rails::Engine)
