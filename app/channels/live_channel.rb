# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  def subscribed
    klass = LiveCable::Registry.find(params[:component])

    unless klass
      raise "Unknown component: #{params[:component]}"
    end

    instance = klass.new
    instance._live_connection = live_connection
    instance._defaults = params[:defaults]

    stream_from(instance.channel_name)

    live_connection.add_component(instance)

    instance.connected
    instance.broadcast_subscribe
    instance.render_broadcast

    @component = instance
  end

  def receive(data)
    live_connection.receive(@component, data)
  end

  def reactive(data)
    live_connection.reactive(@component, data)
  end

  def unsubscribed
    @component&.disconnected
    live_connection.remove_component(@component) if @component
    stop_all_streams
    @component&._live_connection = nil
    @component = nil
  end
end
