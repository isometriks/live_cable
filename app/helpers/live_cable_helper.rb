module LiveCableHelper
  def live_component(name, **options)
    component = name.camelize.constantize
    id = SecureRandom.uuid
    session_id = request.request_id

    tag.div(
      data: {
        controller: "live",
        live_defaults_value: options.to_json,
        live_id_value: id,
        live_session_id_value: session_id,
        live_component_value: name,
      }
    )
  end
end
