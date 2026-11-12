# frozen_string_literal: true

module Live
  class ThemeSwitch < LiveCable::Component
    reactive :theme, -> { 'light' }, shared: true
    reactive :preset

    actions :noop

    after_connect { self.theme = preset if preset }

    def noop; end
  end
end
