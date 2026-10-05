# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client writes to a shared reactive variable' do
  include LiveCable::Testing

  # A client can subscribe the writable sharer just to write through it.
  it 'is refused when another class shares the name without writable' do
    summary = live_mount('account_summary', id: 'summary')
    switcher = live_mount('account_switcher', id: 'attacker', connection: summary.connection)

    expect { switcher.set_reactive(:account_id, 999) }.to raise_error(LiveCable::Forbidden)
    expect(summary.account_id).to eq(1)
  end

  it 'is allowed when every class that shares the name declares it writable' do
    search = live_mount('search_box')

    search.set_reactive(:query, 'cable')

    expect(search.query).to eq('cable')
  end
end
