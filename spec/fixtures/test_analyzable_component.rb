# frozen_string_literal: true

# Test fixture component for MethodAnalyzer specs
class TestAnalyzableComponent
  def self.all_reactive_variables
    %i[username count todos]
  end

  # Simple method that accesses reactive variable
  def display_name
    username.upcase
  end

  def case_when_username
    case count.zero?
    when true
      username.downcase
    when false
      username.upcase
    else
      username
    end
  end

  # Method with reactive variable dependency
  def greeting
    "Hello #{username}"
  end

  # Method that calls another method
  def full_greeting
    "#{greeting}!"
  end

  # Method with multiple dependencies
  def summary
    "#{display_name}: count=#{count}"
  end

  # Method with no dependencies
  def static_message
    'Static'
  end

  # Method that depends on a reactive variable to test transitive deps
  def filtered_todos
    todos.select { |t| t[:active] }
  end
end
