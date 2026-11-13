# frozen_string_literal: true

module LiveCable
  module Rendering
    # A .live.erb template that can't compile. The message names the file,
    # the line and the fix.
    class CompileError < LiveCable::Error; end
  end
end
