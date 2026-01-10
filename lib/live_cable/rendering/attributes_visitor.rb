# frozen_string_literal: true

module LiveCable
  module Rendering
    class AttributesVisitor < ::Herb::Visitor
      EVENTS = %w[
        blur
        click
        change
        focus
        input
        keydown
        keyup
        submit
      ].freeze

      def visit_document_node(doc)
        root_elements = doc.children.select do |node|
          node.is_a?(::Herb::AST::HTMLElementNode)
        end

        if root_elements.size != 1
          raise LiveCable::Error, 'You must have a single top level HTML element in your template'
        end

        component_node = root_elements.first
        component_node.open_tag.children.push(
          create_attribute('data-live-component-value', create_erb_node('component.class.component_string')),
          create_attribute('data-live-id-value', create_erb_node('component.id')),
          create_attribute('data-live-actions-value', create_erb_node('component.class.allowed_actions.to_json')),
          create_attribute('data-live-status-value', create_erb_node('component.status')),
          create_attribute(
            'data-live-defaults-value',
            create_erb_node('component.live_connection ? "{}" : component.defaults.to_json')
          )
        )

        append_to_attribute(component_node, 'data-controller', 'live')

        super
      end

      def visit_html_element_node(node)
        attributes = live_attributes(node)

        super and return unless attributes.any?

        event_pattern = /^live-((?:#{EVENTS.join('|')})(?:\..+)?)$/
        value_pattern = /^live-value-(.+)$/
        reactive_pattern = /^live-reactive(?:-(.+))?$/
        debounce_pattern = /^live-debounce$/
        form_pattern = /^live-form(?:-(.+))?$/

        attributes.each do |attribute, name, value|
          case name
          when event_pattern
            add_action_attributes(node, ::Regexp.last_match[1], value)
          when value_pattern
            add_action_value_attributes(node, ::Regexp.last_match[1], value)
          when reactive_pattern
            add_reactive_attributes(node, ::Regexp.last_match[1])
          when debounce_pattern
            add_debounce_attributes(node, value)
          when form_pattern
            add_form_attributes(node, ::Regexp.last_match[1], value)
          else
            next
          end

          node.open_tag.children.delete(attribute)
        end

        super
      end

      private

      # data-action='input->live#action_$search'
      def add_action_attributes(node, event, action)
        append_to_attribute(node, 'data-action', "#{event}->live#action_$")
        append_to_attribute(node, 'data-action', remove_quote_literals(action), add_space: false)
      end

      # data-live-counter-param="5"
      def add_action_value_attributes(node, param_name, value)
        node.open_tag.children.push(
          create_attribute("data-live-#{param_name}-param", value)
        )
      end

      def add_reactive_attributes(node, event)
        action = event ? "#{event}->live#reactive" : 'live#reactive'
        append_to_attribute(node, 'data-action', action)
      end

      def add_form_attributes(node, event, action)
        append_to_attribute(node, 'data-action', "#{event || 'submit'}->live#form_$")
        append_to_attribute(node, 'data-action', remove_quote_literals(action), add_space: false)
        append_to_attribute(node, 'data-action', ':prevent', add_space: false)
      end

      def append_to_attribute(node, attr_name, value, add_space: true)
        existing_attr = attributes_for_node(node).find do |attr|
          attr.name.children.any? { |child| child.content == attr_name }
        end

        unless existing_attr
          node.open_tag.children.push(create_attribute(attr_name, value))
          return
        end

        # Append to existing attribute value
        existing_attr.value.children.push(
          *([create_literal(' ')] if add_space),
          value.is_a?(String) ? create_literal(value) : value
        )
      end

      def add_debounce_attributes(node, value)
        node.open_tag.children.push(
          create_attribute('data-live-debounce-param', value)
        )
      end

      def attributes_for_node(node)
        node.open_tag.children.select { it.is_a?(::Herb::AST::HTMLAttributeNode) }
      end

      def live_attributes(node)
        attributes_for_node(node).filter_map do |attribute|
          name = attribute.name.children.detect do |child|
            child.content.is_a?(String) && child.content.downcase.start_with?('live-')
          end

          [attribute, name.content, attribute.value] if name
        end
      end

      def create_attribute(name, value)
        name_node = ::Herb::AST::HTMLAttributeNameNode.new(
          'HTMLAttributeNameNode', dummy_location, [], [create_literal(name)]
        )
        value_node = value.is_a?(String) ? create_attribute_value(value) : value.dup

        ::Herb::AST::HTMLAttributeNode.new(
          'HTMLAttributeNode', dummy_location, [], name_node, create_token(:equals, '='), value_node
        )
      end

      def create_erb_node(source)
        erb_node = ::Herb::AST::ERBContentNode.new(
          'ERBContentNode', dummy_location, [],
          create_token(:erb_start, '<%='),
          create_token(:erb_content, source),
          create_token(:erb_end, '%>'),
          nil, false, false
        )

        create_attribute_value(erb_node)
      end

      def create_attribute_value(content)
        content_array = content.is_a?(String) ? [create_literal(content)] : [content]
        ::Herb::AST::HTMLAttributeValueNode.new(
          'HTMLAttributeValueNode', dummy_location, [],
          create_token(:quote, '"'), content_array, create_token(:quote, '"'), true
        )
      end

      def create_literal(value)
        ::Herb::AST::LiteralNode.new('LiteralNode', dummy_location, [], value.dup)
      end

      def remove_quote_literals(node)
        node.children.detect do |child|
          !(child.is_a?(::Herb::AST::LiteralNode) && %w[' "].include?(child.content))
        end
      end

      def create_token(type, value)
        ::Herb::Token.new(value.dup, dummy_range, dummy_location, type.to_s)
      end

      def dummy_location
        @dummy_location ||= ::Herb::Location.from(0, 0, 0, 0)
      end

      def dummy_range
        @dummy_range ||= ::Herb::Range.from(0, 0)
      end
    end
  end
end
