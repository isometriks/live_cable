# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  def subscribed
    klass = params[:component].camelize.constantize

    unless klass < LiveCable::Component
      raise 'Components must extend LiveCable::Component'
    end

    instance = klass.new
    instance._live_connection = live_connection
    instance._defaults = params[:defaults]

    stream_from(instance.channel_name)

    live_connection.add_component(instance)

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
end
