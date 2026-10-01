# frozen_string_literal: true

module LiveCable
  module Rendering
    # Appends to whichever buffer the view is writing to when the append happens,
    # so a template block a view helper yields lands where plain ERB would put it.
    class ViewBuffer
      delegate :safe_append=, :append=, :safe_expr_append=, to: :output_buffer

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
