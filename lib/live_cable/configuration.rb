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

    # When true, client messages are rejected unless they carry a valid CSRF
    # token. By default (false) the token is only checked when the session
    # already has one, so connections without a session (e.g. token auth) are
    # not blocked. Turn this on to require a token for every message.
    #
    #   LiveCable.configure do |config|
    #     config.require_csrf_token = true
    #   end
    attr_accessor :require_csrf_token

    def initialize
      @verbose_errors = !Rails.env.production?
      @require_csrf_token = false
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
