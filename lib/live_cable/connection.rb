# frozen_string_literal: true

module LiveCable
  class Connection
    attr_reader :session_id

    SHARED_CONTAINER = '_shared'

    def initialize(request)
      @request = request
      @session_id = SecureRandom.uuid
      @containers = {} # @todo Use Hash.new with a proc to make a container / hash
      @components = {}
      @changeset = {}
    end

    def get_component(id)
      components[id]
    end

    def add_component(component)
      component._live_connection = self
      components[component._live_id] = component
    end

    def remove_component(component)
      components.delete(component._live_id)
      containers.delete(component._live_id)
    end

    def get(container_name, component, variable, initial_value)
      containers[container_name] ||= {}
      containers[container_name][variable] ||= process_initial_value(component, variable, initial_value)
    end

    def set(container_name, variable, value)
      dirty(container_name, variable)

      containers[container_name] ||= {}
      containers[container_name][variable] = value
    end

    def receive(component, data)
      check_csrf_token(data)
      reset_changeset

      return unless data['messages'].present?

      data['messages'].each do |message|
        action(component, message)
      end

      broadcast_changeset
    end

    def action(component, data)
      params = parse_params(data)

      if data['_action']
        action = data['_action']&.to_sym

        if action == :_reactive
          return reactive(component, data)
        end

        unless component.class.allowed_actions.include?(action)
          raise LiveCable::Error, "Unauthorized action: #{action}"
        end

        method = component.method(action)

        if method.arity.positive?
          method.call(params)
        else
          method.call
        end
      end
    rescue StandardError => e
      handle_error(component, e)
    end

    def reactive(component, data)
      unless component.all_reactive_variables.include?(data['name'].to_sym)
        raise Error, "Invalid reactive variable: #{data['name']}"
      end

      component.public_send("#{data['name']}=", data['value'])
    rescue StandardError => e
      handle_error(component, e)
    end

    def channel_name
      "live_#{session_id}"
    end

    def dirty(container_name, *variables)
      changeset[container_name] ||= []
      changeset[container_name] += variables
    end

    private

    attr_reader :request

    # @return [Hash<String, Hash>]
    attr_reader :containers

    # @return [Hash<String, Component>]
    attr_reader :components

    # @return [Hash<String, Array<Symbol>>]
    attr_reader :changeset

    def check_csrf_token(data)
      session = request.session
      return unless session[:_csrf_token]

      token = data['_csrf_token']
      unless csrf_checker.valid?(session, token)
        raise LiveCable::Error, 'Invalid CSRF token'
      end
    end

    def csrf_checker
      @csrf_checker ||= LiveCable::CsrfChecker.new(request)
    end

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
      params = data['params'] || ''

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
      # Use a copy of the components since new ones can get added while rendering
      # and causes an issue here.
      components.values.dup.each do |component|
        if changeset[component._live_id]
          component.render_broadcast

          next
        end

        shared_changeset = changeset[SHARED_CONTAINER] || []

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
