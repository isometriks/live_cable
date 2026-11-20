# frozen_string_literal: true

module Live
  class RenderLog < LiveCable::Component
    reactive :renders, -> { 0 }

    actions :noop

    after_render { self.renders += 1 }

    def noop; end
  end
end
