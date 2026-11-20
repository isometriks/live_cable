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

    # When true (the default), a control block in a .live.erb template - an
    # if, unless, case or loop - compiles to a structure of static markup and
    # values, so a change inside it sends only the values that changed rather
    # than the block's whole HTML. Set to false to send each block as one HTML
    # string, as LiveCable did before. Read when templates compile, so set it
    # in an initializer.
    attr_accessor :structured_blocks

    # When true, collection streams check what can only be seen at render
    # time: that a row whose element sets its own id renders its key there,
    # and that a component's template renders every stream it declares.
    # Defaults to true outside of production.
    attr_accessor :verify_stream_items

    def initialize
      @verbose_errors = !Rails.env.production?
      @structured_blocks = true
      @verify_stream_items = !Rails.env.production?
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
