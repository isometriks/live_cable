# frozen_string_literal: true

module Live
  class ReplyChild < LiveCable::Component
    class Handled < StandardError; end
    class Rerendered < StandardError; end

    reactive :hidden, -> { [] }, shared: true
    reactive :tick, -> { 0 }, shared: true
    reactive :explode, -> { false }, shared: true
    reactive :count, -> { 0 }
    reactive :note, -> { '' }
    reactive :halt, -> { false }

    actions :own, :hide_me, :bump_shared, :bump_both, :raise_plain, :raise_handled_noop,
      :raise_handled_change, :raise_handled_render, :halted, :explode_parent, :thread_write,
      :staged_only, :announce_and_raise, :invisible_change

    before_dispatch { throw :abort if halt }

    rescue_from Handled do |error|
      self.note = error.message if error.message.present?
    end

    rescue_from Rerendered do
      self.note = 'rerendered'
      broadcast_render
    end

    def own = self.count += 1

    def hide_me = hidden << id

    def bump_shared = self.tick += 1

    def bump_both
      self.tick += 1
      self.count += 1
    end

    def raise_plain = raise('boom')

    def raise_handled_noop = raise(Handled, '')

    def raise_handled_change = raise(Handled, 'handled')

    def raise_handled_render = raise(Rerendered)

    def halted
      self.count += 100
    end

    def explode_parent = self.explode = true

    def thread_write
      connection = live_connection
      @thread = Thread.new do
        connection.synchronize do
          connection.reset_changeset
          self.count += 10
          connection.broadcast_changeset
        end
      end
      @thread.join(0.2)
    end

    def join_thread = @thread&.join

    def staged_only
      self.count += 1
      broadcast_render
    end

    def announce_and_raise
      dispatch_event('reply:announced')
      raise 'after event'
    end

    def invisible_change
      self.halt = false
    end
  end
end
