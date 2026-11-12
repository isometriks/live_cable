# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendering collection streams' do
  include LiveCable::Testing

  before { ChatMessage.reset! }

  def tree = LiveCable::Rendering::Tree

  def message(id, body = "Message #{id}", **)
    ChatMessage.new(id:, body:, **)
  end

  def key(id) = "messages_chat_message_#{id}"

  def chat_class(name = 'Live::Streams::Chat', &)
    Class.new(Live::Streams::Chat) do
      define_singleton_method(:name) { name }
      class_eval(&) if block_given?
    end
  end

  def mount_chat(*ids, **)
    ChatMessage.rows = ids.map { |id| message(id) }
    live_mount('streams/chat', **)
  end

  def stream_meta(component, name = :messages)
    component.rendered_stream(name).last
  end

  def frames(component)
    component.broadcasts(:_refresh).map { |frame| frame[:_refresh].as_json }
  end

  def last_frame(component) = frames(component).last

  # The parts a frame changed, by index
  def changed_parts(frame)
    frame['p'].each_with_index.reject { |part, _| part.nil? }.to_h(&:reverse)
  end

  def op_diff(component, ops, name = :messages)
    meta = stream_meta(component, name)
    { meta.part => tree.path_diff(meta.path, { 'o' => ops }) }
  end

  def tracked_nodes(component)
    tracker_states(component).flat_map { |state| state.nodes.values }
  end

  def unwrapped(component)
    component.is_a?(LiveCable::Testing::TestComponent) ? component.component : component
  end

  def tracker_states(component)
    unwrapped(component).send(:tree_tracker).instance_variable_get(:@states).values
  end

  def texts(component, selector = 'ul.messages li')
    component.rendered.all(selector).map(&:text)
  end

  # Records the template's part methods that run
  def part_calls(component)
    calls = []
    renderer_class = unwrapped(component).instance_variable_get(:@live_template).send(:renderer_class)

    renderer_class.instance_methods(false).grep(/\Arender_part_/).each do |method|
      allow_any_instance_of(renderer_class).to receive(method).and_wrap_original do |original, *args|
        calls << method
        original.call(*args)
      end
    end

    calls
  end

  describe 'on prerender' do
    it 'renders the initial rows inline, with their ids, as the socket renders them' do
      ChatMessage.rows = [message(1, 'one'), message(2, 'two', pinned: true)]

      html = Capybara.string(Live::Streams::Chat.new('page').render)
      chat = live_mount('streams/chat')

      expect(html.all('ul.messages li').map { |row| row[:id] }).to eq([key(1), key(2)])
      expect(html.find('ul.messages').native.inner_html).to eq(chat.rendered.find('ul.messages').native.inner_html)
      expect(html).to have_css("##{key(2)} b", text: 'pinned')
      expect(ChatMessage.queries).to eq(2)
    end
  end

  describe 'the first live render' do
    it 'sends the whole stream node with its name, folding in ops queued in after_connect' do
      ChatMessage.rows = [message(1, 'one')]
      klass = chat_class { after_connect { stream_insert(:messages, ChatMessage.new(id: 2, body: 'early')) } }
      chat = live_mount(klass)
      meta = stream_meta(chat)

      node = tree.node_at(frames(chat).first['p'][meta.part], meta.path)

      expect(node).to include('t' => meta.scope, 'st' => 'messages', 'k' => [key(1), key(2)], 'ik' => 1)
      expect(node['r'].map { |row| row[0..1] }).to eq([%w[Ann one], %w[Ann early]])
      expect(chat.live_stream(:messages)).not_to be_ops
    end

    it 'keeps a placeholder where the stream is, and no rows' do
      chat = mount_chat(1, 2)
      meta = stream_meta(chat)

      expect(tree.node_at(tracker_states(chat).first.nodes[meta.part], meta.path)).to eq(
        't' => meta.scope, 'st' => 'messages', 'r' => [], 'k' => []
      )
      expect(tracked_nodes(chat).to_json).not_to include(key(1))
    end
  end

  describe 'ops' do
    it 'send one frame with only the stream changed, from an action, without running part code' do
      chat = mount_chat(1)
      calls = part_calls(chat)
      chat.clear_broadcasts

      chat.perform(:add, id: 2, body: 'two')

      expect(frames(chat).size).to eq(1)
      row = ['Ann', 'two', { 't' => nil }]
      expect(changed_parts(last_frame(chat))).to eq(op_diff(chat, [['a', key(2), row]]))
      expect(calls).to be_empty
      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
    end

    it 'send prepends, updates and deletes from a stream_from callback and live_update' do
      chat = mount_chat(1, 2)
      calls = part_calls(chat)
      chat.clear_broadcasts

      chat.receive_stream('chat', 3)
      chat.live_update { chat.stream_insert(:messages, message(0, 'zero'), at: :start) }
      chat.live_update { chat.stream_update(:messages, message(1, 'one, edited')) }
      chat.live_update { chat.stream_delete(:messages, key(2)) }

      expect(frames(chat).size).to eq(4)
      expect(frames(chat).map { |frame| changed_parts(frame).keys }).to all(eq([stream_meta(chat).part]))
      expect(chat.stream_ops(:messages).map { |op| op[0..1] }).to eq(
        [['a', key(3)], ['p', key(0)], ['u', key(1)], ['d', key(2)]]
      )
      expect(texts(chat)).to eq(['Ann zero', 'Ann one, edited', 'Ann streamed'])
      expect(calls).to be_empty
    end

    it 'land at the output index of their part in a template with code parts' do
      chat = mount_chat(1)
      parts = frames(chat).first['p'].size

      chat.live_update { chat.stream_insert(:messages, message(2)) }

      expect(last_frame(chat)['p'].size).to eq(parts)
      expect(chat.component.instance_variable_get(:@live_template).send(:parts).map(&:first)).to include(:code)
      expect(texts(chat)).to eq(['Ann Message 1', 'Ann Message 2'])
    end

    it 'go out as queued, and the client keeps rows in place, takes the last values and ignores unknown keys' do
      chat = mount_chat(1, 2)
      chat.clear_broadcasts

      chat.live_update do
        chat.stream_insert(:messages, message(1, 'again'))
        chat.stream_insert(:messages, message(3, 'three'))
        chat.stream_insert(:messages, message(3, 'three, last'), at: :start)
        chat.stream_update(:messages, message(9, 'absent'))
        chat.stream_delete(:messages, key(8))
      end

      expect(chat.stream_ops(:messages).map(&:first)).to eq(%w[a a p u d])
      expect(chat.stream_ids(:messages)).to eq([key(1), key(2), key(3)])
      expect(texts(chat)).to eq(['Ann again', 'Ann Message 2', 'Ann three, last'])
    end

    it 'bring the statics of a branch inside a row the first time a row takes it' do
      chat = mount_chat(1)
      chat.clear_broadcasts

      chat.live_update { chat.stream_insert(:messages, message(2, 'two', pinned: true)) }
      first = last_frame(chat)
      chat.live_update { chat.stream_insert(:messages, message(3, 'three', pinned: true)) }

      expect(first['s'].keys.size).to eq(1)
      expect(first['s'].values.first).to eq([' <b>pinned</b>'])
      expect(last_frame(chat)).not_to have_key('s')
      expect(chat.rendered).to have_css("##{key(3)} b", text: 'pinned')
    end

    it 'send the diffs of two changed streams in one frame' do
      chat = mount_chat(1)
      chat.clear_broadcasts

      chat.live_update do
        chat.stream_insert(:messages, message(2))
        chat.stream_insert(:notices, message(5, 'heads up'))
      end

      expect(frames(chat).size).to eq(1)
      expect(changed_parts(last_frame(chat)).keys).to contain_exactly(stream_meta(chat).part,
        stream_meta(chat, :notices).part)
      expect(chat.stream_ids(:notices)).to eq(%w[notice-5])
      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
    end

    it 'send small frames for a hot topic, whatever the length of the list, and never re-query' do
      chat = mount_chat(*1..50)
      chat.clear_broadcasts

      100.times { |index| chat.receive_stream('chat', 100 + index) }

      sizes = frames(chat).map { |frame| frame.to_json.bytesize }
      expect(sizes.size).to eq(100)
      expect(sizes.max).to be < 200
      expect(ChatMessage.queries).to eq(1)
      expect(chat.stream_ids(:messages).size).to eq(150)
    end

    it 'render a row in a live partial with the partial as the scope of t' do
      ChatMessage.rows = [message(1, 'one')]
      noted = live_mount('streams/noted')

      noted.live_update { noted.stream_insert(:entries, message(2, 'two')) }

      expect(noted.rendered.all('li').map(&:text)).to eq(['Noted: one', 'Noted: two'])
      expect(noted.stream_ops(:entries).last[0..1]).to eq(%w[a entries_chat_message_2])
    end
  end

  describe 'the initial rows' do
    it 'keep the first position and the last values of a duplicated key' do
      ChatMessage.rows = [message(1, 'first'), message(2), message(1, 'last')]
      chat = live_mount('streams/chat')

      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
      expect(texts(chat)).to eq(['Ann last', 'Ann Message 2'])
    end

    it 'make an empty loop node when there are none, or no initial lambda' do
      chat = mount_chat
      feed = live_mount('stream_feed', connection: chat.connection)

      expect(tree.node_at(frames(chat).first['p'][stream_meta(chat).part], stream_meta(chat).path)).to include(
        'st' => 'messages', 'r' => [], 'k' => []
      )
      expect(feed.stream_ids(:messages)).to eq([])
      expect(frames(feed).first['p'].to_json).to include('"st":"messages","r":[],"k":[]')
    end
  end

  describe 'stream_reset' do
    it 'sends the whole node from the initial lambda with later ops folded in, at the path, without part code' do
      chat = mount_chat(1, 2)
      calls = part_calls(chat)
      chat.clear_broadcasts
      ChatMessage.rows = [message(7, 'seven')]

      chat.live_update do
        chat.stream_insert(:messages, message(3))
        chat.stream_reset(:messages)
        chat.stream_insert(:messages, message(8, 'eight'))
      end

      meta = stream_meta(chat)
      update = tree.node_at(tree.apply({ 't' => meta.path[0][0], 'd' => [] }, last_frame(chat)['p'][meta.part]),
        meta.path)
      expect(changed_parts(last_frame(chat)).keys).to eq([meta.part])
      expect(update).to include('t' => meta.scope, 'st' => 'messages', 'k' => [key(7), key(8)])
      expect(chat.stream_ops(:messages)).to eq([['reset', [key(7), key(8)]]])
      expect(texts(chat)).to eq(['Ann seven', 'Ann eight'])
      expect(calls).to be_empty
      expect(ChatMessage.queries).to eq(2)
    end

    it 'joins the diff of a part that re-ran for another reason' do
      chat = mount_chat(1)
      chat.clear_broadcasts
      ChatMessage.rows = [message(5)]

      chat.live_update do
        chat.density = 'compact'
        chat.stream_reset(:messages)
      end

      expect(chat.rendered).to have_css('ul.messages.compact')
      expect(chat.stream_ids(:messages)).to eq([key(5)])
    end
  end

  describe 'a stream the client holds' do
    it 'is left alone when its part re-runs, and its ops join the part diff' do
      chat = mount_chat(1)
      calls = part_calls(chat)
      chat.clear_broadcasts

      chat.live_update do
        chat.density = 'compact'
        chat.stream_insert(:messages, message(2))
      end

      meta = stream_meta(chat)
      diff = last_frame(chat)['p'][meta.part]
      expect(diff['d']).to include('0' => 'compact')
      expect(diff['d'].keys).to contain_exactly('0', meta.path.dig(0, 1).to_s)
      expect(chat.stream_ops(:messages).map(&:first)).to eq(%w[a])
      expect(calls).not_to be_empty
      expect(ChatMessage.queries).to eq(1)
      expect(texts(chat)).to eq(['Ann Message 1', 'Ann Message 2'])
    end

    it 'sends nothing for a change elsewhere, and runs no query' do
      chat = mount_chat(1)
      chat.clear_broadcasts

      chat.perform(:type, text: 'hello')

      expect(last_frame(chat)['p'].to_json).not_to include('messages')
      expect(chat.stream_ops(:messages)).to be_empty
      expect(ChatMessage.queries).to eq(1)
    end

    it 'keeps getting ops while its condition changes without a tracked mark' do
      chat = mount_chat(1)
      chat.clear_broadcasts

      chat.live_update do
        chat.hide_quietly
        chat.stream_insert(:messages, message(2))
      end

      expect(frames(chat).size).to eq(1)
      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
    end
  end

  describe 'a stream the client does not hold' do
    it 'drops ops queued when its part hides it, and sends no frame for later ones' do
      chat = mount_chat(1)
      chat.clear_broadcasts

      chat.live_update do
        chat.stream_insert(:messages, message(2))
        chat.expanded = false
      end
      hidden = frames(chat).size
      chat.live_update { chat.stream_insert(:messages, message(3)) }

      expect(hidden).to eq(1)
      expect(frames(chat).size).to eq(1)
      expect(chat.broadcasts.size).to eq(1)
      expect(chat.stream_ids(:messages)).to eq([])
      expect(chat.stream_ops(:messages)).to eq([])
      expect(chat.live_stream(:messages)).not_to be_ops
    end

    it 'refills from its lambda on a reveal, with one query' do
      chat = mount_chat(1)
      chat.perform(:toggle)
      chat.live_update { chat.stream_insert(:messages, message(2)) }
      ChatMessage.rows = [message(1), message(2)]

      chat.perform(:toggle)

      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
      expect(ChatMessage.queries).to eq(2)
    end

    it 'folds in the ops of the cycle that reveals it, in either order' do
      chat = mount_chat(1)
      chat.perform(:toggle)

      chat.live_update do
        chat.expanded = true
        chat.stream_insert(:messages, message(2))
      end
      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])

      chat.perform(:toggle)
      chat.live_update do
        chat.stream_insert(:messages, message(3), at: :start)
        chat.expanded = true
      end
      expect(chat.stream_ids(:messages)).to eq([key(3), key(1)])
      expect(frames(chat).last['p'].to_json).to include('"st":"messages"')
    end

    it 'stays hidden while its condition changes without a tracked mark, until its part renders' do
      chat = mount_chat(1)
      chat.live_update do
        chat.hide_quietly
        chat.density = 'compact'
      end
      chat.clear_broadcasts

      chat.live_update do
        chat.show_quietly
        chat.stream_insert(:messages, message(2))
      end
      expect(chat.broadcasts).to be_empty

      chat.perform(:type, text: 'x')
      expect(chat.stream_ids(:messages)).to eq([])

      chat.live_update { chat.density = 'cozy' }
      expect(chat.stream_ids(:messages)).to eq([key(1)])
    end

    it "is absent in a compound component's variant without it, and refills on the way back" do
      ChatMessage.rows = [message(1)]
      paged = live_mount('streams/paged')
      paged.perform(:show, kind: 'empty')
      paged.clear_broadcasts

      paged.live_update { paged.stream_insert(:items, message(2)) }
      expect(paged.broadcasts).to be_empty
      expect(paged.live_stream(:items)).not_to be_ops

      ChatMessage.rows = [message(1), message(3)]
      paged.perform(:show, kind: 'list')
      expect(paged.stream_ids(:items)).to eq(%w[items_chat_message_1 items_chat_message_3])
    end
  end

  describe 'a limit' do
    it 'keeps the last rows of the initial lambda, and the client trims opposite each insert' do
      chat = mount_chat
      chat.live_update { (1..5).each { |id| chat.stream_insert(:notices, message(id)) } }
      expect(chat.stream_ids(:notices)).to eq(%w[notice-3 notice-4 notice-5])

      chat.live_update { chat.stream_insert(:notices, message(9), at: :start) }
      expect(chat.stream_ids(:notices)).to eq(%w[notice-9 notice-3 notice-4])

      ChatMessage.notices = (1..5).map { |id| message(id) }
      limited = live_mount('streams/chat', id: 'limited', connection: chat.connection)
      expect(tree.node_at(frames(limited).first['p'][stream_meta(limited, :notices).part], [])).to include(
        'l' => 3, 'k' => %w[notice-3 notice-4 notice-5]
      )
    end
  end

  describe 'errors' do
    it 'send an _error for a row that raises, and drop the queue' do
      chat = mount_chat(1, raise_errors: false)
      broken = message(2)
      broken.define_singleton_method(:body) { raise 'no body' }

      chat.live_update { chat.stream_insert(:messages, broken) }

      expect(chat.broadcasts.last).to have_key(:_error)
      expect(chat.live_stream(:messages)).not_to be_ops
    end

    it 'send an _error when the initial lambda raises' do
      allow(ChatMessage).to receive(:recent).and_raise('query failed')

      chat = live_mount('streams/chat', raise_errors: false)

      expect(chat.broadcasts.last).to have_key(:_error)
    end

    it 'still ship ops queued before an action error rescue_from handles' do
      klass = chat_class do
        actions :add_then_fail
        rescue_from(ArgumentError) { nil }

        def add_then_fail
          stream_insert(:messages, ChatMessage.new(id: 2, body: 'kept'))
          raise ArgumentError, 'handled'
        end
      end
      ChatMessage.rows = [message(1)]
      chat = live_mount(klass)

      chat.perform(:add_then_fail)

      expect(chat.stream_ids(:messages)).to eq([key(1), key(2)])
    end

    it 'drop ops queued before an unhandled error in an action or a callback, and send no _refresh' do
      klass = chat_class do
        actions :add_then_fail
        after_connect do
          stream_from('failing') do |id|
            stream_insert(:messages, ChatMessage.new(id:, body: 'lost'))
            raise 'callback failed'
          end
        end

        def add_then_fail
          stream_insert(:messages, ChatMessage.new(id: 2, body: 'lost'))
          raise 'unhandled'
        end
      end
      chat = live_mount(klass, raise_errors: false)
      chat.clear_broadcasts

      chat.perform(:add_then_fail)
      chat.receive_stream('failing', 3)

      expect(chat.broadcasts.map(&:keys)).to all(include(:_error))
      expect(chat.broadcasts(:_refresh)).to be_empty
      expect(chat.live_stream(:messages)).not_to be_ops
    end

    it 'keep ops a before_render halt held back, and refill and fold them on the next render' do
      klass = chat_class do
        before_render { throw :abort if @halt }

        def halt!(value) = @halt = value
      end
      ChatMessage.rows = [message(1)]
      chat = live_mount(klass)
      chat.clear_broadcasts

      chat.live_update do
        chat.halt!(true)
        chat.stream_insert(:messages, message(2))
      end
      expect(chat.broadcasts(:_refresh)).to be_empty
      expect(chat.live_stream(:messages)).to be_ops

      chat.live_update do
        chat.halt!(false)
        chat.draft = 'resume'
      end

      expect(chat.stream_ops(:messages)).to eq([['reset', [key(1), key(2)]]])
      expect(ChatMessage.queries).to eq(2)
    end

    it 'collapse what a halted component queues past 1,000 ops into the refill, with one warning' do
      klass = chat_class do
        before_render { throw :abort if @halt }

        def halt!(value) = @halt = value
      end
      ChatMessage.rows = [message(1)]
      chat = live_mount(klass)
      LiveCable.instance_variable_set(:@warned_messages, Set.new)
      allow(LiveCable.logger).to receive(:warn)

      chat.live_update { chat.halt!(true) }
      3.times do |batch|
        chat.live_update { 700.times { |id| chat.stream_insert(:messages, message((batch * 700) + id + 2)) } }
      end

      expect(chat.live_stream(:messages)).to have_attributes(ops: [], reset?: true, collapsed?: true)
      expect(LiveCable.logger).to have_received(:warn).with(
        '[LiveCable] stream :messages of streams/chat/test queued 1000 ops while a render callback halted ' \
        "Live::Streams::Chat's renders, so they were dropped: it refills from its initial lambda when it renders"
      ).once
    end
  end

  describe 'what is kept' do
    it 'holds no rows in the tracker or the retained render context after a full render and an op frame' do
      ChatMessage.rows = [message(1, 'first row')]
      room = live_mount('streams/room')
      room.perform(:retopic, topic: 'news')
      feed = room.connection.get_component('streams/feed/side')
      room.live_update { feed.stream_insert(:entries, message(2, 'second row')) }

      [room.component, feed].each do |component|
        expect(tracked_nodes(component).to_json).not_to include('row')
        expect(component.send(:previous_render_context).render_results).to be_empty
      end
    end
  end

  describe 'verify_stream_items' do
    after { LiveCable.configuration.verify_stream_items = true }

    it "adopts a row's own id that is its key, in a row reading its own locals, the component and helpers" do
      ChatMessage.rows = [message(1, 'one')]

      own = live_mount('streams/own_ids')
      own.live_update { own.stream_insert(:messages, message(2, 'two')) }

      expect(own.rendered).to have_css("li.own##{key(1)}", text: 'Said: ONE')
      expect(own.rendered).to have_css("li.own##{key(2)} a[href='#m2']", text: 'TWO')
    end

    it "raises for a row whose own id isn't its key, with the dom_id: fix" do
      ChatMessage.rows = [message(1)]
      klass = Class.new(Live::Streams::OwnIds) { def self.name = 'Live::Streams::WrongIds' }

      expect { live_mount(klass) }.to raise_error(
        LiveCable::Error,
        "stream :messages: the row's id `chat_message_1` isn't its dom id `messages_chat_message_1`. Remove the " \
        'id attribute, or declare `stream :messages, dom_id: ->(message) { … }` returning `chat_message_1`'
      )

      LiveCable.configuration.verify_stream_items = false
      expect(live_mount(klass).rendered).to have_css('li#chat_message_1')
    end

    it "raises for a declared stream the template doesn't render" do
      klass = Class.new(Live::StreamFeed) do
        def self.name = 'Live::StreamFeed'

        stream :notes
      end

      expect { live_mount(klass) }.to raise_error(
        LiveCable::Error,
        'Live::StreamFeed declares stream :notes, but live/stream_feed.html.live.erb has no `live_stream_for :notes`'
      )

      LiveCable.configuration.verify_stream_items = false
      expect(live_mount(klass).stream_ids(:messages)).to eq([])
    end

    it 'defaults to off in production' do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(LiveCable::Configuration.new.verify_stream_items).to be(false)
    end
  end

  describe 'inline children' do
    def room_with(*ids)
      ChatMessage.rows = ids.map { |id| message(id) }
      room = live_mount('streams/room')
      [room, room.connection.get_component('streams/feed/side')]
    end

    def entry(id) = "entries_chat_message_#{id}"

    it "send ops in the child's result when the parent renders it inline" do
      room, feed = room_with(1)
      room.clear_broadcasts

      room.live_update do
        room.topic = 'news'
        feed.stream_insert(:entries, message(2))
      end

      child = last_frame(room)['c'].fetch('streams/feed/side')
      expect(child['p'].to_json).to include('"o":[["a","entries_chat_message_2"')
      expect(feed.live_stream(:entries)).not_to be_ops
      expect(room.rendered).to have_css("li##{entry(2)}")
    end

    it "send them in the child's own frame once it subscribed, when the parent doesn't render it" do
      room, = room_with(1)
      feed = room.subscribe_child('streams/feed/side')
      room.clear_broadcasts
      feed.clear_broadcasts

      room.live_update { feed.stream_insert(:entries, message(2)) }

      expect(room.broadcasts).to be_empty
      expect(feed.stream_ops(:entries).map { |op| op[0..1] }).to eq([['a', entry(2)]])
      expect(feed.stream_ids(:entries)).to eq([entry(1), entry(2)])
    end

    it 'keep them until the child subscribes, then send them' do
      room, feed = room_with(1)
      room.clear_broadcasts

      room.live_update { feed.stream_insert(:entries, message(2)) }
      expect(room.broadcasts).to be_empty
      expect(feed.live_stream(:entries)).to be_ops

      subscribed = room.subscribe_child('streams/feed/side')

      expect(subscribed.stream_ops(:entries).map { |op| op[0..1] }).to eq([['a', entry(2)]])
      expect(subscribed.stream_ids(:entries)).to eq([entry(1), entry(2)])
    end

    it 'refill from the lambda on subscribe after too many ops queued' do
      room, feed = room_with(1)
      allow(LiveCable).to receive(:warn_once)
      ChatMessage.rows = [message(1), message(5)]

      room.live_update { 1_001.times { |index| feed.stream_insert(:entries, message(100 + index)) } }
      subscribed = room.subscribe_child('streams/feed/side')

      expect(LiveCable).to have_received(:warn_once).once
      expect(subscribed.stream_ops(:entries)).to eq([['reset', [entry(1), entry(5)]]])
    end

    it "carry a prerendered child's rows in the parent's first socket frame" do
      ChatMessage.rows = [message(1), message(2)]
      page = Capybara.string(Live::Streams::Room.new('page').render)

      room = live_mount('streams/room', id: 'page')
      child = frames(room).first['c'].fetch('streams/feed/side')

      expect(page.all('li').map { |row| row[:id] }).to eq([entry(1), entry(2)])
      expect(child['p'].to_json).to include('"k":["entries_chat_message_1","entries_chat_message_2"]')
      expect(room.rendered.find('ul').native.inner_html).to eq(page.find('ul').native.inner_html)
    end
  end

  describe 'live components in rows' do
    it 'raise when a helper renders one from a row' do
      ChatMessage.rows = [message(1)]

      expect { live_mount('streams/badged') }.to raise_error(
        LiveCable::Error,
        'Live::Streams::Badged rendered the live component badge/1 in a row of stream :messages. Rows render on ' \
        "their own when ops arrive, so they can't hold live components: render it outside the stream"
      )
    end

    it 'raise on prerender too' do
      ChatMessage.rows = [message(1)]

      expect { Live::Streams::Badged.new('page').render }.to raise_error(LiveCable::Error, /in a row of stream/)
    end
  end
end
