# frozen_string_literal: true

module Live
  class Recursive < LiveCable::Component
    reactive :expanded, -> { false }
    reactive :depth, -> { 0 }
    reactive :label, -> { 'Root' }

    actions :toggle

    def toggle
      self.expanded = !expanded
    end

    def show_child?
      expanded && depth < 5 # Limit recursion depth to prevent infinite nesting
    end

    def child_depth
      depth + 1
    end

    def child_label
      "#{label}.#{child_depth}"
    end
  end
end
