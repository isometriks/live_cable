# frozen_string_literal: true

class LiveChannel < ActionCable::Channel::Base
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
    live_connection.handle_error(instance, error) if instance
  end

  def receive(data)
    live_connection.receive(component, data)
  end

  def unsubscribed
    return unless component

    component.disconnect
    @component = nil
  end

  private

  # @return [LiveCable::Component, nil]
  attr_reader :component
end
