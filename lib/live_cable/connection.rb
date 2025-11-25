# frozen_string_literal: true

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
      @containers[container_name][variable] ||= process_initial_value(component, variable, initial_value)
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

    def receive(component, data)
      reset_changeset

      params = parse_params(data)

      if data['_action']
        component.public_send(data['_action'], params)
        broadcast_changeset
      end
    rescue StandardError => e
      handle_error(component, e)
    end

    def reactive(component, data)
      reset_changeset

      unless component.all_reactive_variables.include?(data['name'].to_sym)
        raise Error, "Invalid reactive variable: #{data['name']}"
      end

      component.public_send("#{data['name']}=", data['value'])
      broadcast_changeset
    rescue StandardError => e
      handle_error(component, e)
    end

    def channel_name
      "live_#{session_id}"
    end

    def dirty(container_name, *variables)
      @changeset[container_name] ||= []
      @changeset[container_name] += variables
    end

    private

    def process_initial_value(component, variable, initial_value)
      case initial_value
      when nil
        nil
      when Proc
        args = []
        args << component if initial_value.arity.positive?

        initial_value.call(*args)
      else
        raise Error, "Initial value for \":#{variable}\" must be a proc or nil"
      end
    rescue StandardError => e
      handle_error(component, e)
    end

    def parse_params(data)
      params = data['params'] || {}

      ActionController::Parameters.new(
        ActionDispatch::ParamBuilder.from_pairs(
          ActionDispatch::QueryParser.each_pair(params)
        )
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

    def handle_error(component, error)
      html = <<~HTML
        <details>
          <summary style="color: #f00; cursor: pointer">
            <strong>#{component.class.name}</strong> - #{error.class.name}: #{error.message}
          </summary>
          <small>
            <ol>
              #{error.backtrace&.map { "<li>#{it}</li>" }&.join("\n")}
            </ol>
          </small>
        </details>
      HTML

      component.broadcast(_refresh: html)

      raise(error)
    end
  end
end
