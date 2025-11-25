# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  def subscribed
    klass_string = params[:component].camelize
    klass = Live

    begin
      klass_string.split('::').each do |part|
        unless klass.const_defined?(part)
          raise Error, "Component Live::#{klass_string} not found, make sure it is located in the Live:: module"
        end

        klass = klass.const_get(part)
      end
    rescue NameError => error
      raise LiveCable::Error, "Invalid component name"
    end

    klass = "Live::#{klass_string}".safe_constantize

    unless klass < LiveCable::Component
      raise 'Components must extend LiveCable::Component'
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
