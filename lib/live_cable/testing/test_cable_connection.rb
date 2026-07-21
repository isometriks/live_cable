# frozen_string_literal: true

module LiveCable
  module Testing
    # Stand-in for an ActionCable connection exposing identified_by values
    # (e.g. current_user) to components and their templates.
    class TestCableConnection
      # @return [Set<Symbol>]
      attr_reader :identifiers

      def initialize(identifiers = {})
        identifiers = identifiers.symbolize_keys
        @identifiers = identifiers.keys.to_set

        identifiers.each do |name, value|
          define_singleton_method(name) { value }
        end
      end
    end
  end
end
