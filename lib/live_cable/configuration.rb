# frozen_string_literal: true

module LiveCable
  class Configuration
    # When true, error broadcasts include the full backtrace.
    # Defaults to true outside of production so developers see stack traces,
    # and false in production to avoid leaking internals to the client.
    # Override in an initializer:
    #
    #   LiveCable.configure do |config|
    #     config.verbose_errors = false
    #   end
    attr_accessor :verbose_errors

    def initialize
      @verbose_errors = !Rails.env.production?
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end
