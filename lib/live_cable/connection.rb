module LiveCable
  class Connection
    attr_reader :session_id

    SHARED_CONTAINER = '_shared'

    def initialize
      @session_id = SecureRandom.uuid
      @containers = {} # @todo Use Hash.new with a proc to make a container / hash
      @components = {}
      @changeset = {}
    end

    def to_gid_param
      @session_id
    end

    def add_component(component)
      @components[component._live_id] = component
    end

    def get(container_name, component, variable, initial_value)
      @containers[container_name] ||= {}
      @containers[container_name][variable] ||= process_initial_value(component, initial_value)
    end

    def set(container_name, variable, value)
      has_value = @containers[container_name]&.key?(variable)
      current_value = @containers.dig(container_name, variable)

      if !has_value || current_value != value
        dirty(container_name, variable)
      end

      @containers[container_name] ||= {}
      @containers[container_name][variable] = value
    end

    def broadcast(data)
      ActionCable.server.broadcast(channel_name, data)
    end

    def receive(data)
      reset_changeset
      component = component_for_data(data)

      return unless component

      params = parse_params(data)

      if data["_action"]
        component.public_send(data["_action"], params)
        broadcast_changeset
      end
    end

    def reactive(data)
      reset_changeset
      component = component_for_data(data)

      return unless component

      unless component.all_reactive_variables.include?(data["name"].to_sym)
        raise "Invalid reactive variable: #{data["name"]}"
      end

      component.public_send("#{data["name"]}=", data["value"])
      broadcast_changeset
    end

    def channel_name
      "live_#{session_id}"
    end

    def dirty(container_name, *variables)
      @changeset[container_name] ||= []
      @changeset[container_name] += variables
    end

    private

    def process_initial_value(component, initial_value)
      case initial_value
      when nil
        nil
      when Proc
        args = []
        args << component if initial_value.arity.positive?

        initial_value.call(*args)
      else
        raise "Initial values must be a proc or nil"
      end
    end

    def parse_params(data)
      params = data["params"] || {}

      ActionController::Parameters.new(
        ActionDispatch::ParamBuilder.from_pairs(
          ActionDispatch::QueryParser.each_pair(params),
        ),
      )
    end

    def reset_changeset
      @changeset = {}
    end

    def broadcast_changeset
      @components.each_value do |component|
        if @changeset[component._live_id]
          component.render_broadcast

          next
        end

        shared_changeset = @changeset[SHARED_CONTAINER] || []

        if (component.shared_reactive_variables || []).intersect?(shared_changeset)
          component.render_broadcast
        end
      end
    end

    def component_for_data(data)
      return unless data['_live_id']

      @components[data['_live_id']]
    end
  end
end
