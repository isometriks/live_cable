# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  # Private so ActionCable does not expose it as an action the client can call
  delegate :live_connection, to: :connection, private: true

  before_subscribe :ensure_live_connection

  # Each entry point below runs as its own job on ActionCable's worker pool,
  # so each holds the connection's lock for the whole of its work - see
  # LiveCable::Connection#synchronize.

  # @component is assigned as soon as the component is known, so a failure
  # later in here still leaves it for unsubscribed to clean up
  def subscribed
    live_connection.synchronize do
      live_id = "#{params[:component]}/#{params[:id]}"

      @component = live_connection.get_component(live_id)

      # The client replaces a subscription, to send new defaults, by
      # unsubscribing first, but ActionCable may run the two out of order
      if component&.subscribed?
        component.disconnect
        @component = nil
      end

      rendered = component.present?

      unless component
        @component = LiveCable.instance_from_string(params[:component], params[:id])
        live_connection.add_component(component)
        # Defaults round-trip through the client, so verify the signed blob and
        # bind it to this live_id before trusting it - otherwise a tampered value
        # could set non-writable reactive variables at subscribe time.
        component.defaults = LiveCable::DefaultsSigner.verify(params[:defaults], live_id)
        component.apply_defaults
      end

      component.connect(self)

      if rendered
        component.broadcast_subscribe
      else
        component.broadcast_render
      end
    rescue StandardError => error
      live_connection.handle_error(component, error, channel: self)
    end
  end

  # Every batch must be answered - the client holds its loading state until a
  # _refresh, _ack or _error arrives - so nothing raised here may escape to
  # ActionCable, which would only log it and leave the client hanging.
  def receive(data)
    live_connection.synchronize do
      raise LiveCable::Error, 'No component was built, so this subscription cannot receive messages' unless component

      live_connection.receive(component, data)
    rescue StandardError => error
      live_connection.handle_error(component, error, channel: self)
    end
  end

  def unsubscribed
    return unless component

    live_connection.synchronize do
      # Already disconnected by a newer subscription for the same component
      component.disconnect if live_connection.get_component(component.live_id).equal?(component)
      @component = nil
    end
  end

  # Exposes #transmit, which ActionCable keeps private to the channel.
  def broadcast(data)
    transmit(data)
  end

  private

  # @return [LiveCable::Component, nil]
  attr_reader :component

  def ensure_live_connection
    return if live_connection

    raise LiveCable::Error, "#{connection.class.name} still declares identified_by :live_connection, " \
                            'which shadows the live_connection LiveCable attaches and leaves it nil. ' \
                            'Remove that line and the connect override that set it; see the 0.3.0 ' \
                            'upgrade notes.'
  end
end
