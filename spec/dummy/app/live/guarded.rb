# frozen_string_literal: true

module Live
  class Guarded < GuardedBase
    reactive :count, -> { 0 }
    reactive :name, -> { '' }, writable: true

    actions :increment, :rename, :subscribe_to_feed

    def increment(params)
      self.count += (params[:by] || 1).to_i
    end

    def rename
      self.name = 'server'
    end

    def subscribe_to_feed
      stream_from('guarded') { |payload| self.count = payload['count'] }
    end
  end
end
