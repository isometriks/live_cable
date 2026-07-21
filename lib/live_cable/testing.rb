# frozen_string_literal: true

module LiveCable
  # Test helpers for unit testing LiveCable components without a browser
  # or a real ActionCable connection.
  #
  # Include the module in your specs and use +live_mount+ to mount a
  # component. Actions and reactive updates are dispatched through the real
  # message pipeline, so action whitelisting, parameter parsing, writability
  # checks, change tracking, and re-rendering are all exercised exactly as
  # they are in production.
  #
  # @example RSpec
  #   RSpec.describe Live::Counter do
  #     include LiveCable::Testing
  #
  #     it 'increments by the step size' do
  #       counter = live_mount('counter', step: 2)
  #
  #       counter.perform(:increment)
  #
  #       expect(counter.count).to eq(2)
  #       expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '2')
  #     end
  #   end
  module Testing
    # Mount a component for testing.
    #
    # Mirrors what +LiveChannel#subscribed+ does in production: the component
    # is registered on a connection, defaults are applied, lifecycle connect
    # callbacks run, and the initial render is broadcast.
    #
    # @param component [String, Class, LiveCable::Component] Component name
    #   (e.g. 'counter' or 'chat/room'), component class, or instance
    # @param id [String] The component id (defaults to 'test')
    # @param connection [LiveCable::Connection, nil] Mount onto an existing
    #   test connection (from another mounted component) to share state
    #   between components
    # @param identifiers [Hash] ActionCable connection identifiers made
    #   available to the component (e.g. current_user: user)
    # @param raise_errors [Boolean] Raise errors from actions and rendering
    #   instead of broadcasting an _error like production does (default true)
    # @param defaults [Hash] Default values for reactive variables
    # @return [LiveCable::Testing::TestComponent]
    def live_mount(component, id: 'test', connection: nil, identifiers: {}, raise_errors: true, **defaults)
      connection ||= build_test_connection(raise_errors:)

      instance =
        case component
        when LiveCable::Component then component
        when Class then component.new(id)
        else LiveCable.instance_from_string(component.to_s, id)
        end

      test_component = TestComponent.new(instance, connection, TestChannel.new(identifiers))

      connection.add_component(instance)
      instance.defaults = defaults
      instance.apply_defaults
      instance.connect(test_component.channel)
      instance.broadcast_render

      test_component
    end

    private

    def build_test_connection(raise_errors:)
      require 'action_dispatch/testing/test_request'

      # An empty session skips the CSRF check, like a session-less request
      request = ActionDispatch::TestRequest.create('rack.session' => {})
      connection = LiveCable::Connection.new(request)

      if raise_errors
        def connection.handle_error(_component, error)
          raise error
        end
      end

      connection
    end
  end
end
