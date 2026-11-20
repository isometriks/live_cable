# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Changesets consumed by the render that ships them' do
  include LiveCable::Testing

  def kinds(component)
    component.broadcasts.map { |frame| frame.keys.first }
  end

  def shared_changeset(component)
    component.connection.send(:containers)[LiveCable::Connection::SHARED_CONTAINER].changeset
  end

  def own_changeset(connection, live_id)
    connection.send(:containers)[live_id].changeset
  end

  describe 'stream callbacks' do
    it 'sends nothing for a callback that changes nothing after a reactive update' do
      tally = live_mount('tally')
      tally.set_reactive(:draft, 'hello')
      tally.clear_broadcasts

      tally.receive_stream('tally', { 'by' => nil })

      expect(tally.broadcasts).to be_empty
    end

    it 'sends only the part a callback changed after a reactive update' do
      tally = live_mount('tally')
      tally.set_reactive(:draft, 'hello')
      tally.clear_broadcasts

      tally.receive_stream('tally', { 'by' => 2 })

      parts = tally.broadcasts(:_refresh).sole[:_refresh][:p]
      expect(parts.compact).to eq(['2'])
      expect(tally.rendered).to have_css('[data-testid="draft"]', exact_text: 'hello')
    end
  end

  describe 'a write in after_render' do
    it 'renders on the next cycle of its own' do
      log = live_mount('render_log')
      log.clear_broadcasts

      log.perform(:noop)

      expect(kinds(log)).to eq([:_refresh])
      expect(log.rendered).to have_css('[data-testid="renders"]', exact_text: '1')
    end

    it 'renders on the next cycle another component drives' do
      log = live_mount('render_log')
      counter = live_mount('counter', connection: log.connection)
      log.clear_broadcasts

      counter.perform(:noop)

      expect(kinds(log)).to eq([:_refresh])
    end
  end

  describe 'shared variables' do
    it 'leaves the shared changeset empty once every sharer rendered' do
      first = live_mount('shared_counter', id: 'first')
      second = live_mount('shared_counter', id: 'second', connection: first.connection)
      first.clear_broadcasts
      second.clear_broadcasts

      first.perform(:bump)

      expect(first.broadcasts(:_refresh).size).to eq(1)
      expect(second.broadcasts(:_refresh).size).to eq(1)
      expect(shared_changeset(first)).to be_empty
    end

    it 'settles a shared variable two sharers derive in before_render' do
      first = live_mount('derived_total', id: 'first')
      second = live_mount('derived_total', id: 'second', connection: first.connection)
      first.perform(:bump)
      first.clear_broadcasts
      second.clear_broadcasts

      first.perform(:noop)

      expect(first.broadcasts).to eq([{ _ack: true }])
      expect(second.broadcasts).to be_empty
      expect(second.rendered).to have_css('[data-testid="doubled"]', exact_text: '2')
      expect(shared_changeset(first)).to be_empty
    end

    it 'keeps a shared variable a render derived pending for a sharer that did not render it' do
      total = live_mount('derived_total')
      view = live_mount('doubled_view', connection: total.connection)
      total.perform(:bump)

      total.perform(:noop)

      expect(view.rendered).to have_css('[data-testid="doubled"]', exact_text: '2')
      expect(shared_changeset(total)).to be_empty
    end
  end

  describe 'marks made at subscribe' do
    it 'consumes a shared default with the first render' do
      theme = live_mount('theme_switch', theme: 'dark')
      theme.clear_broadcasts

      theme.perform(:noop)

      expect(theme.broadcasts).to eq([{ _ack: true }])
    end

    it 'consumes a shared write in after_connect with the first render' do
      theme = live_mount('theme_switch', preset: 'dark')
      theme.clear_broadcasts

      theme.perform(:noop)

      expect(theme.broadcasts).to eq([{ _ack: true }])
      expect(theme.rendered).to have_css('[data-testid="theme"]', exact_text: 'dark')
    end

    it 'renders a sharer that rendered before a later mount changed the shared value on the next cycle' do
      first = live_mount('theme_switch', id: 'first')
      second = live_mount('theme_switch', id: 'second', connection: first.connection, theme: 'dark')
      first.clear_broadcasts
      second.clear_broadcasts

      first.perform(:noop)

      expect(kinds(first)).to eq([:_refresh])
      expect(first.rendered).to have_css('[data-testid="theme"]', exact_text: 'dark')
      expect(second.broadcasts).to be_empty
      expect(shared_changeset(first)).to be_empty
    end

    it 'renders a parent again after its inline child applied a shared default during its mount' do
      host = live_mount('theme_host')
      expect(host.rendered).to have_css('[data-testid="host-theme"]', exact_text: 'light')
      host.clear_broadcasts

      host.perform(:noop)

      expect(kinds(host)).to eq([:_refresh])
      expect(host.rendered).to have_css('[data-testid="host-theme"]', exact_text: 'dark')
    end
  end

  describe 'the snapshot point' do
    it 'leaves an inline child its first render created with nothing pending' do
      parent = live_mount('parent')

      expect(own_changeset(parent.connection, 'child/child-0')).to be_empty
    end

    it 'consumes the changeset of a template without .live.erb' do
      plain = live_mount('plain_erb')
      plain.perform(:increment)
      plain.clear_broadcasts

      expect(own_changeset(plain.connection, plain.live_id)).to be_empty

      plain.connection.broadcast_changeset

      expect(plain.broadcasts).to be_empty
    end
  end

  it 'sends only the _error for an action that raises after a reactive write' do
    tally = live_mount('tally', raise_errors: false)
    tally.clear_broadcasts

    tally.perform(:fail_after_write)

    expect(kinds(tally)).to eq([:_error])
  end
end
