# frozen_string_literal: true

module LiveCable
  class Component
    include ActiveSupport::Rescuable

    class_attribute :is_compound, default: false
    class_attribute :shared_variables, default: []
    class_attribute :reactive_variables, default: []
    class_attribute :shared_reactive_variables, default: []

    class << self
      def compound
        self.is_compound = true
      end

      def actions(*names)
        @allowed_actions = names.map!(&:to_sym).freeze
      end

      def allowed_actions
        @allowed_actions || []
      end

      def reactive(variable, initial_value = nil, shared: false)
        list_name = shared ? :shared_reactive_variables : :reactive_variables
        current   = (public_send(list_name) || []).dup
        public_send("#{list_name}=", current << variable)

        if shared
          shared_reactive_variables << variable
        else
          reactive_variables << variable
        end

        create_reactive_variables(variable, initial_value, shared: shared)
      end

      def shared(variable, initial_value = nil)
        self.shared_variables = (shared_variables || []).dup << variable

        create_reactive_variables(variable, initial_value, shared: true)
      end

      def component_string
        name.underscore.delete_prefix('live/')
      end

      def component_id(id)
        "#{component_string}/#{id}"
      end

      private

      def create_reactive_variables(variable, initial_value, shared: false)
        define_method(variable) do
          container_name = shared ? Connection::SHARED_CONTAINER : live_id

          if live_connection
            return live_connection.get(container_name, self, variable, initial_value)
          elsif prerender_container.key?(variable)
            return prerender_container[variable]
          end

          return if initial_value.nil?

          if initial_value.arity.positive?
            initial_value.call(self)
          else
            initial_value.call
          end
        end

        define_method("#{variable}=") do |value|
          container_name = shared ? Connection::SHARED_CONTAINER : live_id

          if live_connection
            live_connection.set(container_name, variable, value)
          else
            prerender_container[variable] = value
          end
        end
      end
    end

    attr_reader :rendered, :defaults

    def initialize(id)
      @live_id = self.class.component_id(id)
      @rendered = false
      @subscribed = false
    end

    def broadcast(data)
      ActionCable.server.broadcast(channel_name, data)
    end

    def render
      @rendered = true
      ApplicationController.renderer.render(self, layout: false)
    end

    def broadcast_subscribe
      broadcast({ _status: 'subscribed', id: live_id })
      @subscribed = true
    end

    def broadcast_destroy
      broadcast({ _status: 'destroy' })
      @subscribed = false
    end

    def render_broadcast
      before_render
      broadcast(_refresh: render)
      after_render
    end

    def status
      subscribed? ? 'subscribed' : 'disconnected'
    end

    def subscribed?
      @subscribed
    end

    def destroy
      broadcast_destroy
    end

    # Lifecycle hooks - override in subclasses to add custom behavior
    def connected
      # Called when the component is first subscribed to the channel
    end

    def disconnected
      # Called when the component is unsubscribed from the channel
    end

    def before_render
      # Called before each render/broadcast
    end

    def after_render
      # Called after each render/broadcast
    end

    attr_accessor :live_connection

    def live_id
      @live_id ||= SecureRandom.uuid
    end

    def channel_name
      "#{live_connection.channel_name}/#{live_id}"
    end

    def to_partial_path
      base = self.class.name.underscore

      if self.class.is_compound
        "#{base}/#{template_state}"
      else
        base
      end
    end

    def template_state
      'component'
    end

    def render_in(view_context)
      # @TODO: Figure out where to put this
      ActionView::Base.annotate_rendered_view_with_filenames = false

      view, render_context = view_context.with_render_context(self) do
        view_context.render(template: to_partial_path, layout: false, locals:)
      end

      if @previous_render_context
        destroyed = @previous_render_context.children - render_context.children

        destroyed.each(&:destroy)
      end

      @previous_render_context = render_context

      view
    end

    def all_reactive_variables
      self.class.reactive_variables + self.class.shared_reactive_variables
    end

    def dirty(*variables)
      variables.each do |variable|
        unless all_reactive_variables.include?(variable)
          raise Error, "Invalid reactive variable: #{variable}"
        end

        container_name = self.class.reactive_variables.include?(variable) ? live_id : Connection::SHARED_CONTAINER

        live_connection.dirty(container_name, variable)
      end
    end

    def defaults=(defaults)
      # Don't set defaults more than once
      return if defined?(@defaults)

      @defaults = (defaults || {}).symbolize_keys
      keys = all_reactive_variables & @defaults.keys

      keys.each do |key|
        public_send("#{key}=", @defaults[key])
      end
    end

    private

    def prerender_container
      @prerender_container ||= {}
    end

    def locals
      (all_reactive_variables + (self.class.shared_variables || [])).
        to_h { |v| [v, public_send(v)] }.
        merge(
          component: self
        )
    end
  end
end
