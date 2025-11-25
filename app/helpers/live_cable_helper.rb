# frozen_string_literal: true

module LiveCableHelper
  def live_component(component, **options)
    name = if component.is_a?(Class)
             LiveCable::Registry.find_name(component)
           else
             component
           end

    tag.div(
      data: {
        controller: 'live',
        live_defaults_value: options.to_json,
        live_component_value: name,
      }
    )
  end
end
