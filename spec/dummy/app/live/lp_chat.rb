# frozen_string_literal: true

module Live
  class LpChat < LiveCable::Component
    reactive :title, -> { 'Lobby' }
    reactive :messages, -> { ['hi', '<b>x</b>'] }
    reactive :count, -> { 1 }
    reactive :open_panel, -> { true }
    reactive :draft, -> { '' }, writable: true
    reactive :footer, -> { 'f' }

    actions :add_message, :rename, :bump, :toggle, :change_footer

    def add_message = messages << 'new'
    def rename = self.title = 'Renamed'
    def bump = self.count = count + 1
    def toggle = self.open_panel = !open_panel
    def change_footer = self.footer = 'g'
  end
end
