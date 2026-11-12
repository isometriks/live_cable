# frozen_string_literal: true

# A message kept in memory, standing in for a model the stream specs query
class ChatMessage
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :id, :body, :author, :pinned

  def initialize(id:, body:, author: 'Ann', pinned: false)
    @id = id
    @body = body
    @author = author
    @pinned = pinned
  end

  def persisted? = true

  class << self
    # @return [Array<ChatMessage>] what the next query returns
    attr_accessor :rows

    # @return [Integer] how many queries ran
    attr_accessor :queries

    # @return [Array<ChatMessage>] notices, which aren't counted as queries
    attr_accessor :notices

    def reset!
      self.rows = []
      self.notices = []
      self.queries = 0
    end

    def recent
      self.queries += 1
      rows.dup
    end
  end

  reset!
end
