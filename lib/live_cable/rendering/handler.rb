# frozen_string_literal: true

module LiveCable
  module Rendering
    class Handler < ActionView::Template::Handlers::ERB
      def call(template, source)
        Renderer.
          new(source, visitors: [AttributesVisitor.new]).
          src
      end
    end
  end
end
