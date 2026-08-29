# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

RSpec.describe 'Connection view context reuse' do
  include LiveCable::Testing

  it 'reuses a single view context across renders on a connection' do
    connection = LiveCable::Connection.new(
      ActionDispatch::TestRequest.create('rack.session' => {})
    )

    expect(connection.view_context).to be_a(ActionView::Base)
    expect(connection.view_context).to equal(connection.view_context)
  end

  it 'renders correct, consistent output across repeated renders' do
    counter = live_mount('counter', step: 3)

    counter.perform(:increment)
    counter.perform(:increment)

    # rendered_html is reconstructed from the _refresh diffs, so it only comes
    # out right if each reused-context render produced the correct parts.
    expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '6')
  end

  it 'renders multiple components sharing one connection correctly' do
    parent = live_mount('counter', id: 'p', step: 1)
    # Mount a second component on the same connection (shares the view context)
    other = live_mount('hidden_var', id: 'h', connection: parent.connection)

    parent.perform(:increment)
    other.perform(:bump_shown)

    expect(parent.rendered).to have_css('[data-testid="counter-value"]', text: '1')
    expect(other.rendered).to have_css('[data-testid="shown"]', text: '1')
  end
end
