# frozen_string_literal: true

# Test fixture for MethodAnalyzer specs: other defs in the same file that
# share names with the component's instance methods
module TestSameFileHelpers
  def helper_label
    "helper=#{count}"
  end
end

class TestSameFileMethodsComponent < LiveCable::Component
  include TestSameFileHelpers

  reactive :count, -> { 0 }

  def title
    "title=#{count}"
  end

  def label
    "label=#{count}"
  end

  def summary
    "summary=#{count}"
  end

  def heading
    "heading=#{count}"
  end

  def caption
    "caption=#{count}"
  end

  def helper_title
    helper_label
  end

  def self.title
    'class-level'
  end

  def self.registry_name
    count
  end

  class << self
    def label
      'class-level'
    end

    def class_only_label
      count
    end
  end

  Row = Struct.new(:value) do
    def summary
      value.to_s
    end
  end

  class Item
    def heading
      'item'
    end
  end
end

class TestSameFileOtherComponent
  def caption
    'other'
  end
end
