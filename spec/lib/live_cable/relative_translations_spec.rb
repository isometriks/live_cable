# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Relative t('.key') lookups in component templates" do
  include LiveCable::Testing

  it "uses the component template's scope over the socket" do
    component = live_mount('translated')
    component.perform(:bump)

    expect(component.rendered).to have_css('[data-testid="hello"]', text: 'Hello from the component')
    expect(component.rendered).to have_css('[data-testid="count"]', text: 'Count: 1')
  end

  it "uses the component template's scope on prerender, not the page's" do
    html = Capybara.string(ApplicationController.render(template: 'home/translated', layout: false))

    expect(html).to have_css('[data-testid="hello"]', text: 'Hello from the component')
    expect(html).to have_css('[data-testid="child-hello"]', text: 'Hello from the child')
  end

  it "uses each child's own scope and restores the parent's after it" do
    component = live_mount('translated')

    expect(component.rendered).to have_css('[data-testid="child-hello"]', text: 'Hello from the child')
    expect(component.rendered).to have_css('[data-testid="after-child"]', text: 'Hello from the component')
  end

  it "uses the current variant's scope in a compound component" do
    component = live_mount('translated_compound')
    expect(component.rendered).to have_css('[data-testid="name"]', text: 'Even')

    component.perform(:bump)

    expect(component.rendered).to have_css('[data-testid="name"]', text: 'Odd')
  end
end
