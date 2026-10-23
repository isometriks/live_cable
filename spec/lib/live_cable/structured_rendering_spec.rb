# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendering a component whose markup is mostly control blocks' do
  include LiveCable::Testing

  def titles(component)
    component.rendered.all('[data-testid="title"]').map(&:text)
  end

  def last_refresh(component)
    component.broadcasts(:_refresh).last[:_refresh].as_json
  end

  def mount_with(*titles)
    component = live_mount('checklist')
    titles.reverse_each { |title| component.perform(:add, title:) }
    component
  end

  it 'renders the empty state' do
    component = live_mount('checklist')

    expect(component.rendered).to have_css('[data-testid="empty"]', text: 'Nothing to do.')
  end

  it 'renders added todos, newest first' do
    component = mount_with('Milk', 'Eggs')

    expect(titles(component)).to eq(%w[Milk Eggs])
    expect(component.rendered).to have_css('[data-testid="remaining"]', text: '2 left')
  end

  it 'renders a toggled todo in its done branch' do
    component = mount_with('Milk', 'Eggs')

    component.perform(:toggle, id: 2)

    expect(component.rendered).to have_css('#todo-2 .line-through', text: 'Milk')
    expect(component.rendered).to have_css('#todo-2 input[checked]')
    expect(component.rendered).to have_css('[data-testid="remaining"]', text: '1 left')
  end

  it 'renders removals, renames and filters' do
    component = mount_with('Milk', 'Eggs', 'Bread')

    component.perform(:remove, id: 2)
    component.perform(:rename, id: 1, title: 'Oat milk')
    component.perform(:toggle, id: 3)
    component.perform(:show, filter: 'active')

    expect(titles(component)).to eq(['Oat milk'])

    component.perform(:show, filter: 'done')

    expect(titles(component)).to eq(['Milk'])
  end

  it 'goes back to the empty state when the last todo is removed' do
    component = mount_with('Milk')

    component.perform(:remove, id: 1)

    expect(component.rendered).to have_css('[data-testid="empty"]')
  end

  it 'sends a full render after one that could not be delivered' do
    component = mount_with('Milk', 'Eggs')
    channel = component.component.instance_variable_get(:@channel)

    # A component a parent rendered inline has no channel yet
    component.component.instance_variable_set(:@channel, nil)
    component.perform(:rename, id: 1, title: 'Eggs, free range')
    component.component.instance_variable_set(:@channel, channel)

    component.perform(:add, title: 'Bread')

    expect(titles(component)).to eq(['Bread', 'Milk', 'Eggs, free range'])
  end

  it 'answers with an ack when the blocks an action re-runs render the same values' do
    component = mount_with('Milk')
    component.clear_broadcasts

    component.perform(:show, filter: 'all')

    expect(component.broadcasts(:_refresh)).to be_empty
    expect(component.broadcasts(:_ack)).to eq([{ _ack: true }])
  end

  it 'sends the statics of a scope once' do
    component = mount_with('Milk')
    component.clear_broadcasts

    component.perform(:add, title: 'Eggs')

    expect(last_refresh(component)).not_to have_key('s')
  end

  it 'sends the statics of a branch the client has not seen yet' do
    component = mount_with('Milk')
    component.clear_broadcasts

    component.perform(:toggle, id: 1)

    statics = last_refresh(component)['s'].values.join

    expect(statics).to include('line-through')
    expect(statics).not_to include('<ul')
  end

  it 'sends a renamed todo as its new title and nothing else from the list' do
    component = mount_with('Milk', 'Eggs', 'Bread')
    component.clear_broadcasts

    component.perform(:rename, id: 2, title: 'Free-range eggs')

    payload = last_refresh(component)['p'].to_json

    expect(payload).to include('Free-range eggs')
    expect(payload).not_to include('Milk')
    expect(payload).not_to include('Bread')
    expect(payload).not_to include('<li')
  end

  it 'sends a new todo as one row and the new key order' do
    component = mount_with('Milk', 'Eggs')
    component.clear_broadcasts

    component.perform(:add, title: 'Bread')

    list = last_refresh(component)['p'].grep(Hash).first.dig('d', '0')

    expect(list['k']).to eq(%w[todo-3 todo-2 todo-1])
    expect(list['r'].keys).to eq(%w[todo-3])
  end
end
