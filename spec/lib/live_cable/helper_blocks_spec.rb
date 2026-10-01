# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Blocks passed to view helpers from a .live.erb template' do
  include LiveCable::Testing

  it 'passes the block as written to a helper that checks its arity or instance_execs it' do
    component = live_mount('helper_blocks')

    expect(component.rendered).to have_css('[data-testid="link"]', exact_text: 'Home at /')
    expect(component.rendered).to have_css('[data-testid="words"]', exact_text: 'live, cable')
  end
end
