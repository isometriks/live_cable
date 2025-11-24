module LiveCable
  class Component
    class_attribute :reactive_variables
    class_attribute :shared_reactive_variables

    def self.reactive(variable, initial_value = nil, shared: false)
      self.reactive_variables ||= []
      self.shared_reactive_variables ||= []

      if shared
        self.shared_reactive_variables << variable
      else
        self.reactive_variables << variable
      end

      define_method(variable) do
        container_name = shared ? Connection::SHARED_CONTAINER : _live_id

        if _live_connection
          _live_connection.get(container_name, variable, initial_value)
        else
          initial_value
        end
      end

      define_method("#{variable}=") do |value|
        container_name = shared ? Connection::SHARED_CONTAINER : _live_id

        _live_connection.set(container_name, variable, value)
      end
    end

    def broadcast(data)
      _live_connection.broadcast(data.merge('_id' => _live_id))
    end

    def render
      ActionController::Base.render(self)
    end

    def render_broadcast
      broadcast('_refresh': render)
    end

    def _defaults=(defaults)
      defaults = (defaults || {}).symbolize_keys
      keys = all_reactive_variables & defaults.keys

      keys.each do |key|
        public_send("#{key}=", defaults[key])
      end
    end

    def _live_connection=(connection)
      @_live_connection = connection
    end

    def _live_id=(_live_id)
      @_live_id = _live_id
    end

    def _live_id
      @_live_id
    end

    def to_partial_path
      "live/#{self.class.name.underscore}/#{template_state}"
    end

    def template_state
      "component"
    end

    def render_in(view_context)
      view_context.render(partial: to_partial_path, locals:)
    end

    def all_reactive_variables
      self.class.reactive_variables + self.class.shared_reactive_variables
    end

    def dirty(*variables)
      variables.each do |variable|
        unless all_reactive_variables.include?(variable)
          raise "Invalid reactive variable: #{variable}"
        end

        container_name = self.class.reactive_variables.include?(variable) ? _live_id : Connection::SHARED_CONTAINER

        _live_connection.dirty(container_name, variable)
      end
    end

    private

    def locals
      all_reactive_variables.
        map { |v| [v, public_send(v)] }.
        to_h
    end

    attr_reader :_live_connection
  end
end
