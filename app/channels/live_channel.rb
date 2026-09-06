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

    # Lets the page recover from a token this socket cannot verify without
    # re-rendering anything - see Connection#csrf_token
    token = live_connection.csrf_token
    transmit({ _csrf_token: token }) if token

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
  # _refresh, _ack, _error or _reconnect arrives - so nothing raised here may
  # escape to ActionCable, which would only log it and leave the client hanging.
  def receive(data)
    raise LiveCable::Error, 'Component failed to subscribe, so it cannot receive messages' unless component

    live_connection.receive(component, data)
  rescue LiveCable::InvalidCsrfToken
    # The page's token is minted from the current session; it is this socket's
    # handshake session that has gone stale (a sign-in rotates the token). A
    # fresh handshake carries the current cookie, so ask the client to
    # reconnect and replay the batch - nothing in it has run.
    logger.info 'LiveCable: CSRF token is from a newer session than the socket; asking the client to reconnect'
    transmit({ _reconnect: true, messages: data['messages'] })
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
