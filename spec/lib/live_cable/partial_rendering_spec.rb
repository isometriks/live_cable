# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendering partials from a .live.erb template' do
  include LiveCable::Testing

  it 'passes the block to a layout partial' do
    component = live_mount('layout_partial')

    expect(component.rendered).to have_css('[data-testid="card"] h2', text: 'Count')
    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="card-count"]', text: '0')
  end

  it 're-renders the block when its dependencies change' do
    component = live_mount('layout_partial')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="card-count"]', text: '1')
  end

  it 'passes the block to a layout partial that a view helper renders' do
    component = live_mount('layout_partial')

    expect(component.rendered).to have_css('[data-testid="card"] h2', text: 'Helper')
    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="helper-card-count"]', text: '0')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="helper-card-count"]', text: '1')
  end

  it 'passes the block to a layout partial that another object renders' do
    component = live_mount('layout_partial')

    expect(component.rendered).to have_css('[data-testid="card"] h2', text: 'Presenter')
    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="presenter-card-count"]', text: '0')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="presenter-card-count"]', text: '1')
    expect(component.rendered_html).not_to include('&lt;')
  end

  it 'inlines a .live.erb partial rendered with a literal path' do
    component = live_mount('live_partial')

    expect(component.rendered).to have_css('[data-testid="live-partial"] [data-testid="live-card"]')
  end

  it 'raises when a .live.erb partial is rendered with a path only known at runtime' do
    expect do
      live_mount('lp_dynamic')
    end.to raise_error(
      ActionView::Template::Error,
      %r{\Aapp/views/shared/_live_card\.html\.live\.erb is a live partial\. .* such as `render 'shared/live_card'`}
    )
  end

  it 'raises when a .live.erb partial is rendered outside a component template' do
    expect do
      ApplicationController.render(partial: 'shared/live_card')
    end.to raise_error(ActionView::Template::Error, /_live_card\.html\.live\.erb is a live partial/)
  end
end
