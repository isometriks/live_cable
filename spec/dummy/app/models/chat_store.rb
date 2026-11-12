# frozen_string_literal: true

# Chat messages kept in memory, standing in for a model whose after_commit
# callbacks broadcast { event:, id: } to the chat's subscribers
class ChatStore
  CHANNEL = 'chat'

  Message = Data.define(:id, :author, :body, :likes)

  @lock = Mutex.new

  class << self
    def reset!
      @lock.synchronize do
        @messages = {}
        @last_id = 0
      end
    end

    def all = @lock.synchronize { @messages.values }

    def find(id) = @lock.synchronize { @messages[id.to_i] }

    def add(body, author: 'Ann', publish: true)
      message = @lock.synchronize do
        @last_id += 1
        @messages[@last_id] = Message.new(id: @last_id, author:, body:, likes: 0)
      end

      publish('created', message.id) if publish
      message
    end

    def like(id)
      message = @lock.synchronize do
        @messages[id.to_i] &&= @messages[id.to_i].with(likes: @messages[id.to_i].likes + 1)
      end

      publish('updated', message.id) if message
      message
    end

    def delete(id, publish: true)
      publish('deleted', id.to_i) if @lock.synchronize { @messages.delete(id.to_i) } && publish
    end

    def publish(event, id) = ActionCable.server.broadcast(CHANNEL, { event:, id: })
  end

  reset!
end
