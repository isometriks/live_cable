# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::Rendering::Partial do
  include LiveCable::Testing

  def render_template(source, identifier: '/views/live/cached_template.html.live.erb')
    template = ActionView::Template.new(source, identifier, LiveCable::Rendering::Handler, locals: [], format: :html)
    template.render(ApplicationController.new.view_context, {})
  end

  def renderer_class(partial)
    partial.send(:renderer_class)
  end

  it 'builds a template once and reuses it on every render' do
    first = render_template('<p><%= count %></p>')
    second = render_template('<p><%= count %></p>')

    expect(second).to equal(first)
    expect(renderer_class(second)).to equal(renderer_class(first))
  end

  it 'builds a new one when the template changes' do
    old = render_template('<p><%= count %></p>', identifier: '/views/live/edited.html.live.erb')
    edited = render_template('<p><%= count %>!</p>', identifier: '/views/live/edited.html.live.erb')

    expect(edited).not_to equal(old)
    expect(render_template('<p><%= count %>!</p>', identifier: '/views/live/edited.html.live.erb')).to equal(edited)
  end

  it 'keeps one entry per template' do
    render_template('<p>one</p>', identifier: '/views/live/bounded.html.live.erb')
    render_template('<p>two</p>', identifier: '/views/live/bounded.html.live.erb')

    expect(described_class::CACHE.keys.grep(/bounded/).size).to eq(1)
  end

  it 'keeps different templates apart' do
    first = render_template('<p><%= count %></p>', identifier: '/views/live/first.html.live.erb')
    second = render_template('<p><%= count %></p>', identifier: '/views/live/second.html.live.erb')

    expect(second).not_to equal(first)
  end

  it 'reuses the build when a component renders again' do
    counter = live_mount('counter')
    allow(described_class).to receive(:new).and_call_original

    counter.perform(:increment)

    expect(described_class).not_to have_received(:new)
    expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '1')
  end

  it 'keeps state apart between instances of the same component' do
    first = live_mount('counter', id: 'first')
    second = live_mount('counter', id: 'second', connection: first.connection)

    first.perform(:increment)
    first.perform(:increment)
    second.perform(:decrement)

    expect(first.rendered).to have_css('[data-testid="counter-value"]', text: '2')
    expect(second.rendered).to have_css('[data-testid="counter-value"]', text: '-1')
  end
end
