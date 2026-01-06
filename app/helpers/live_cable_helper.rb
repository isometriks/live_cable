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

  def live(component, id:, **defaults)
    unless component.is_a?(String)
      raise LiveCable::Error, 'live helper only accepts string component names. Use render directly if you have a ' \
                              'component instance.'
    end

    live_id = "#{component}/#{id}"

    component = render_context&.get_component(live_id) || LiveCable.instance_from_string(component, id)
    component.defaults = defaults

    render(component)
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
  # @param params [Hash] Additional parameters to pass to the action
  #   Each key-value pair will be converted to a data-live-{key}-param attribute
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
  # @example Passing additional parameters
  #   <button <%= live_action(:submit, user_id: current_user.id) %>>Submit</button>
  #   # Generates: data-action='live#call' data-live-action-param='submit' data-live-user-id-param='123'
  #
  # @note The action must be defined in your component class using the `actions` macro
  def live_action(action, event = nil, **params)
    data_attrs = {
      action: "#{event && "#{event}->"}live#call",
      live_action_param: action,
    }

    # Convert additional params to data-live-{key}-param attributes
    params.each do |key, value|
      data_attrs[:"live_#{key.to_s.underscore}_param"] = value
    end

    tag.attributes(data: data_attrs)
  end

  # Returns a hash of data attributes for LiveCable form submissions.
  #
  # Use this with Rails form helpers like form_with or form_for to integrate
  # LiveCable actions with Rails forms.
  #
  # @param action [String, Symbol] The name of the component action to call
  # @param event [String, Symbol, nil] The DOM event to bind to (optional, default: :submit)
  # @param prevent [Boolean] Whether to prevent default form submission (default: true)
  # @param debounce [Integer, nil] Debounce delay in milliseconds (optional)
  #
  # @return [Hash] Hash with :data key containing the Stimulus data attributes
  #
  # @example With form_with
  #   <%= form_with(model: @user, **live_form_attr(:save)) do |form| %>
  #     <%= form.text_field :name %>
  #     <%= form.submit "Save" %>
  #   <% end %>
  #
  # @example With custom event
  #   <%= form_with(model: @user, **live_form_attr(:filter, :change, debounce: 500)) do |form| %>
  #     <%= form.select :category, options %>
  #   <% end %>
  #
  # @note The action must be defined in your component class using the `actions` macro
  def live_form_attr(action, event = nil, prevent: true, debounce: nil)
    event ||= :submit
    action_value = "#{event}->live#form"
    action_value += ':prevent' if prevent

    data_attrs = {
      action: action_value,
      live_action_param: action,
    }

    data_attrs[:live_debounce_param] = debounce if debounce

    { data: data_attrs }
  end

  # Helper to generate Stimulus form attributes for submitting forms to LiveCable component actions.
  #
  # Simplifies the Stimulus HTML syntax for form submissions by generating the necessary
  # data attributes in a single call. For use with Rails form helpers, see live_form_attr.
  #
  # @param action [String, Symbol] The name of the component action to call
  # @param event [String, Symbol, nil] The DOM event to bind to (optional, default: :submit)
  # @param prevent [Boolean] Whether to prevent default form submission (default: true)
  # @param debounce [Integer, nil] Debounce delay in milliseconds (optional)
  #
  # @return [ActiveSupport::SafeBuffer] HTML-safe string with data attributes
  #
  # @example Basic form submission
  #   <form <%= live_form(:save) %>>
  #     <input type="text" name="title">
  #     <button type="submit">Save</button>
  #   </form>
  #   # Generates: data-action='submit->live#form:prevent' data-live-action-param='save'
  #
  # @example Without preventing default
  #   <form <%= live_form(:search, prevent: false) %>>
  #     ...
  #   </form>
  #   # Generates: data-action='submit->live#form' data-live-action-param='search'
  #
  # @example With custom event and debounce
  #   <form <%= live_form(:filter, :change, debounce: 500) %>>
  #     <select name="category">...</select>
  #   </form>
  #   # Generates:
  #   #   data-action='change->live#form:prevent'
  #   #   data-live-action-param='filter'
  #   #   data-live-debounce-param='500'
  #
  # @note The action must be defined in your component class using the `actions` macro
  def live_form(action, event = nil, prevent: true, debounce: nil)
    tag.attributes(live_form_attr(action, event, prevent: prevent, debounce: debounce)[:data])
  end

  private

  def context_stack
    @context_stack ||= []
  end

  def render_context
    context_stack.last
  end
end
