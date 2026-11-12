# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'content_for across the tags of a .live.erb template' do
  include LiveCable::Testing

  let(:component) { live_mount('content_for_heading') }

  it 'keeps the content when only the reading tag re-renders' do
    expect(component.rendered).to have_css('[data-testid="heading"]', exact_text: 'Inbox (0)')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="heading"]', exact_text: 'Inbox (1)')
  end

  it 'shows new content when only the providing tag changes' do
    component.perform(:rename)

    expect(component.rendered).to have_css('[data-testid="heading"]', exact_text: 'Outbox (0)')
  end
end
