# frozen_string_literal: true

module LiveCableHelper
  def live_component(component, **, &)
    tag.div(**live_attributes(component, {}, **)) do
      live_component_capture(component, &)
    end
  end

  def live_component_capture(component, &block)
    capture { block.call }
  end

  def with_live_connection(live_connection, &)
    # Another component has already set the connection
    if @_live_connection
      return yield
    end

    @_live_connection = live_connection

    begin
      value = yield
    ensure
      @_live_connection = nil
    end

    value
  end

  def live(component, **options)
    renderable = component
    id = options.delete(:id)

    if renderable.is_a?(String)
      live_id = "#{renderable}/#{id}"

      renderable = if (existing = @_live_connection&.get_component(live_id))
                     existing
                   else
                     LiveCable.instance_from_string(renderable, id)
                   end
    end

    # Add the component with the given state server side
    @_live_connection&.add_component(renderable)
    renderable.defaults = options

    render(renderable)
  end

  def live_attributes(component, defaults = {}, **options)
    options.merge(
      {
        data: {
          controller: "live #{options.dig(:data, :controller)}".rstrip,
          live_defaults_value: options.to_json,
          live_component_value: component.class.component_string,
          live_live_id_value: component._live_id,
        },
        'live-ignore' => '',
      }
    )
  end

  def live_attributes_html(...)
    tag.tag_options(live_attributes(...)).html_safe
  end
end
