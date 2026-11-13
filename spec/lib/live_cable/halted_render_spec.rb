# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A render a before_render callback halted' do
  include LiveCable::Testing

  it 'sends what changed while it was halted once it renders again' do
    pausable = live_mount('pausable')

    pausable.perform(:pause)
    pausable.perform(:increment)
    pausable.perform(:resume)

    expect(pausable.rendered).to have_css('[data-testid="count"]', exact_text: '1')
  end

  it 'sends what changed while its parent rendered it halted once it renders again' do
    host = live_mount('pausable_host')
    pausable = live_mount(host.connection.get_component('pausable/child'), connection: host.connection)

    pausable.perform(:pause)
    pausable.perform(:increment)
    host.perform(:relabel)
    pausable.perform(:resume)

    expect(pausable.rendered).to have_css('[data-testid="count"]', exact_text: '1')
  end

  it 'sends only what changed on the renders after that' do
    pausable = live_mount('pausable')
    pausable.perform(:pause)
    pausable.perform(:resume)
    pausable.clear_broadcasts

    pausable.perform(:increment)

    expect(pausable.broadcasts(:_refresh).map { |frame| frame[:_refresh][:p].compact }).to eq([['1']])
  end
end
