# frozen_string_literal: true

module LiveCable
  module Rendering
    class Handler < ActionView::Template::Handlers::ERB
      def call(template, source)
        return LivePartials.refusal(template) if LivePartials.partial?(template)

        parse_result = ::Herb.parse(source, track_whitespace: true)
        ast = parse_result.value

        live_partials = LivePartials::Inliner.for(template)
        engine = Renderer.new(template.short_identifier, template.virtual_path, live_partials:)
        compiler = Compiler.new(engine, live_partials:)
        ast.accept(compiler)

        compiler.generate_output
        engine.src
      end
    end
  end
end
