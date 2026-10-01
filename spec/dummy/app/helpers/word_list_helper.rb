# frozen_string_literal: true

module WordListHelper
  def word_list(&)
    [].tap { it.instance_exec(&) }.join(', ')
  end
end
