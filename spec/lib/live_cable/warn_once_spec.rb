# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'LiveCable.warn_once' do
  include LiveCable::Testing

  before do
    # Reset the per-process de-dupe set so each example starts clean
    LiveCable.instance_variable_set(:@warned_messages, Set.new)
  end

  it 'logs a given message only once per process' do
    expect(LiveCable.logger).to receive(:warn).with('hello').once

    3.times { LiveCable.warn_once('hello') }
  end

  it 'logs distinct messages independently' do
    expect(LiveCable.logger).to receive(:warn).with('a').once
    expect(LiveCable.logger).to receive(:warn).with('b').once

    LiveCable.warn_once('a')
    LiveCable.warn_once('b')
    LiveCable.warn_once('a')
  end

  it 'renders a non-.live.erb template without warning on every render' do
    allow(LiveCable.logger).to receive(:warn)

    # PlainErb uses a .html.erb template, so it hits the warn_once path, but
    # only the first render across the mount + two actions should log.
    counter = live_mount('plain_erb')
    counter.perform(:increment)
    counter.perform(:increment)

    expect(LiveCable.logger).to have_received(:warn).with(/less performant/).once
  end
end
