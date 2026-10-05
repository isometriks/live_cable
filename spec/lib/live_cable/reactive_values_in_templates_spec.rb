# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactive values in templates' do
  include LiveCable::Testing

  def prerender(name)
    Capybara.string(ApplicationController.render(inline: "<%= live('#{name}', id: 'test') %>"))
  end

  def mount_child(parent, live_id)
    live_mount(parent.connection.get_component(live_id), connection: parent.connection)
  end

  it 'renders tag helper options from reactive values the same as the prerender' do
    socket = live_mount('tag_options').rendered

    [prerender('tag_options'), socket].each do |html|
      expect(html).to have_css('span.btn.primary[data-testid="span"]')
      expect(html).to have_css('b.active[data-testid="b"]')
      expect(html).to have_no_css('b.hidden')
      expect(html).to have_css('i.btn.primary.active[data-testid="i"]')
      expect(html).to have_css('u[data-active="true"][data-hidden="false"]')
      expect(html).to have_css('[data-testid="kind"]', text: 'array')
      expect(html).to have_css('span.btn.primary[data-testid="display"]')
      expect(html).to have_css('[data-testid="display-kind"]', text: 'array')
    end
  end

  it 'keeps rendering reactive tag options after a mutation' do
    component = live_mount('tag_options')

    component.perform(:add_class)

    expect(component.rendered).to have_css('span.btn.primary.more[data-testid="span"]')
  end

  it 'renders tag helper options from collections a component method builds the same as the prerender' do
    socket = live_mount('grouped_todos').rendered

    [prerender('grouped_todos'), socket].each do |html|
      expect(html).to have_css('b.a.b[data-testid="row-1"]')
      expect(html).to have_css('i.a.b[data-testid="status-1"]')
      expect(html).to have_css('u.dark.wide[data-testid="theme"]')
      expect(html).to have_css('s.a.b[data-testid="end-1"]')
    end
  end

  it 'leaves collections a component method builds alone on the prerender, where they hold no wrappers' do
    expect_any_instance_of(LiveCable::RenderContext).not_to receive(:unwrap_nested)

    expect(prerender('grouped_todos')).to have_css('b.a.b[data-testid="row-1"]')
  end

  it 'gives component code the plain value through Delegator.unwrap on the prerender and over the socket' do
    socket = live_mount('grouped_todos').rendered

    [prerender('grouped_todos'), socket].each do |html|
      expect(html).to have_css('[data-testid="settings-kind"]', text: 'Hash')
    end
  end

  it 'renders reactive tag options in .html.erb templates' do
    component = live_mount('tag_options_erb')

    component.perform(:add_class)

    expect(component.rendered).to have_css('span.btn.primary.more[data-testid="span"]')
  end

  it 'renders tag helper options from an element moved into another variable' do
    board = live_mount('kanban_board')

    board.perform(:finish)

    expect(board.rendered).to have_css('b.a.b', text: '1')
  end

  it 're-renders the parent when a child changes a collection it was passed' do
    parent = live_mount('sharing_parent')

    mount_child(parent, 'sharing_list/list').perform(:add)

    expect(parent.rendered).to have_css('[data-testid="total"]', text: '3')
  end

  it 're-renders a child given a reactive value when the parent changes it, though another variable holds it' do
    parent = live_mount('sharing_parent')

    parent.perform(:add)

    expect(parent.rendered).to have_css('[live-id="list"] [data-testid="list-total"]', text: '3')
  end

  it 're-renders the parent when a child changes an element of a collection built in the template' do
    parent = live_mount('sharing_parent')

    mount_child(parent, 'sharing_list/open').perform(:finish_first)

    expect(parent.rendered).to have_css('[data-testid="done"]', text: '1')
  end

  it 're-renders the parent when a child changes an element it was passed' do
    parent = live_mount('sharing_parent')

    mount_child(parent, 'sharing_row/row-2').perform(:finish)

    expect(parent.rendered).to have_css('[data-testid="done"]', text: '1')
  end

  it 're-renders the parent when a child changes an element of a collection a component method built' do
    parent = live_mount('sharing_parent')

    mount_child(parent, 'sharing_list/ends').perform(:finish_first)

    expect(parent.rendered).to have_css('[data-testid="done"]', text: '1')
  end

  it 'maps props back to tracked values only for a child it creates' do
    parent = live_mount('sharing_parent')
    expect_any_instance_of(LiveCable::RenderContext).not_to receive(:track)

    parent.perform(:finish_first)

    expect(parent.rendered).to have_css('[data-testid="done"]', text: '1')
  end
end
