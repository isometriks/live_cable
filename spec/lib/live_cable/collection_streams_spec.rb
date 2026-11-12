# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection stream declarations and verbs' do
  include LiveCable::Testing

  let(:message_class) do
    Class.new(Struct.new(:id, :body)) do
      include ActiveModel::Conversion
      extend ActiveModel::Naming

      def self.name = 'Message'

      def persisted? = !id.nil?
    end
  end

  let(:message) { message_class.new(42, 'hello') }

  def component_class(name = 'Live::Declared', &)
    Class.new(LiveCable::Component) do
      define_singleton_method(:name) { name }
      class_eval(&) if block_given?
    end
  end

  # Live::StreamFeed with more of a component's code, rendering its template
  def feed_class(&)
    Class.new(Live::StreamFeed) do
      def self.name = 'Live::StreamFeed'

      class_eval(&) if block_given?
    end
  end

  def ops(component, name = :messages)
    component.live_stream(name).ops
  end

  def locked(component, &)
    component.connection.synchronize(&)
  end

  describe 'stream' do
    it 'records the declaration' do
      initial = -> { [] }
      dom_id = ->(row) { "row-#{row.id}" }
      klass = component_class { stream :messages, initial, dom_id:, limit: 3 }

      expect(klass.collection_streams[:messages]).to have_attributes(
        name: :messages, initial:, dom_id:, limit: 3
      )
      expect(Live::StreamFeed.collection_streams.keys).to eq(%i[messages])
      expect(LiveCable::Component.collection_streams).to be_empty
    end

    it 'raises at class load for a bad name' do
      ['messages', :Messages, :'1st', :'new-messages', :messages?].each do |name|
        expect { component_class { stream name } }.to raise_error(
          ArgumentError,
          "Live::Declared can't declare stream #{name.inspect}: a stream's name is a Symbol of lowercase " \
          'letters, digits and underscores that starts with a letter or an underscore'
        )
      end
    end

    it 'raises at class load for an initial value or dom_id that is not a proc, or a bad limit' do
      expect { component_class { stream :messages, [] } }.to raise_error(
        ArgumentError, "Live::Declared can't declare stream :messages: its initial value must be a proc or nil, got []"
      )
      expect { component_class { stream :messages, dom_id: 'id' } }.to raise_error(
        ArgumentError, %(Live::Declared can't declare stream :messages: dom_id: must be a proc, got "id")
      )

      [0, -1, 2.5, '3'].each do |limit|
        expect { component_class { stream :messages, limit: } }.to raise_error(
          ArgumentError,
          "Live::Declared can't declare stream :messages: limit: must be a positive Integer or nil, " \
          "got #{limit.inspect}"
        )
      end
    end

    it 'raises at class load for a name declared twice, here or in a superclass' do
      expect { component_class { 2.times { stream :messages } } }.to raise_error(
        ArgumentError, "Live::Declared can't declare stream :messages: it is already declared"
      )
      expect { Class.new(Live::StreamFeed) { stream :messages } }.to raise_error(ArgumentError, /already declared/)
    end

    it 'raises at class load for a name taken by a reactive variable, a shared variable, a query or a method' do
      taken = {
        'a reactive variable' => -> { reactive :messages, -> { [] } },
        'a reactive variable ' => -> { reactive :messages, shared: true },
        'a shared variable' => -> { shared :messages },
        'a reactive_query' => -> { reactive_query :messages, -> {} },
        'a method (Live::Declared#messages)' => -> { private define_method(:messages) { nil } },
      }

      taken.each do |what, declaration|
        expect do
          component_class do
            instance_exec(&declaration)
            stream :messages
          end
        end.to raise_error(ArgumentError, "Live::Declared can't declare stream :messages: it is already #{what.strip}")
      end

      expect { component_class { stream :render } }.to raise_error(
        ArgumentError, "Live::Declared can't declare stream :render: it is already a method (LiveCable::Component::Rendering#render)"
      )
    end

    it 'leaves a name that only Kernel defines privately free' do
      klass = component_class { stream :select }

      expect(klass.collection_streams.keys).to eq(%i[select])
    end

    it "makes reactive, shared, reactive_query and def raise on a stream's name in turn" do
      declarations = {
        'declare reactive :messages' => -> { reactive :messages },
        'declare reactive :messages ' => -> { reactive :messages, shared: true },
        'declare shared :messages' => -> { shared :messages },
        'declare reactive_query :messages' => -> { reactive_query :messages, -> {} },
        'define #messages' => -> { define_method(:messages) { [] } },
      }

      declarations.each do |what, declaration|
        expect do
          component_class do
            stream :messages
            instance_exec(&declaration)
          end
        end.to raise_error(ArgumentError, "Live::Declared can't #{what.strip}: it is already a collection stream")
      end

      expect { Class.new(Live::StreamFeed) { attr_reader :messages } }.to raise_error(ArgumentError, /define #messages/)
    end
  end

  describe 'the reader' do
    it 'raises with how to render and change the stream' do
      feed = Live::StreamFeed.new('reader')
      guidance = '`Live::StreamFeed#messages` is a collection stream: it holds no rows, so it can\'t be read or ' \
                 'enumerated. Render it with `<%= live_stream_for :messages do |message| %>`, and change it with ' \
                 '`stream_insert`, `stream_update`, `stream_delete` or `stream_reset`'

      expect { feed.messages }.to raise_error(LiveCable::Error, guidance)
      expect { feed.messages.each { nil } }.to raise_error(LiveCable::Error, guidance)
      expect { feed.messages.size }.to raise_error(LiveCable::Error, guidance)
    end

    it 'names the row after the singular of the stream, or row' do
      klass = component_class { stream :news }

      expect { klass.new('x').news }.to raise_error(LiveCable::Error, /live_stream_for :news do \|row\|/)
    end

    it 'raises when a template reads the stream' do
      klass = feed_class { def heading = messages.size }

      expect { live_mount(klass) }.to raise_error(LiveCable::Error, /is a collection stream/)
    end
  end

  describe 'the verbs' do
    let(:feed) { live_mount('stream_feed') }

    it 'queue an op per call with the key computed then, in call order' do
      other = message_class.new(7, 'other')

      locked(feed) do
        feed.stream_insert(:messages, message)
        feed.stream_insert(:messages, other, at: :start)
        feed.stream_update(:messages, message)
        feed.stream_delete(:messages, other)
        feed.stream_delete(:messages, 'messages_message_1')
      end

      expect(ops(feed)).to eq([
        ['a', 'messages_message_42', message],
        ['p', 'messages_message_7', other],
        ['u', 'messages_message_42', message],
        %w[d messages_message_7],
        %w[d messages_message_1],
      ])
    end

    it 'return nil' do
      locked(feed) do
        expect(feed.stream_insert(:messages, message)).to be_nil
        expect(feed.stream_update(:messages, message)).to be_nil
        expect(feed.stream_delete(:messages, message)).to be_nil
        expect(feed.stream_reset(:messages)).to be_nil
      end
    end

    it 'drop the earlier ops on a reset and flag the stream for a refill' do
      locked(feed) do
        feed.stream_insert(:messages, message)
        feed.stream_reset(:messages)
        feed.stream_insert(:messages, message, at: :start)
      end

      expect(feed.live_stream(:messages)).to be_reset
      expect(ops(feed)).to eq([['p', 'messages_message_42', message]])
    end

    it 'raise ArgumentError for an at: other than :end or :start' do
      expect { locked(feed) { feed.stream_insert(:messages, message, at: :after) } }.to raise_error(
        ArgumentError, 'at: must be :end or :start, got :after'
      )
      expect(ops(feed)).to be_empty
    end

    it 'raise for a stream the component does not declare' do
      expect { locked(feed) { feed.stream_insert(:msgs, message) } }.to raise_error(
        LiveCable::Error, 'Live::StreamFeed has no stream :msgs (declared: :messages)'
      )
      expect { component_class.new('none').stream_reset(:msgs) }.to raise_error(
        LiveCable::Error, 'Live::Declared has no stream :msgs (declared: none)'
      )
    end

    it 'run from an action and a stream_from callback' do
      klass = feed_class do
        actions :add
        after_connect { stream_from('feed') { |id| stream_insert(:messages, Message.new(id, 'streamed')) } }

        def add(params) = stream_insert(:messages, Message.new(params[:id].to_i, 'added'))
      end
      stub_const('Message', message_class)
      feed = live_mount(klass)

      feed.perform(:add, id: 1)
      feed.receive_stream('feed', 2)

      expect(ops(feed).map { |op| op[0..1] }).to eq([%w[a messages_message_1], %w[a messages_message_2]])
    end

    it 'run from after_connect' do
      stub_const('Message', message_class)
      feed = live_mount(feed_class { after_connect { stream_insert(:messages, Message.new(3, 'early')) } })

      expect(ops(feed).map { |op| op[0..1] }).to eq([%w[a messages_message_3]])
    end
  end

  describe 'guards' do
    let(:feed) { live_mount('stream_feed') }

    it 'raise with no live connection, as on prerender' do
      component = Live::StreamFeed.new('prerender')
      needs = 'needs a live connection: call it from an action, a `stream_from` callback or `after_connect`; ' \
              "for the first page, return the rows from the stream's initial lambda"

      expect { component.stream_insert(:messages, message) }.to raise_error(
        LiveCable::Error, "Live::StreamFeed#stream_insert #{needs}"
      )
      expect { component.stream_reset(:messages) }.to raise_error(LiveCable::Error, /#stream_reset needs a live/)
      expect { component.live_update { nil } }.to raise_error(LiveCable::Error, /#live_update needs a live/)
    end

    it 'raise after the component disconnects' do
      component = feed.component
      feed.unmount

      expect { component.stream_delete(:messages, message) }.to raise_error(LiveCable::Error, /needs a live connection/)
      expect { component.live_update { nil } }.to raise_error(LiveCable::Error, /needs a live connection/)
    end

    it 'raise outside the connection lock' do
      expect { feed.stream_update(:messages, message) }.to raise_error(
        LiveCable::Error,
        'Live::StreamFeed#stream_update was called outside the connection lock: wrap it in `live_update { … }`'
      )
      expect(ops(feed)).to be_empty
    end

    it 'raise outside the lock on a thread of its own while another thread holds it' do
      error = nil
      locked(feed) do
        Thread.new do
          feed.stream_insert(:messages, message)
        rescue LiveCable::Error => e
          error = e
        end.join
      end

      expect(error.message).to include('outside the connection lock')
    end

    it 'raise while rendering, in render callbacks, templates and helpers' do
      inserting = feed_class { before_render { stream_insert(:messages, Message.new(1, 'x')) } }
      stub_const('Message', message_class)

      expect { live_mount(inserting) }.to raise_error(
        LiveCable::Error,
        'Live::StreamFeed#stream_insert was called while rendering: queue stream changes in the action or callback'
      )
      expect { live_mount(feed_class { after_render { stream_reset(:messages) } }) }.to raise_error(
        LiveCable::Error, /#stream_reset was called while rendering/
      )
      expect { live_mount(feed_class { def heading = stream_reset(:messages) }) }.to raise_error(
        LiveCable::Error, /#stream_reset was called while rendering/
      )
      expect { live_mount(feed_class { before_render { live_update { nil } } }) }.to raise_error(
        LiveCable::Error, /#live_update was called while rendering/
      )
    end

    it 'raise while another component on the connection renders' do
      feed
      host = feed_class do
        before_render { live_connection.get_component('stream_feed/test').stream_reset(:messages) }
      end

      expect { live_mount(host, id: 'host', connection: feed.connection) }.to raise_error(
        LiveCable::Error, /#stream_reset was called while rendering/
      )
    end

    it 'leave the stream as it was' do
      expect { feed.stream_insert(:messages, message) }.to raise_error(LiveCable::Error)

      expect(feed.live_stream(:messages)).to have_attributes(ops: [], reset?: false)
    end
  end

  describe 'live_update' do
    let(:feed) { live_mount('stream_feed') }

    it 'runs the block under the connection lock, then sends what changed' do
      feed.clear_broadcasts

      result = feed.live_update do
        feed.stream_insert(:messages, message)
        feed.title = 'Updated'
        feed.connection.synchronized?
      end

      expect(result).to be(true)
      expect(feed.broadcasts(:_refresh).size).to eq(1)
      expect(feed.rendered).to have_css('[data-testid="title"]', text: 'Updated')
      expect(ops(feed).map(&:first)).to eq(%w[a])
    end

    it 'only runs the block when nested inside a lock holder, so an action sends one frame' do
      klass = feed_class do
        actions :retitle

        def retitle(params)
          live_update { self.title = params[:title] }
          self.title = "#{title}!"
        end
      end
      feed = live_mount(klass)
      feed.clear_broadcasts

      feed.perform(:retitle, title: 'Nested')

      expect(feed.broadcasts.size).to eq(1)
      expect(feed.broadcasts(:_refresh).first[:_reply]).to be(true)
      expect(feed.rendered).to have_css('[data-testid="title"]', text: 'Nested!')
    end

    it "lets the block's error through and sends nothing" do
      feed.clear_broadcasts

      expect do
        feed.live_update do
          feed.title = 'Lost'
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')
      expect(feed.broadcasts).to be_empty
    end

    it 'checks the connection again once it holds the lock' do
      component = feed.component
      holding = Queue.new
      release = Queue.new
      holder = Thread.new do
        feed.connection.synchronize do
          holding << true
          release.pop
          feed.connection.disconnect_component(component)
        end
      end
      holding.pop

      waiting = Thread.new do
        Thread.current.report_on_exception = false
        component.live_update { :ran }
      end
      Thread.pass until waiting.status == 'sleep'
      release << true
      holder.join

      expect { waiting.value }.to raise_error(LiveCable::Error, /#live_update needs a live connection/)
    end
  end

  describe 'keys' do
    def feed_with(dom_id)
      live_mount(feed_class { stream :notes, dom_id: })
    end

    it 'default to dom_id(row, name)' do
      feed = live_mount('stream_feed')

      expect(feed.live_stream(:messages).key_for(message)).to eq('messages_message_42')
    end

    it 'come from dom_id:, run on the component, which has dom_id and dom_class privately' do
      feed = feed_with(->(row) { "#{dom_class(row)}-#{dom_id(row)}-#{title}" })

      expect(feed.live_stream(:notes).key_for(message)).to eq('message-message_42-Feed')
      expect(feed.component).not_to respond_to(:dom_id)
      expect(feed.component).not_to respond_to(:dom_class)
      expect(LiveCable::Component.private_method_defined?(:dom_id)).to be(false)
    end

    it 'raise for a dom_id: result that is not a String with no whitespace' do
      [nil, '', ' ', 'two words', :message, 42].each do |key|
        feed = feed_with(->(_row) { key })

        expect { locked(feed) { feed.stream_insert(:notes, message) } }.to raise_error(
          LiveCable::Error,
          "stream :notes: dom id #{key.inspect} is invalid: a row's dom id is its key and its element's id, " \
          'so it must be a non-empty String with no whitespace'
        )
      end
    end

    it 'raise for a String key to delete that is invalid' do
      feed = live_mount('stream_feed')

      expect { locked(feed) { feed.stream_delete(:messages, 'two words') } }.to raise_error(
        LiveCable::Error, /dom id "two words" is invalid/
      )
    end

    it 'raise with a dom_id: hint for a row the default dom_id cannot identify' do
      feed = live_mount('stream_feed')

      expect { locked(feed) { feed.stream_insert(:messages, Object.new) } }.to raise_error(
        LiveCable::Error,
        'stream :messages: the default dom id needs a model with to_key, and Object has none. ' \
        'Declare `stream :messages, dom_id: ->(message) { … }`'
      )
      expect { locked(feed) { feed.stream_insert(:messages, message_class.new(nil, 'unsaved')) } }.to raise_error(
        LiveCable::Error,
        'stream :messages: Message has no id yet, so the default dom id would be the same for every unsaved ' \
        'row. Save it first, or declare `stream :messages, dom_id: ->(message) { … }`'
      )
    end

    it 'raise in the action, where rescue_from sees them' do
      klass = feed_class do
        actions :add
        rescue_from(LiveCable::Error) { |error| self.title = error.message[0, 20] }

        def add = stream_insert(:messages, Object.new)
      end
      feed = live_mount(klass)

      feed.perform(:add)

      expect(feed.broadcasts(:_error)).to be_empty
      expect(feed.rendered).to have_css('[data-testid="title"]', text: 'stream :messages: th')
    end
  end

  describe 'the 1,000-op collapse' do
    let(:connection) { live_mount('stream_feed').connection }

    def unsubscribed_feed
      Live::StreamFeed.new('waiting').tap { |feed| connection.add_component(feed) }
    end

    it 'turns an unsubscribed component past 1,000 ops into a refill, with one warning' do
      feed = unsubscribed_feed
      LiveCable.instance_variable_set(:@warned_messages, Set.new)
      allow(LiveCable.logger).to receive(:warn)

      connection.synchronize do
        1_000.times { |id| feed.stream_insert(:messages, message_class.new(id + 1, 'm')) }
        expect(feed.live_stream(:messages).ops.size).to eq(1_000)

        3.times { |id| feed.stream_insert(:messages, message_class.new(id + 1_001, 'm')) }
      end

      expect(feed.live_stream(:messages)).to have_attributes(ops: [], reset?: true, collapsed?: true)
      expect(LiveCable.logger).to have_received(:warn).with(
        '[LiveCable] stream :messages of stream_feed/waiting queued 1000 ops before Live::StreamFeed subscribed, ' \
        'so they were dropped: it refills from its initial lambda when it renders'
      ).once
    end

    it 'still checks keys while collapsed, and a reset starts a new queue' do
      feed = unsubscribed_feed
      allow(LiveCable.logger).to receive(:warn)

      connection.synchronize do
        1_001.times { |id| feed.stream_insert(:messages, message_class.new(id + 1, 'm')) }

        expect { feed.stream_insert(:messages, Object.new) }.to raise_error(LiveCable::Error, /to_key/)

        feed.stream_reset(:messages)
        feed.stream_insert(:messages, message)
      end

      expect(feed.live_stream(:messages)).to have_attributes(reset?: true, collapsed?: false)
      expect(feed.live_stream(:messages).ops.map(&:first)).to eq(%w[a])
    end

    it 'never collapses a subscribed component' do
      feed = live_mount('stream_feed')

      locked(feed) { 1_500.times { |id| feed.stream_insert(:messages, message_class.new(id + 1, 'm')) } }

      expect(feed.live_stream(:messages)).to have_attributes(reset?: false, collapsed?: false)
      expect(ops(feed).size).to eq(1_500)
    end
  end

  describe 'a component with a plain .html.erb template' do
    let(:klass) do
      Class.new(Live::PlainErb) do
        def self.name = 'Live::PlainErb'

        stream :messages
      end
    end

    it 'raises at render, over the socket and on prerender' do
      error = 'Live::PlainErb declares collection streams, which need a .live.erb template, but live/plain_erb ' \
              'rendered another kind: rename it to live/plain_erb.html.live.erb'

      expect { live_mount(klass) }.to raise_error(LiveCable::Error, error)
      expect { ApplicationController.renderer.render(klass.new('page'), layout: false) }.to raise_error(
        LiveCable::Error, error
      )
    end
  end
end
