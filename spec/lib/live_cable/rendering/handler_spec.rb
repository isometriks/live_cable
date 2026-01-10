# frozen_string_literal: true

require 'spec_helper'
require 'action_view'

RSpec.describe LiveCable::Rendering::Handler do
  let(:source) { raise NotImplementedError }
  let(:locals) { {} }
  let(:component) do
    Class.new(LiveCable::Component) do
      actions :action
      reactive :reactive
      reactive :reactive_shared, shared: true
      shared :shared

      def self.name
        'Live::TestComponent'
      end
    end.new('test-id')
  end
  let(:local_assigns) { locals.merge(component:) }
  let(:output) do
    handler = described_class.new
    src = handler.call(nil, source)
    m = Class.new
    locals_code = local_assigns.map { |k, v| "#{k} = local_assigns[:#{k}]" }.join("\n")
    method_definition = %(
      def render(local_assigns, output_buffer)
        @output_buffer = output_buffer
        #{locals_code}
        #{src}
      end
    )

    m.instance_eval(method_definition, __FILE__, __LINE__ + 1)
    m.render(local_assigns, ActionView::OutputBuffer.new).to_s
  end

  context 'with invalid template' do
    let(:source) { '<div>Hello</div><div>World</div>' }

    it 'throw error without single root element' do
      expect { output }.to raise_error('You must have a single top level HTML element in your template')
    end
  end

  context 'with simple template' do
    let(:source) { '<div>Hello</div>' }

    it 'adds stimulus controller to element' do
      expect(output).to eq(
        '<div data-live-component-value="test_component" data-live-id-value="test-id" ' \
             'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
             'data-live-defaults-value="{}" ' \
             'data-controller="live">Hello</div>'
      )
    end
  end

  context 'with another stimulus controller on root' do
    let(:source) { '<div data-controller="other">Hello</div>' }

    it 'appends stimulus controller to existing one' do
      expect(output).to eq(
        '<div data-controller="other live" data-live-component-value="test_component" ' \
             'data-live-id-value="test-id" data-live-actions-value="[&quot;action&quot;]" ' \
             'data-live-status-value="disconnected" data-live-defaults-value="{}">Hello</div>'
      )
    end
  end

  context 'with 2 different live actions' do
    let(:source) { '<div live-click="click" live-blur="blur">Hello</div>' }

    it 'appends both to data-action and calls the correct action' do
      expect(output).to eq(
        '<div data-live-component-value="test_component" data-live-id-value="test-id" ' \
             'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
             'data-live-defaults-value="{}" data-controller="live" ' \
             'data-action="click->live#action_$click blur->live#action_$blur">Hello</div>'
      )
    end
  end

  context 'when action contains erb' do
    let(:source) { '<div live-click="<%= "click" %>">Hello</div>' }

    it 'moves the erb node into the data-action attribute' do
      expect(output).to eq(
        '<div data-live-component-value="test_component" data-live-id-value="test-id" ' \
             'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
             'data-live-defaults-value="{}" data-controller="live" ' \
             'data-action="click->live#action_$click">Hello</div>'
      )
    end
  end

  context 'with live params' do
    let(:source) { '<div live-value-counter="5" live-value-increment="-1">Hello</div>' }

    it 'adds stimulus params' do
      expect(output).to eq(
        '<div data-live-component-value="test_component" data-live-id-value="test-id" ' \
             'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
             'data-live-defaults-value="{}" data-controller="live" ' \
             'data-live-counter-param="5" data-live-increment-param="-1">Hello</div>'
      )
    end
  end

  context 'with live form' do
    let(:source) { '<form live-form="form">Hello</form>' }

    it 'adds stimulus params' do
      expect(output).to eq(
        '<form data-live-component-value="test_component" data-live-id-value="test-id" ' \
              'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
              'data-live-defaults-value="{}" data-controller="live" ' \
              'data-action="submit->live#form_$form:prevent">Hello</form>'
      )
    end
  end

  context 'with live form erb action' do
    let(:source) { '<form live-form="<%= "form" %>">Hello</form>' }

    it 'adds stimulus params' do
      expect(output).to eq(
        '<form data-live-component-value="test_component" data-live-id-value="test-id" ' \
          'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
          'data-live-defaults-value="{}" data-controller="live" ' \
          'data-action="submit->live#form_$form:prevent">Hello</form>'
      )
    end
  end

  context 'with form and action' do
    let(:source) { '<form live-form="form" live-click="click">Hello</form>' }

    it 'adds both actions to data-action' do
      expect(output).to eq(
        '<form data-live-component-value="test_component" data-live-id-value="test-id" ' \
              'data-live-actions-value="[&quot;action&quot;]" data-live-status-value="disconnected" ' \
              'data-live-defaults-value="{}" data-controller="live" ' \
              'data-action="submit->live#form_$form:prevent click->live#action_$click">Hello</form>'
      )
    end
  end
end
