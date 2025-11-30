# frozen_string_literal: true

module LiveCableHelper
  def live_component(name, **options)
    tag.div(
      data: {
        controller: 'live',
        live_defaults_value: options.to_json,
        live_component_value: name,
      },
      'live-ignore' => ''
    )
  end
end
