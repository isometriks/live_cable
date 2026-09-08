# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  # Private so ActionCable does not expose it as an action the client can call
  delegate :live_connection, to: :connection, private: true

  def subscribed
    instance = nil

    # Build live_id from component and id params
    live_id = "#{params[:component]}/#{params[:id]}"

    instance = live_connection.get_component(live_id)
    rendered = instance.present?

    unless instance
      instance = LiveCable.instance_from_string(params[:component], params[:id])
      live_connection.add_component(instance)
      instance.defaults = params[:defaults]
      instance.apply_defaults
    end

    instance.connect(self)

    if rendered
      instance.broadcast_subscribe
    else
      instance.broadcast_render
    end

    @component = instance
  rescue StandardError => error
    live_connection.handle_error(instance, error, channel: self)
  end

  # Every batch must be answered - the client holds its loading state until a
  # _refresh, _ack or _error arrives - so nothing raised here may escape to
  # ActionCable, which would only log it and leave the client hanging.
  def receive(data)
    raise LiveCable::Error, 'Component failed to subscribe, so it cannot receive messages' unless component

    live_connection.receive(component, data)
  rescue StandardError => error
    live_connection.handle_error(component, error, channel: self)
  end

  def unsubscribed
    return unless component

    component.disconnect
    @component = nil
  end

  # Exposes #transmit, which ActionCable keeps private to the channel.
  def broadcast(data)
    transmit(data)
  end

  private

  # @return [LiveCable::Component, nil]
  attr_reader :component
end
