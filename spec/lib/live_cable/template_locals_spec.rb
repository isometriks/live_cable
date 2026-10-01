# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Template locals in a .live.erb template' do
  include LiveCable::Testing

  it 'resolves a name assigned only inside an earlier block to the component' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('li.message', exact_text: 'Hello')
    expect(component.rendered).to have_css('[data-testid="css"]', exact_text: 'message-list')
  end

  it 'keeps the value a block gives a top-level local' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="total"]', exact_text: '6')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="total"]', exact_text: '10')
  end

  it 'keeps the value a do...end block gives a top-level local' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '6')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '10')

    component.perform(:flag)

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '10')
  end

  it 'keeps the earlier value of a local when the branch that reassigns it does not run' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'old')

    component.perform(:flag)

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'new')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'new')
  end
end
