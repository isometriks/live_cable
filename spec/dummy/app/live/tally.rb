# frozen_string_literal: true

module Live
  class Tally < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :draft, -> { '' }, writable: true

    actions :noop, :fail_after_write

    after_connect :listen

    def noop; end

    def fail_after_write
      self.count += 1
      raise 'Failed after writing'
    end

    private

    def listen
      stream_from('tally', coder: ActiveSupport::JSON) do |data|
        self.count += data['by'] if data['by']
      end
    end
  end
end
