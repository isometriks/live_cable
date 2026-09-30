# frozen_string_literal: true

module LiveCable
  # A message asked for an action or reactive write the component doesn't
  # expose. Never offered to rescue_from.
  class Forbidden < Error; end
end
