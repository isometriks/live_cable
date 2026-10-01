# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Template names that Kernel or Object also define' do
  include LiveCable::Testing

  let(:component) { live_mount('kernel_names') }

  it 'resolves a reactive variable to the component and re-renders it' do
    expect(component.rendered).to have_css('[data-testid="state"]', text: 'closed')

    component.perform(:toggle)

    expect(component.rendered).to have_css('[data-testid="state"]', text: 'open')
  end

  it 'resolves component methods to the component' do
    expect(component.rendered).to have_css('[data-testid="test"]', text: 'from the component')
    expect(component.rendered).to have_css('[data-testid="display"]', text: 'compact')
  end

  it 'resolves view helpers to the view context' do
    expect(component.rendered).to have_css('select#post_category option', count: 2)
    expect(component.rendered).to have_css('[data-testid="j"]', text: "a\\'b")
  end

  it 'renders the block a Kernel-named view helper passes to a layout inside it' do
    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="trapped"]', text: 'inside')
    expect(component.rendered_html).not_to include('&lt;')
  end

  it 'keeps the Kernel and Object methods that nothing else defines' do
    expect(component.rendered).to have_css('[data-testid="price"]', text: '1.50')
    expect(component.rendered).to have_css('[data-testid="kernel"]', text: '0 4')
    expect(component.rendered).to have_css('[data-testid="send"]', text: '1.5')
  end

  it 'answers a bare respond_to? for the component too' do
    expect(component.rendered).to have_css('[data-testid="respond"]', text: 'true')
  end

  context 'when the component overrides Object methods' do
    let(:component) { live_mount('kernel_names_overrides') }

    it 'resolves them to the component' do
      expect(component.rendered).to have_css('[data-testid="method"]', text: 'post')
      expect(component.rendered).to have_css('[data-testid="send"]', text: 'sent hi')
    end

    it 'keeps the other Object names working' do
      expect(component.rendered).to have_css('[data-testid="try"]', text: 'sub')
    end
  end
end
