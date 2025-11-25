# frozen_string_literal: true

module LiveCable
  module Registry
    class << self
      def register(name, klass)
        components[name] = klass
        names[klass] = name
      end

      def find(name)
        components[name]
      end

      def find_name(klass)
        names[klass]
      end

      def reset!
        @components = {}
        @names = {}
      end

      private

      def components
        @components ||= {}
      end

      def names
        @names ||= {}
      end
    end
  end
end
