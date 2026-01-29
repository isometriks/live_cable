# frozen_string_literal: true

module LiveCable
  module Rendering
    class Handler < ActionView::Template::Handlers::ERB
      def call(template, source)
        parse_result = ::Herb.parse(source, track_whitespace: true)
        ast = parse_result.value

        engine = Renderer.new
        compiler = Compiler.new(engine)
        ast.accept(compiler)

        compiler.generate_output
        engine.src
      end
    end
  end
end
