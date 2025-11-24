class LiveChannel < ActionCable::Channel::Base
  def subscribed
    # @todo - Add a stream for each component
    stream_from(live_connection.channel_name)

    klass = params[:component].camelize.constantize

    unless klass < LiveCable::Component
      raise "Components must extend LiveCable::Component"
    end

    instance = klass.new
    instance._live_id = params[:_live_id]
    instance._live_connection = live_connection
    instance._defaults = params[:defaults]

    live_connection.add_component(instance)

    instance.broadcast({ _status: "subscribed" })
    instance.render_broadcast
  end

  def receive(data)
    live_connection.receive(data)
  end

  def reactive(data)
    live_connection.reactive(data)
  end
end
