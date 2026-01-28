# frozen_string_literal: true

module LiveCableHelper
  # @param [LiveCable::Component] component
  def with_render_context(component, &)
    # Add the current component to the parent context before making a new context
    render_context&.add_component(component)

    # If we had a parent with a live connection, we're connected, so apply defaults now, if not
    # then we apply them to the pre-render container
    component.apply_defaults

    context = LiveCable::RenderContext.new(component, root: context_stack.first)
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
      raise LiveCable::Error, '`live` helper only accepts string component names. Use render(component) directly if ' \
                              'you have a component instance.'
    end

    live_id = "#{component}/#{id}"

    component = render_context&.get_component(live_id) || LiveCable.instance_from_string(component, id)
    component.defaults = defaults

    render(component)
  end

  private

  def context_stack
    @context_stack ||= []
  end

  def render_context
    context_stack.last
  end
end
