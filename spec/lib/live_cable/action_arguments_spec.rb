# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Action arguments' do
  include LiveCable::Testing

  %i[required optional splat optional_with_keywords wrapped_with_params].each do |action|
    it "passes the params to an action declared as #{action}" do
      component = live_mount('action_arguments')

      component.perform(action, q: 'cable')

      expect(component.received.to_a).to eq(['cable'])
    end
  end

  it 'calls an action that takes only keywords without the params' do
    component = live_mount('action_arguments')

    component.perform(:keywords_only, q: 'cable')

    expect(component.received.to_a).to eq([{}])
  end

  it 'calls an action that takes no arguments without the params' do
    component = live_mount('action_arguments')

    component.perform(:none, q: 'cable')

    expect(component.received.to_a).to eq([:none])
  end

  it 'calls a delegated action without the params' do
    component = live_mount('action_arguments')

    component.perform(:next_page, q: 'cable')

    expect(component.received.to_a).to eq([:next_page])
  end

  it 'calls a wrapped action with what the wrapped method takes' do
    component = live_mount('action_arguments')

    component.perform(:wrapped, q: 'cable')

    expect(component.received.to_a).to eq([:wrapped])
  end

  it 'calls an action served by method_missing without the params' do
    component = live_mount('action_arguments')

    component.perform(:ghost, q: 'cable')

    expect(component.received.to_a).to eq([[]])
  end

  it 'calls a stubbed action with what the method it stubs takes' do
    component = live_mount('action_arguments')
    allow(component.component).to receive(:none).and_call_original

    component.perform(:none, q: 'cable')

    expect(component.received.to_a).to eq([:none])
  end
end
