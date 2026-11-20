# frozen_string_literal: true

module Live
  # Stands in for a component whose access the application checks
  class Revocable < LiveCable::Component
    class Gone < StandardError; end

    reactive :count, -> { 0 }
    reactive :access, -> { 'granted' }
    reactive :notice, -> { '' }

    actions :increment, :leave, :vanish

    after_connect :check_on_connect
    before_dispatch :check_access

    rescue_from StandardError do
      self.notice = 'rescued'
    end

    rescue_from(Gone) { refuse!('gone') }

    def increment
      self.count += 1
    end

    def leave
      refuse!('membership_ended')
    end

    def vanish
      raise Gone
    end

    private

    def check_on_connect
      refuse!('no_access') if access == 'none_on_connect'
      stream_from('revocable') { |payload| refuse!(payload['reason']) }
    end

    def check_access
      refuse!('no_access') if access == 'revoked'
    end
  end
end
