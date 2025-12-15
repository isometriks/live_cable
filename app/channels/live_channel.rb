# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  def subscribed
    instance = params[:live_id].present? && live_connection.get_component(params[:live_id])
    rendered = instance.present?

    unless instance
      instance = LiveCable.instance_from_string(params[:component], params[:live_id])
      live_connection.add_component(instance)
      instance.defaults = params[:defaults]
    end

    stream_from(instance.channel_name)

    instance.connected
    instance.broadcast_subscribe
    instance.render_broadcast unless rendered

    @component = instance
  end

  def receive(data)
    live_connection.receive(@component, data)
  end

  def unsubscribed
    @component&.disconnected
    live_connection.remove_component(@component) if @component
    stop_all_streams
    @component&._live_connection = nil
    @component = nil
  end
end
