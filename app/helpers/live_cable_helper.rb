# frozen_string_literal: true

module LiveCableHelper
  def live_component(component, **, &block)
    tag.div(**live_attributes(component, component.defaults, **)) do
      capture { block.call }
    end
  end

  # @param [LiveCable::Component] component
  def with_render_context(component, &)
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

    # @todo Move to live_component so direct renders work too, we would need to assign the options
    #       again when a connection is assigned so it no loner uses the local container
    render_context&.add_component(renderable)

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
          live_live_id_value: component.live_id,
          live_status_value: component.status,
        },
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
