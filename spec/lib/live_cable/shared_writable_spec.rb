# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client writes to a shared reactive variable' do
  include LiveCable::Testing

  # A client can subscribe the writable sharer just to write through it.
  it 'is refused when another class shares the name without writable' do
    summary = live_mount('account_summary', id: 'summary')
    switcher = live_mount('account_switcher', id: 'attacker', connection: summary.connection)

    expect { switcher.set_reactive(:account_id, 999) }.to raise_error(LiveCable::Forbidden)
    expect(summary.account_id).to eq(1)
  end

  it 'is allowed when every class that shares the name declares it writable' do
    search = live_mount('search_box')

    search.set_reactive(:query, 'cable')

    expect(search.query).to eq('cable')
  end
end

RSpec.describe 'Client writes to a shared name after a code reload' do
  include LiveCable::Testing

  def define_guard(body)
    Live.module_eval("class ProbeGuard < LiveCable::Component; #{body}; end", __FILE__, __LINE__)
  end

  before { define_guard('shared :query') }

  after do
    Live.send(:remove_const, :ProbeGuard) if Live.const_defined?(:ProbeGuard, false)
    LiveCable::Component::ReactiveVariables::SHARED_DECLARATIONS[:query].delete('Live::ProbeGuard')
  end

  it 'is refused while the guarding class still shares the name' do
    search = live_mount('search_box')

    expect { search.set_reactive(:query, 'cable') }.to raise_error(LiveCable::Forbidden)
  end

  it 'is allowed once the guarding class no longer exists' do
    Live.send(:remove_const, :ProbeGuard)
    search = live_mount('search_box')

    search.set_reactive(:query, 'cable')

    expect(search.query).to eq('cable')
  end

  it 'is allowed once the reloaded guarding class stops sharing the name' do
    Live.send(:remove_const, :ProbeGuard)
    define_guard('reactive :other')
    search = live_mount('search_box')

    search.set_reactive(:query, 'cable')

    expect(search.query).to eq('cable')
  end

  it 'is allowed once the reloaded guarding class only inherits a writable declaration' do
    Live.send(:remove_const, :ProbeGuard)
    Live.const_set(:ProbeGuard, Class.new(Live::SearchBox))
    search = live_mount('search_box')

    search.set_reactive(:query, 'cable')

    expect(search.query).to eq('cable')
  end

  it 'is refused while a guarding class with a temporary name shares the name' do
    Live.send(:remove_const, :ProbeGuard)
    namespace = Module.new
    namespace.module_eval('class Guard < LiveCable::Component; shared :query; end', __FILE__, __LINE__)
    search = live_mount('search_box')

    expect { search.set_reactive(:query, 'cable') }.to raise_error(LiveCable::Forbidden)
  ensure
    LiveCable::Component::ReactiveVariables::SHARED_DECLARATIONS[:query].delete(namespace::Guard.name)
  end
end
