# frozen_string_literal: true

module LiveCable
  module Rendering
    # A template's buffer: stands in for whichever buffer the view is writing to at
    # that moment, so a block lands wherever its caller yields it, as in plain ERB.
    class ViewBuffer
      delegate :safe_append=, :append=, :safe_expr_append=, to: :output_buffer
      delegate_missing_to :output_buffer

      def initialize(view_context)
        @view_context = view_context
      end

      private

      def output_buffer
        @view_context.output_buffer
      end
    end
  end
end
