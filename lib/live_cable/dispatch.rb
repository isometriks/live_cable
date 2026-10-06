# frozen_string_literal: true

module LiveCable
  # A client message on its way to a component: an action call or a
  # live-reactive write. Exposed as Component#current_dispatch while the
  # component's before_dispatch callbacks, and the action or write, run.
  class Dispatch
    # @return [Symbol] :action or :reactive
    attr_reader :kind

    # @return [Symbol] The action or reactive variable name
    attr_reader :name

    # @return [Object] The value a reactive write assigns; nil for an action
    attr_reader :value

    # @param data [Hash] One message from the client's batch
    # @return [LiveCable::Dispatch]
    def self.from_message(data)
      if data['_action'].to_s == '_reactive'
        new(:reactive, data['name'], value: data['value'])
      else
        new(:action, data['_action'], query: data['params'])
      end
    end

    def initialize(kind, name, value: nil, query: nil)
      @kind = kind
      @name = name.to_s.to_sym
      @value = value
      @query = query
    end

    def action?
      kind == :action
    end

    def reactive?
      kind == :reactive
    end

    # @return [ActionController::Parameters, nil] The action's params; nil for
    #   a reactive write
    def params
      return unless action?

      @params ||= ActionController::Parameters.new(
        ActionDispatch::ParamBuilder.from_pairs(
          ActionDispatch::QueryParser.each_pair(@query || '')
        )
      )
    end
  end
end
