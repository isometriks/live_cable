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

  it 're-renders a part that passes a top-level local by hash shorthand' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="total-data"][data-total="6"]')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="total-data"][data-total="10"]')
  end

  it 'keeps the value a do...end block gives a top-level local' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '6')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '10')

    component.perform(:flag)

    expect(component.rendered).to have_css('[data-testid="sum"]', exact_text: '10')
  end

  it 'keeps a local first assigned in an if for a later part that re-renders' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="greeting"]', exact_text: 'Hello-3')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="greeting"]', exact_text: 'Hello-4')
  end

  it 'keeps a local assigned in an output tag for a later part that re-renders' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="state-count"]', exact_text: 'off-3')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="state"]', exact_text: 'off')
    expect(component.rendered).to have_css('[data-testid="state-count"]', exact_text: 'off-4')
  end

  context 'when no later tag reads the local a group assigns' do
    let(:component) { live_mount('unread_locals') }

    it 'skips the group when nothing it reads has changed' do
      component.clear_broadcasts

      component.perform(:type)

      expect(component.broadcasts(:_refresh).sole.dig(:_refresh, :p).compact).to eq(['x'])
    end

    it "doesn't re-render a child inside the group" do
      child = component.connection.get_component('child/item-a')

      expect { component.perform(:type) }.not_to change(child, :renders)
    end
  end

  it 're-renders locals set by multiple assignment, pattern matching and a named capture' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="rest"]', exact_text: '2')
    expect(component.rendered).to have_css('[data-testid="last-count"]', exact_text: '3')
    expect(component.rendered).to have_css('[data-testid="digits"]', exact_text: '123')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="rest"]', exact_text: '3')
    expect(component.rendered).to have_css('[data-testid="last-count"]', exact_text: '4')
    expect(component.rendered).to have_css('[data-testid="digits"]', exact_text: '1234')
  end

  context 'when a template reads a block local after its block' do
    it 'raises NameError on mount' do
      expect { live_mount('block_local_read') }.to raise_error(NameError)
    end

    it 'raises NameError on the page' do
      expect do
        ApplicationController.render(inline: "<%= live('block_local_read', id: 'b1') %>")
      end.to raise_error(ActionView::Template::Error) { |error| expect(error.cause).to be_a(NameError) }
    end
  end

  it 'keeps the earlier value of a local when the branch that reassigns it does not run' do
    component = live_mount('template_locals')

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'old')

    component.perform(:flag)

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'new')

    component.perform(:add_count)

    expect(component.rendered).to have_css('[data-testid="badge"]', exact_text: 'new')
  end

  context 'when a method shares its name with a template local' do
    let(:component) { live_mount('local_calls') }

    it 'calls the helper when the name is called with arguments' do
      expect(component.rendered).to have_css('[data-testid="local"]', text: 'local')
      expect(component.rendered).to have_css('[data-testid="call"]', text: 'HI')
    end

    it 'calls the component method for name() and self.name' do
      expect(component.rendered).to have_css('[data-testid="label"]', exact_text: 'local')
      expect(component.rendered).to have_css('[data-testid="label-parens"]', exact_text: 'component')
      expect(component.rendered).to have_css('[data-testid="label-self"]', exact_text: 'component')
    end
  end
end
