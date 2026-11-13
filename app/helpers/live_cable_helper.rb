# frozen_string_literal: true

module LiveCableHelper
  # @param [LiveCable::Component] component
  def with_render_context(component, &)
    # Add the current component to the parent context before making a new context
    render_context&.add_component(component)

    # A prerendered root is the one component whose defaults are signed into the page
    component.round_trip_defaults if render_context.nil? && !component.live_connection

    # If we had a parent with a live connection, we're connected, so apply defaults now, if not
    # then we apply them to the pre-render container
    component.apply_defaults

    context = LiveCable::RenderContext.new(component, root: context_stack.first)
    context_stack.push(context)

    begin
      value = nil

      # A connected root runs its render callbacks in broadcast_render
      if component.live_connection && !context.root?
        component.run_callbacks(:render) { value = yield }
      else
        value = yield
      end
    ensure
      context_stack.pop
      context.forget_tracked_values
    end

    [value, context]
  end

  def render_part(index, &)
    ctx = render_context
    return yield unless ctx

    ctx.render_part(index, &)
  end

  # Relative t('.key') lookups resolve against @virtual_path, which ActionView
  # only sets while the template's compiled method runs, not while its parts do.
  def with_live_cable_virtual_path(virtual_path)
    previous = @virtual_path
    @virtual_path = virtual_path
    yield
  ensure
    @virtual_path = previous
  end

  # Parts run after ActionView has left the template; cache reads it for its digest
  def with_current_template(template)
    previous = @current_template
    @current_template = template
    yield
  ensure
    @current_template = previous
  end

  def live(component, id:, **defaults)
    unless component.is_a?(String)
      raise LiveCable::Error, '`live` helper only accepts string component names. Use render(component) directly if ' \
                              'you have a component instance.'
    end

    id = LiveCable::Component.resolve_id(id)

    live_id = "#{component}/#{id}"
    return live_child_placeholder(live_id) if render_context&.keep_refused(live_id)

    component = render_context&.get_component(live_id) || LiveCable.instance_from_string(component, id)
    track = render_context && !component.defaults_applied
    component.defaults = track ? defaults.transform_values { |value| render_context.track(value) } : defaults

    return render(component) unless render_context&.live_connection
    return render_live_child(component).tap { component.mark_changed_props(render_context) } if track

    component.mark_changed_props(render_context)
    render_live_child(component)
  end

  # A meta tag carrying a digest of who this page was rendered for. When a
  # Turbo visit brings a different one - after a sign-in, sign-out or
  # impersonation - the client reopens its socket, so the new handshake
  # identifies the new session. Pass what your connection's connect
  # identifies by; the values are never sent in the clear.
  #
  # @param values [Array<Object>] e.g. current_user, or nil when signed out
  def live_cable_identity_tag(*values)
    tag.meta(name: 'live-cable-identity', content: LiveCable::IdentityDigest.digest(*values))
  end

  # Templates get the plain value inside a reactive one, so Rails helpers and
  # `case` see a real Array or Hash.
  def live_cable_unwrap(value)
    case value
    when LiveCable::Delegator then render_context.unwrap(value)
    when Array, Hash then render_context.live_connection ? render_context.unwrap_nested(value) : value
    else value
    end
  end

  private

  # A child that refuses while its parent renders it is refused on its own
  def render_live_child(component)
    render(component)
  rescue LiveCable::Refused => refusal
    render_context.live_connection.handle_error(component, refusal)
    live_child_placeholder(component.live_id)
  end

  def live_child_placeholder(live_id)
    content_tag('LiveCable', nil, 'child-live-id' => live_id)
  end

  # A fragment that renders a child is never stored: a cache hit would skip its live(...) call
  def write_fragment_for(name, options, &)
    return super unless (context = render_context)

    renders = context.inline_renders
    fragment = output_buffer.capture(&)
    return fragment if context.inline_renders > renders

    controller.write_fragment(name, fragment, options)
  end

  # @return [LiveCable::RenderContext, nil]
  def render_context
    context_stack.last
  end

  # @return [Array<LiveCable::RenderContext>]
  def context_stack
    @context_stack ||= []
  end
end
