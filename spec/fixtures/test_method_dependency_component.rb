# frozen_string_literal: true

# Test fixture for MethodDependencyVisitor specs
class TestMethodDependencyComponent
  def self.all_reactive_variables
    %i[username count]
  end

  # Method with implicit self call
  def implicit_self_call
    filtered_todos.each { |t| puts t }
  end

  # Method with explicit self call
  def explicit_self_call
    self.filtered_todos.each { |t| puts t } # rubocop:disable Style/RedundantSelf
  end

  # Method with variable receiver call (should NOT be tracked)
  def variable_receiver_call(component)
    component.filtered_todos.each { |t| puts t }
  end

  # Method with reactive variable
  def uses_reactive_var
    "Hello #{username}"
  end

  # Method with mixed calls
  def mixed_calls
    helper_method
    username
    count
  end

  def filtered_todos
    []
  end

  def helper_method
    'help'
  end
end
