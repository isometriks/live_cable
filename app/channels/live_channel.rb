# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
  def subscribed
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

    stream_from(instance.channel_name)

    instance.channel = self
    instance.connected # @todo - Should this be called multiple times?
    instance.broadcast_subscribe
    instance.broadcast_render unless rendered

    @component = instance
  end

  def receive(data)
    live_connection.receive(component, data)
  end

  def unsubscribed
    return unless component

    stop_stream_from(component.channel_name)
    component.disconnected
    live_connection.remove_component(component)
    component.live_connection = nil
    @component = nil
  end

  private

  # @return [LiveCable::Component, nil]
  attr_reader :component
end
