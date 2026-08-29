# frozen_string_literal: true

require 'logger'
require 'set'
require 'zeitwerk'
require 'herb'

loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/live.rb")
loader.setup

require_relative 'live_cable/configuration'

# Require helpers explicitly (Zeitwerk doesn't autoload app/ directory)
require_relative '../app/helpers/live_cable_helper'

# Namespace for user components (e.g. Live::Chat); lives outside the gem's
# own LiveCable namespace, so it's ignored by the gem loader above and
# required explicitly instead.
require_relative 'live'

module LiveCable
  @warn_mutex = Mutex.new
  @warned_messages = Set.new

  # Log a warning through the Rails logger at most once per process for a
  # given message. Used for performance and configuration hints (e.g. a
  # component rendered without a .live.erb template) that would otherwise
  # repeat on every render and flood the log.
  def self.warn_once(message)
    @warn_mutex.synchronize do
      return unless @warned_messages.add?(message)
    end

    logger.warn(message)
  end

  # @return [Logger]
  def self.logger
    if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      Rails.logger
    else
      @fallback_logger ||= Logger.new($stderr)
    end
  end

  def self.instance_from_string(string, id)
    klass = Live
    klass_string = string.camelize

    begin
      klass_string.split('::').each do |part|
        # inherit: false so component names that collide with a top-level
        # constant (e.g. "string" -> ::String) don't resolve through Object's
        # ancestry and slip past this guard, only to blow up later with a
        # confusing NameError instead of this friendly message.
        unless klass.const_defined?(part, false)
          raise LiveCable::Error,
            "Component Live::#{klass_string} not found, make sure it is located in the Live:: module"
        end

        klass = klass.const_get(part, false)
      end
    rescue NameError
      raise LiveCable::Error, "Invalid component name \"#{string}\" - Live::#{klass_string} not found"
    end

    klass = "Live::#{klass_string}".safe_constantize

    unless klass && klass < LiveCable::Component
      raise LiveCable::Error, 'Components must extend LiveCable::Component'
    end

    klass.new(id)
  end
end

require 'live_cable/engine' if defined?(Rails::Engine)
