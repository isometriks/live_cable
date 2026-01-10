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
          raise 'You must have a single top level HTML element in your template'
        end

        component_node = root_elements.first
        component_node.open_tag.children.push(
          create_attribute('data-live-component-value', create_erb_node('component.class.component_string')),
          create_attribute('data-live-id-value', create_erb_node('component.id'))
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

        attributes.each do |attribute, name, value|
          # Check for event bindings
          if (match = name.match(event_pattern))
            add_action_attributes(node, match[1], value)
            node.open_tag.children.delete(attribute)
          # Check for live-value bindings
          elsif (match = name.match(value_pattern))
            add_action_value_attributes(node, match[1], value)
            node.open_tag.children.delete(attribute)
          # Check for live-reactive bindings
          elsif (match = name.match(reactive_pattern))
            add_reactive_attributes(node, match[1])
            node.open_tag.children.delete(attribute)
          # Check for live-debounce
          elsif name.match(debounce_pattern)
            add_debounce_attributes(node, value)
            node.open_tag.children.delete(attribute)
          end
        end

        super
      end

      private

      # data-action='input->live#call' data-live-action-param='search'
      def add_action_attributes(node, event, action)
        append_to_attribute(node, 'data-action', "#{event}->live#call")
        node.open_tag.children.push(
          create_attribute('data-live-action-param', action)
        )
      end

      def add_action_value_attributes(node, param_name, value)
        node.open_tag.children.push(
          create_attribute("data-live-#{param_name}-param", value)
        )
      end

      def add_reactive_attributes(node, event)
        action = event ? "#{event}->live#reactive" : 'live#reactive'
        append_to_attribute(node, 'data-action', action)
      end

      def append_to_attribute(node, attr_name, value)
        existing_attr = attributes_for_node(node).find do |attr|
          attr.name.children.any? { |child| child.content == attr_name }
        end

        unless existing_attr
          # Create new attribute
          node.open_tag.children.push(
            create_attribute(attr_name, value)
          )

          return
        end

        # Append to existing attribute value
        space_literal = ::Herb::AST::LiteralNode.new('LiteralNode', dummy_location, [], ' ')
        value_node = value

        if value.is_a?(String)
          value_node = ::Herb::AST::LiteralNode.new('LiteralNode', dummy_location, [], value)
        end

        existing_attr.value.children.push(space_literal, value_node)
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
        name_literal = ::Herb::AST::LiteralNode.new('LiteralNode', dummy_location, [], name.dup)
        name_node = ::Herb::AST::HTMLAttributeNameNode.new('HTMLAttributeNameNode', dummy_location, [], [name_literal])
        value = value.dup

        if value.is_a?(String)
          value_literal = ::Herb::AST::LiteralNode.new('LiteralNode', dummy_location, [], value)
          value = ::Herb::AST::HTMLAttributeValueNode.new(
            'HTMLAttributeValueNode',
            dummy_location,
            [],
            create_token(:quote, '"'),
            [value_literal],
            create_token(:quote, '"'),
            true
          )
        end

        equals_token = create_token(:equals, '=')

        ::Herb::AST::HTMLAttributeNode.new('HTMLAttributeNode', dummy_location, [], name_node, equals_token, value)
      end

      def create_erb_node(source)
        node = ::Herb::AST::ERBContentNode.new(
          'ERBContentNode',
          dummy_location,
          [],
          create_token(:erb_start, '<%='),
          create_token(:erb_content, source),
          create_token(:erb_end, '%>'),
          nil,
          false,
          false
        )

        ::Herb::AST::HTMLAttributeValueNode.new('HTMLAttributeValueNode', dummy_location, [], create_token(:quote, '"'),
          [node], create_token(:quote, '"'), true)
      end

      def dummy_location
        @dummy_location ||= ::Herb::Location.from(0, 0, 0, 0)
      end

      def dummy_range
        @dummy_range ||= ::Herb::Range.from(0, 0)
      end

      def create_token(type, value)
        ::Herb::Token.new(value.dup, dummy_range, dummy_location, type.to_s)
      end
    end
  end
end
