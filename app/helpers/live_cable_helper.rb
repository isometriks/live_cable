# frozen_string_literal: true

module LiveCableHelper
  def live_component(**, &block)
    unless render_context&.component
      raise LiveCable::Error, 'live_component must be called while rendering a live component'
    end

    # We don't need to add defaults in the HTML if we're already connected
    component = render_context.component
    defaults = component.live_connection ? {} : component.defaults

    tag.div(**live_attributes(component, defaults, **)) do
      capture { block.call }
    end
  end

  # @param [LiveCable::Component] component
  def with_render_context(component, &)
    # Add the current component to the parent context before making a new context
    render_context&.add_component(component)

    # If we had a parent with a live connection, we're connected, so apply defaults now, if not
    # then we apply them to the pre-render container
    component.apply_defaults

    context = LiveCable::RenderContext.new(component)
    context_stack.push(context)

    begin
      value = yield
    ensure
      context_stack.pop
    end

    [value, context]
  end

  def live(component, **options)
    renderable = component
    id = options.delete(:id)

    if renderable.is_a?(String)
      live_id = "#{renderable}/#{id}"

      renderable = if (existing = render_context&.get_component(live_id))
                     existing
                   else
                     LiveCable.instance_from_string(renderable, id)
                   end
    end

    renderable.defaults = options

    render(renderable)
  end

  def live_attributes(component, defaults = {}, **options)
    options.merge(
      {
        data: {
          controller: "live #{options.with_indifferent_access.dig(:data, :controller)}".rstrip,
          live_defaults_value: defaults.to_json,
          live_component_value: component.class.component_string,
          live_id_value: component.id,
          live_status_value: component.status,
        },
      }
    )
  end

  # Helper to generate Stimulus action attributes for calling LiveCable component actions.
  #
  # Simplifies the Stimulus HTML syntax for triggering component actions by generating
  # the necessary data attributes in a single call.
  #
  # @param action [String, Symbol] The name of the component action to call
  # @param event [String, Symbol, nil] The DOM event to bind to (optional)
  #   If nil, uses Stimulus default event for the element type (click for buttons, submit for forms, etc.)
  #
  # @return [ActiveSupport::SafeBuffer] HTML-safe string with data attributes
  #
  # @example Using default event (click on button, submit on form)
  #   <button <%= live_action(:save) %>>Save</button>
  #   # Generates: data-action='live#call' data-live-action-param='save'
  #
  # @example Specifying a custom event
  #   <input <%= live_action(:search, :input) %> />
  #   # Generates: data-action='input->live#call' data-live-action-param='search'
  #
  # @note The action must be defined in your component class using the `actions` macro
  def live_action(action, event = nil)
    tag.attributes(
      data: {
        action: "#{event && "#{event}->"}live#call",
        live_action_param: action,
      }
    )
  end

  private

  def context_stack
    @context_stack ||= []
  end

  def render_context
    context_stack.last
  end
end
