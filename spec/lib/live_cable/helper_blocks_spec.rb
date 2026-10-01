# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Blocks passed to view helpers from a .live.erb template' do
  include LiveCable::Testing

  it 'passes the block as written to a helper that checks its arity or instance_execs it' do
    component = live_mount('helper_blocks')

    expect(component.rendered).to have_css('[data-testid="link"]', exact_text: 'Home at /')
    expect(component.rendered).to have_css('[data-testid="words"]', exact_text: 'live, cable')
  end

  it 'lets the template write to @output_buffer as plain ERB does' do
    page = Capybara.string(ApplicationController.render(inline: "<%= live('helper_blocks', id: 'test') %>"))

    [page, live_mount('helper_blocks').rendered].each do |html|
      expect(html).to have_css('[data-testid="buffer"] i', exact_text: 'top')
      expect(html).to have_css('[data-testid="block-buffer"]', exact_text: 'in block')
    end
  end
end
