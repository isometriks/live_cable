# frozen_string_literal: true

module Live
  class ThemeHost < LiveCable::Component
    reactive :theme, -> { 'light' }, shared: true

    actions :noop

    def noop; end
  end
end
