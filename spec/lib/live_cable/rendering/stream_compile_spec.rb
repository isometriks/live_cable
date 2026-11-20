# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Compiling collection streams' do
  host = 'app/views/live/streams/host.html.live.erb'

  let(:message) do
    Class.new(Struct.new(:id, :body, :author_name)) do
      include ActiveModel::Conversion
      extend ActiveModel::Naming

      def self.name = 'Message'

      def persisted? = true
    end
  end

  # Answers the template's names the way a component answers its reactive
  # variables.
  let(:component_class) do
    Class.new do
      def initialize(names) = @names = names

      def live_connection = nil

      def live_stream(name) = raise(LiveCable::Error, "Fake has no stream #{name.inspect} (declared: none)")

      def method_missing(name, *args)
        @names.key?(name) ? @names[name] : super
      end

      def respond_to_missing?(name, include_private = false)
        @names.key?(name) || super
      end
    end
  end

  def compile(source, virtual_path: 'live/streams/host', structured: true)
    previous = LiveCable.configuration.structured_blocks
    LiveCable.configuration.structured_blocks = structured
    identifier = Rails.root.join("app/views/#{virtual_path}.html.live.erb").to_s
    template = ActionView::Template.new(source, identifier, LiveCable::Rendering::Handler,
      locals: [], format: :html, virtual_path:)
    LiveCable::Rendering::Handler.call(template, source)
  ensure
    LiveCable.configuration.structured_blocks = previous
  end

  def partial_for(source, **)
    LiveCable::Rendering::Partial::CACHE.clear
    eval(compile(source, **)) # rubocop:disable Security/Eval
  end

  def compile_error(source, **)
    compile(source, **)
  rescue LiveCable::Rendering::CompileError => e
    e.message
  else
    raise 'expected a compile error'
  end

  # A stream's node as its full render builds it, from row values by key
  def stream_node(stream, scope, rows)
    node = { 't' => scope, 'r' => rows.values, 'k' => rows.keys }
    stream.key_id ? node.merge('ik' => 1) : node
  end

  def render_rows(partial, rows, name: :messages)
    stream = partial.streams.fetch(name)
    LiveCable::Rendering::Tree.render(stream_node(stream, stream.scope, rows), partial.statics)
  end

  def renderer_for(partial, names)
    component = component_class.new(names)
    view_context = ApplicationController.new.view_context
    view_context.send(:context_stack).push(LiveCable::RenderContext.new(component))
    partial.for_component(component, view_context)
  end

  # Renders the template on prerender, with each stream's node built from
  # its row method the way a stream's full render builds it.
  def prerender(source, rows: {}, **names)
    partial = partial_for(source)
    renderer = renderer_for(partial, names)
    streams = partial.streams
    build = method(:stream_node)

    renderer.define_singleton_method(:__lc_stream) do |name, scope|
      stream = streams.fetch(name)
      values = rows.fetch(name).to_h { |row| ["#{name}_#{row.id}", row] }.to_h do |key, row|
        [key, __send__(stream.row_method, row, key)]
      end
      build.call(stream, scope, values)
    end

    renderer.render_changes(:all).sum('') { |part| LiveCable::Rendering::Tree.render(part, partial.statics) }
  end

  chat = <<~ERB
    <div class="chat">
      <h2><%= room_name %></h2>
      <% if expanded %>
        <ul class="messages <%= density %>" live-stream="messages">
          <%= live_stream_for :messages do |message| %>
            <li class="message"><strong><%= message.author_name %></strong> <%= message.body %></li>
          <% end %>
        </ul>
      <% else %>
        <button live-action="toggle">Show chat</button>
      <% end %>
    </div>
  ERB

  describe 'the worked example' do
    it 'records where the stream is and gives its row a method and statics of its own' do
      partial = partial_for(chat)
      stream = partial.streams.fetch(:messages)

      expect(stream.to_h).to eq(name: :messages, part: 3, path: [[0, 1]], scope: 1, virtual_path: 'live/streams/host',
        user_id_code: nil, key_id: true)
      expect(partial.statics[0]).to eq(['    <ul class="messages ', "\" live-stream=\"messages\">\n      ",
        "    </ul>\n  "])
      expect(partial.statics[1]).to eq(['<li id="', '" class="message"><strong>', '</strong> ', '</li>'])

      row = renderer_for(partial, {}).__lc_stream_row_1(message.new(7, 'hi', 'Ann'), 'messages_message_7')
      expect(row).to eq(%w[Ann hi])
    end

    it "leaves the id it gives a row out of the row's values, for the key to fill" do
      partial = partial_for(chat)
      row = renderer_for(partial, {}).__lc_stream_row_1(message.new(7, 'hi', 'Ann'), 'messages_message_7')

      expect(render_rows(partial, { 'messages_message_7' => row, 'a&"<b>' => row })).to eq(
        '<li id="messages_message_7" class="message"><strong>Ann</strong> hi</li>' \
        '<li id="a&amp;&quot;&lt;b&gt;" class="message"><strong>Ann</strong> hi</li>'
      )
    end

    it "keeps a row's own id among its values" do
      partial = partial_for(<<~ERB)
        <div>
          <ul live-stream="messages">
            <%= live_stream_for :messages do |message| %><li id="<%= dom_id(message) %>"><%= message.body %></li><% end %>
          </ul>
        </div>
      ERB

      expect(partial.streams.fetch(:messages).key_id).to be(false)
      expect(renderer_for(partial, {}).__lc_stream_row_0(message.new(3, 'hi'), 'message_3')).to eq(%w[message_3 hi])
    end

    it 'calls the stream in place of its rows in the hosting part' do
      code = partial_for(chat).send(:parts).find { |type, _| type == :tree }.last

      expect(code).to include("__lc_2 << __lc_stream(:messages, 1)\n")
      expect(code).not_to include('live_stream_for')
      expect(code).not_to include('author_name')
    end

    it "leaves the row's reads out of the hosting part's dependencies" do
      partial = partial_for(<<~ERB)
        <div>
          <% if expanded %>
            <ul live-stream="messages">
              <%= live_stream_for :messages do |message| %><li><%= highlight %><%= message.body %></li><% end %>
            </ul>
          <% end %>
        </div>
      ERB

      dependencies = partial.send(:metadata).compact.flat_map { |part| part[:component_dependencies] }
      expect(dependencies).to include(:expanded)
      expect(dependencies).not_to include(:highlight)
    end

    it 'renders on prerender with each row keyed by its id, without whitespace around it' do
      rows = [message.new(1, 'one', 'Ann'), message.new(2, 'two <b>', 'Bob')]
      html = prerender(chat, rows: { messages: rows }, room_name: 'Lobby', expanded: true, density: 'cozy')

      expect(html).to include(
        "<ul class=\"messages cozy\" live-stream=\"messages\">\n      " \
        '<li id="messages_1" class="message"><strong>Ann</strong> one</li>' \
        '<li id="messages_2" class="message"><strong>Bob</strong> two &lt;b&gt;</li>    </ul>'
      )
    end
  end

  describe 'placement' do
    def stream_in(markup) = "<div>\n#{markup}</div>\n"

    let(:list) do
      <<~ERB
        <ul live-stream="messages">
          <%= live_stream_for :messages do |message| %>
            <li><%= message.body %></li>
          <% end %>
        </ul>
      ERB
    end

    it 'puts a top-level stream at the root of its part' do
      stream = partial_for(stream_in(list)).streams.fetch(:messages)

      expect([stream.part, stream.path]).to eq([1, []])
    end

    it 'counts the output position, which leaves out code parts' do
      partial = partial_for(stream_in("<% x = 1 %>\n<p><%= x %></p>\n#{list}"))
      stream = partial.streams.fetch(:messages)
      renderer = renderer_for(partial, {})
      renderer.define_singleton_method(:__lc_stream) { |name, scope| { 't' => scope, 'name' => name } }

      expect(partial.send(:parts).map(&:first)).to include(:code)
      expect(renderer.render_changes(:all)[stream.part]).to eq('t' => stream.scope, 'name' => :messages)
    end

    it 'finds a stream two branches deep, through unless and case' do
      partial = partial_for(stream_in(<<~ERB))
        <% unless hidden %>
          <p><%= title %></p>
          <% case mode %>
          <% when :list %>
            #{list}
          <% end %>
        <% end %>
      ERB

      expect(partial.streams.fetch(:messages).path).to eq([[0, 1], [1, 0]])
    end

    it 'finds a stream in an elsif branch' do
      partial = partial_for(stream_in("<% if a %>a<% elsif b %>#{list}<% end %>"))

      expect(partial.streams.fetch(:messages).path).to eq([[1, 0]])
    end

    it 'goes through a live partial rendered at the top of the template' do
      partial = partial_for("<div>\n  <%= render 'live/streams/list', title: 'Log' %>\n</div>\n")
      stream = partial.streams.fetch(:entries)

      expect(stream.to_h).to include(path: [[0, 1]], virtual_path: 'live/streams/_list')
    end

    it 'splices a live partial in a branch into the branch' do
      partial = partial_for("<div>\n<% if open %><%= render 'live/streams/list', title: 'Log' %><% end %></div>\n")

      expect(partial.streams.fetch(:entries).path).to eq([[0, 1]])
    end

    it 'finds the row element of a live partial and gives it the id' do
      partial = partial_for(stream_in(<<~ERB))
        <ul live-stream="messages">
          <%= live_stream_for :messages do |message| %>
            <%= render 'live/streams/message', message: %>
          <% end %>
        </ul>
      ERB

      row = renderer_for(partial, {}).__lc_stream_row_0(message.new(3, 'hi'), 'messages_3')
      expect(render_rows(partial, { 'messages_3' => row })).to eq('<li id="messages_3" class="message">hi</li>')
    end

    it "adopts a live partial row's own id" do
      partial = partial_for(stream_in(<<~ERB))
        <ul live-stream="messages">
          <%= live_stream_for :messages do |message| %><%= render 'live/streams/identified_message', message: %><% end %>
        </ul>
      ERB

      row = renderer_for(partial, {}).__lc_stream_row_0(message.new(3, 'hi'), 'ignored')
      expect(partial.streams.fetch(:messages).key_id).to be(false)
      expect(render_rows(partial, { 'ignored' => row })).to eq('<li id="messages_message_3" class="message">hi</li>')
    end

    it 'rejects a stream in a loop, naming the loop' do
      %w[each times].zip(['items.each do |item|', '3.times do']).each do |name, code|
        expect(compile_error(stream_in("<% #{code} %>\n#{list}<% end %>"))).to eq(
          "#{host}:4: stream :messages can't sit inside `#{name}` (#{host}:2): a stream needs exactly one " \
          'container, so it renders once, outside any loop'
        )
      end

      expect(compile_error(stream_in("<% for i in items %>\n#{list}<% end %>"))).to include("inside `for` (#{host}:2)")
      expect(compile_error(stream_in("<% while more %>\n#{list}<% end %>"))).to include("inside `while` (#{host}:2)")
      expect(compile_error(stream_in("<% if a %><% items.each do |i| %><% if b %>#{list}<% end %><% end %><% end %>"))).
        to include("inside `each` (#{host}:2)")
    end

    it "rejects a stream in another stream's row" do
      nested = stream_in(<<~ERB)
        <ul live-stream="outer">
          <%= live_stream_for :outer do |row| %>
            <li><ol live-stream="inner"><%= live_stream_for :inner do |item| %><li></li><% end %></ol></li>
          <% end %>
        </ul>
      ERB

      expect(compile_error(nested)).to include("stream :inner can't sit inside the row of stream :outer (#{host}:3)")
    end

    it 'rejects a stream in a collection render of a live partial' do
      expect(compile_error("<div>\n<%= render partial: 'live/streams/list', collection: lists, as: :title %></div>")).
        to include("stream :entries can't sit inside `render collection:` (#{host}:2)")
    end

    it 'rejects a stream in a block helper or begin, naming it with the fix' do
      {
        '<%= form_with url: "/x" do |form| %>' => 'form_with',
        '<%= tag.section class: "x" do %>' => 'tag.section',
        '<%= content_tag :section do %>' => 'content_tag',
        '<%= turbo_frame_tag "x" do %>' => 'turbo_frame_tag',
        '<% cache "x" do %>' => 'cache',
        '<% c = capture do %>' => 'capture',
        '<% content_for :side do %>' => 'content_for',
      }.each do |opener, name|
        expect(compile_error(stream_in("#{opener}\n#{list}<% end %>"))).to eq(
          "#{host}:4: stream :messages can't sit inside `#{name}` (#{host}:2): block helpers render to one " \
          'HTML string. Use a plain element: `<form live-form="…">` instead of `form_with`, or ' \
          '`<section class="…">` instead of `tag.section do`'
        )
      end

      expect(compile_error(stream_in("<% begin %>\n#{list}<% rescue %><% end %>"))).to eq(
        "#{host}:4: stream :messages can't sit inside `begin` (#{host}:2): begin/rescue renders to one HTML " \
        'string. Rescue in a component method instead'
      )
    end

    it 'rejects a stream in a block that would compile to HTML, with the reason' do
      expect(compile_error("<% if a %>\n<div>#{list}</div><% end %>\n")).to eq(
        "#{host}:3: stream :messages is in a block that opens the template, which renders to one HTML string. " \
        "Put the template's content in a root element"
      )
      expect(compile_error(stream_in("<% if a %><% next if b %>#{list}<% end %>"))).to include(
        'stream :messages is in a block that uses next, break, return, redo, retry or throw'
      )
      expect(compile_error(stream_in(<<~ERB))).to include('uses next, break, return')
        <ul live-stream="messages">
          <%= live_stream_for :messages do |message| %><li><% break if message.body %></li><% end %>
        </ul>
      ERB
      expect(compile_error(stream_in("<% x = if a %>#{list}<% end %><%= x %>"))).to include(
        'stream :messages is in a conditional used as a value (`x = if …`)'
      )
    end

    it 'needs structured blocks' do
      expect(compile_error(stream_in(list), structured: false)).to eq(
        "#{host}:3: collection streams need structured blocks: stream :messages can't compile with " \
        'config.structured_blocks = false'
      )
    end

    it 'allows one call site per stream' do
      expect(compile_error(stream_in("#{list}#{list}"))).to eq(
        "#{host}:8: stream :messages is also rendered at #{host}:3: a template renders each stream from one place"
      )

      twice = "<div>\n<% if a %><%= render 'live/streams/list', title: 'A' %><% else %>" \
              "<%= render 'live/streams/list', title: 'B' %><% end %></div>"
      list_file = 'app/views/live/streams/_list.html.live.erb'
      expect(compile_error(twice)).to eq(
        "#{list_file}:5: stream :entries is also rendered at #{list_file}:5: a template renders each stream " \
        'from one place'
      )
    end
  end

  describe 'the call' do
    def call_error(tag, close = '<% end %>')
      compile_error(%(<div>\n<ul live-stream="messages">#{tag}<li></li>#{close}</ul></div>))
    end

    form = '<%= live_stream_for :name do |row| %>…<% end %>'

    it 'must be an output tag with a do block, a Symbol literal and one parameter' do
      {
        '<% live_stream_for :messages do |m| %>' => 'it needs an output tag (<%=), not <%',
        '<%= live_stream_for name do |m| %>' => "its only argument is the stream's name, as a Symbol literal " \
                                                '(got name)',
        '<%= live_stream_for :messages, :x do |m| %>' => "its only argument is the stream's name, as a Symbol " \
                                                         'literal (got :messages, :x)',
        '<%= live_stream_for do |m| %>' => "its only argument is the stream's name, as a Symbol literal (got none)",
        '<%= live_stream_for :Messages do |m| %>' => 'stream names are lowercase snake_case (got :Messages)',
        '<%= live_stream_for :messages do %>' => 'its block takes exactly one parameter, the row (got none)',
        '<%= live_stream_for :messages do |a, b| %>' => 'its block takes exactly one parameter, the row (got |a, b|)',
        '<%= live_stream_for :messages do |(a, b)| %>' => 'its block takes exactly one parameter, the row ' \
                                                          '(got |(a, b)|)',
        '<%= live_stream_for :messages do |m = 1| %>' => 'its block takes exactly one parameter, the row ' \
                                                         '(got |m = 1|)',
      }.each do |tag, problem|
        expect(call_error(tag)).to eq("#{host}:2: write `live_stream_for` as #{form}: #{problem}")
      end

      expect(call_error('<%= live_stream_for(:messages) { |m| %>', '<% } %>')).to eq(
        "#{host}:2: write `live_stream_for` as #{form}: its block needs do … end, not braces"
      )
      expect(call_error('<%= live_stream_for :messages do |m| %>', '<% rescue %><% end %>')).to eq(
        "#{host}:2: write `live_stream_for` as #{form}: its block can't have rescue, else or ensure"
      )
    end

    it 'raises when a template the compiler never saw calls it' do
      view_context = ApplicationController.new.view_context

      expect { view_context.live_stream_for(:messages) { nil } }.to raise_error(
        LiveCable::Error,
        "live_stream_for is compiled into .live.erb templates. Render it from the component's template or a " \
        'live partial'
      )
    end

    it 'points stream(:name).each at live_stream_for' do
      expect(compile_error("<div>\n<% stream(:messages).each do |m| %><p></p><% end %></div>")).to eq(
        "#{host}:2: `stream(:messages).each` reads collection stream :messages as a list, but a stream holds no " \
        'rows. Render it with <%= live_stream_for :messages do |row| %>…<% end %> inside an element with ' \
        'live-stream="messages"'
      )
      expect(compile_error('<div><%= stream(:messages).size %></div>')).to include('`stream(:messages).size`')
      expect(compile(%(<div><%# stream(:messages).each %><%= stream %></div>))).to be_a(String)
      [
        '<% if stream(:messages).any? %>x<% end %>',
        '<% unless a %>x<% else %><% while stream(:messages).empty? %><% end %><% end %>',
        '<% if a %>x<% elsif stream(:messages).none? %>y<% end %>',
        '<% case stream(:messages).size %><% when 1 %>x<% end %>',
        '<% case a %><% when stream(:messages).first %>x<% end %>',
      ].each do |control|
        expect(compile_error("<div>\n#{control}</div>")).to start_with("#{host}:2: `stream(:messages).")
      end
    end

    it 'raises for a stream nobody declared when it renders' do
      partial = partial_for(%(<div>\n<ul live-stream="messages">) +
                            %(<%= live_stream_for :messages do |m| %><li></li><% end %></ul></div>))

      expect do
        renderer_for(partial, {}).render_changes(:all)
      end.to raise_error(LiveCable::Error, /has no stream :messages/)
    end
  end

  describe 'the container' do
    def container_error(open, close)
      compile_error(%(<div>\n#{open}<%= live_stream_for :messages do |m| %><li></li><% end %>#{close}</div>))
    end

    it 'is the element the call is the sole content of, named by a static live-stream' do
      commented = %(<div>\n<ul live-stream="messages">\n  <%# rows %>\n  ) +
                  %(<%= live_stream_for :messages do |m| %><li></li><% end %>\n</ul></div>)
      expect(compile(commented)).to be_a(String)

      expect(container_error('<ul>', '</ul>')).to eq(
        "#{host}:2: stream :messages needs its container, <ul>, to have live-stream=\"messages\""
      )
      expect(container_error('<ul live-stream="msgs">', '</ul>')).to eq(
        "#{host}:2: stream :messages is in <ul live-stream=\"msgs\">: its live-stream must be \"messages\""
      )
      expect(container_error('<ul live-stream="<%= name %>">', '</ul>')).to eq(
        "#{host}:2: stream :messages needs a static live-stream on its container, written live-stream=\"messages\""
      )
    end

    it 'holds nothing else' do
      expect(container_error('<ul live-stream="messages"><li>first</li>', '</ul>')).to eq(
        "#{host}:2: an element with live-stream must contain nothing but its live_stream_for call (whitespace " \
        'and ERB comments aside)'
      )
      expect(compile_error(%(<div>\n<%= live_stream_for :messages do |m| %><li></li><% end %></div>))).to eq(
        "#{host}:1: stream :messages needs its container, <div>, to have live-stream=\"messages\""
      )
      crowded = %(<div>\n<ul><li></li><%= live_stream_for :messages do |m| %><li></li><% end %></ul></div>)
      expect(compile_error(crowded)).to eq(
        "#{host}:2: live_stream_for :messages must be the only content of an element with " \
        'live-stream="messages", such as <ul live-stream="messages">'
      )
    end

    it 'has a call' do
      expect(compile_error(%(<div>\n<ul live-stream="messages"></ul></div>))).to eq(
        "#{host}:2: <ul live-stream=\"messages\"> has no live_stream_for call: its only content must be " \
        '<%= live_stream_for :messages do |row| %>…<% end %>'
      )
    end

    it 'is not a table, a p, inside SVG, or opened conditionally' do
      expect(container_error('<table live-stream="messages">', '</table>')).to eq(
        "#{host}:2: stream :messages can't use a <table> as its container: the browser moves rows out of a " \
        '<table>: put live-stream on its <tbody>'
      )
      expect(container_error('<p live-stream="messages">', '</p>')).to include("can't use a <p> as its container")
      expect(container_error('<svg><g live-stream="messages">', '</g></svg>')).to eq(
        "#{host}:2: stream :messages can't sit inside <svg>: its rows would be parsed as SVG elements"
      )
      expect(compile_error(%(<div>\n<svg><%= render 'live/streams/shapes' %></svg></div>))).to eq(
        "app/views/live/streams/_shapes.html.live.erb:1: stream :entries can't sit inside <svg>: its rows would " \
        'be parsed as SVG elements'
      )
      expect(container_error('<% if a %><ul class="a" live-stream="messages"><% else %><ul live-stream="messages">' \
                             '<% end %>', '</ul>')).to include(
                               'stream :messages its container opens with a conditional tag'
                             )
    end
  end

  describe 'the row' do
    def row_error(row, before: '')
      compile_error(%(<div>\n#{before}<ul live-stream="messages"><%= live_stream_for :messages do |message| %>) +
                    %(#{row}<% end %></ul></div>))
    end

    one = "#{host}:2: the row of stream :messages must render exactly one element"

    it 'renders exactly one element' do
      expect(row_error('<li></li><li></li>')).to eq("#{one}: it has 2 at its top level")
      expect(row_error(' <%# none %> ')).to eq("#{one}: it renders nothing")
      expect(row_error('hello')).to eq("#{one}: it is bare text")
      expect(row_error('<%= link_to "x", "/" %>')).to eq(
        "#{one}: it is `link_to \"x\", \"/\"`, which the compiler can't see into. Write the row's root element " \
        'in the template and render the partial inside it, or make the partial a live partial'
      )
      expect(row_error("<%= render 'live/streams/plain_row', message: %>")).to include(
        "it is `render 'live/streams/plain_row', message:`, which the compiler can't see into"
      )
      expect(row_error("<%= render 'live/streams/two_roots', message: %>")).to eq("#{one}: it has 2 at its top level")
    end

    it 'gets its key as its first attribute, or keeps an id that reads only the row' do
      partial = partial_for(%(<div>\n<ul live-stream="messages"><%= live_stream_for :messages do |message| %>) +
                            %(<li class="a" id="<%= dom_id(message, :messages) %>"></li><% end %></ul></div>))

      expect(partial.statics[0]).to eq(['<li class="a" id="', '"></li>'])
      expect(partial.streams.fetch(:messages).user_id_code).to eq("[(dom_id(message, :messages)\n).to_s].join")

      expect(row_error('<li id="row"></li>')).to eq(
        "#{host}:2: the row of stream :messages has a static id, which every row would share. Remove it, and " \
        'each row gets its dom id as its id'
      )
      expect(row_error('<li id="m-<%= prefix %>"></li>')).to eq(
        "#{host}:2: the row of stream :messages has an id that reads more than `message`. Remove it, and each " \
        'row gets its dom id as its id, or declare `stream :messages, dom_id: ->(message) { … }`'
      )
      expect(row_error('<% if a %><li><% else %><li class="b"><% end %></li>')).to include(
        'opens its element with a conditional tag'
      )
    end

    it 'reads only its own variable, its own locals and the component' do
      partial = partial_for(<<~ERB)
        <div>
          <% label = 'x' %>
          <ul live-stream="messages"><%= live_stream_for :messages do |message| %>
            <% css = message.body.size > 2 ? 'long' : 'short' %>
            <li class="<%= css %>"><%= link_to message.body, '/m' %> <%= room_name %> <%= dom_id(message) %></li>
          <% end %></ul>
          <p><%= label %></p>
        </div>
      ERB

      row = renderer_for(partial, room_name: 'Lobby').__lc_stream_row_0(message.new(4, 'hey'), 'k')
      expect(row).to eq(['long', '<a href="/m">hey</a>', 'Lobby', 'message_4'])
    end

    it 'rejects template locals, live components, provided content and instance variables' do
      local = 'Rows render on their own when ops arrive, so they can read only `message` and the component: ' \
              'use a component method, or compute it from `message`'

      expect(row_error('<li><%= label %></li>', before: "<% label = 'x' %>\n")).to eq(
        "#{host}:3: the row of stream :messages reads `label`, a template local. #{local}"
      )
      expect(row_error('<li><%= label %></li>', before: "<% if a %><% label = 'x' %><% end %>\n")).
        to include('reads `label`, a template local')
      expect(compile_error(<<~ERB)).to include("#{host}:4: the row of stream :messages reads `label`")
        <div>
        <% if open %><% label = 'x' %>
        <ul live-stream="messages">
          <%= live_stream_for :messages do |message| %><li><%= label %></li><% end %>
        </ul><% end %></div>
      ERB
      expect(row_error('<li><% label = 1 %></li>', before: "<% label = 'x' %>\n")).to eq(
        "#{host}:3: the row of stream :messages assigns `label`, a template local. #{local}"
      )
      expect(row_error('<li><%= live("counter", id: message.id) %></li>')).to include(
        'the row of stream :messages calls `live`: live components inside rows are not supported'
      )
      expect(row_error('<li><%= render(Live::Counter.new(message.id)) %></li>')).to include(
        'renders a component (`render(Live::Counter.new(message.id))`)'
      )
      expect(row_error('<li><% content_for :side, message.body %></li>')).to include('calls `content_for`')
      expect(row_error('<li><%= @user %></li>')).to include('uses @user')

      expect(compile_error("<div>\n<%= render 'live/streams/titled_list', title: 'Log' %></div>")).to eq(
        'app/views/live/streams/_titled_list.html.live.erb:3: the row of stream :entries reads `title`, a ' \
        'template local. Rows render on their own when ops arrive, so they can read only `entry` and the ' \
        'component: use a component method, or compute it from `entry`'
      )
    end

    it 'holds branches and block helpers of its own, sent whole' do
      partial = partial_for(<<~ERB)
        <div>
          <ul live-stream="messages"><%= live_stream_for :messages do |message| %>
            <li><% if message.body %><b><%= message.body %></b><% else %><i>none</i><% end %><%= link_to '/m' do %>go<% end %></li>
          <% end %></ul>
        </div>
      ERB

      renderer = renderer_for(partial, {})
      rows = { 'a' => renderer.__lc_stream_row_0(message.new(1, 'hi'), 'a'),
               'b' => renderer.__lc_stream_row_0(message.new(2), 'b') }

      expect(render_rows(partial, rows)).to eq(
        '<li id="a"><b>hi</b><a href="/m">go</a></li><li id="b"><i>none</i><a href="/m">go</a></li>'
      )
    end

    it 'renders an object that responds to render_in, such as a ViewComponent' do
      stub_const('StreamBadge', Data.define(:label) do
        def render_in(view_context) = view_context.tag.b(label)
      end)
      partial = partial_for(<<~ERB)
        <div>
        <ul live-stream="messages"><%= live_stream_for :messages do |message| %><li><%= render(StreamBadge.new(message.body)) %><%= render StreamBadge.new('x') %></li><% end %></ul></div>
      ERB

      row = renderer_for(partial, {}).__lc_stream_row_0(message.new(1, 'hi'), 'k')

      expect(render_rows(partial, { 'k' => row })).to eq('<li id="k"><b>hi</b><b>x</b></li>')
    end

    it 'resolves a Kernel name the component defines to the component' do
      partial = partial_for(%(<div>\n<ul live-stream="messages"><%= live_stream_for :messages do |message| %>) +
                            %(<li><%= test %></li><% end %></ul></div>))

      expect(renderer_for(partial, test: 'mine').__lc_stream_row_0(message.new(1), 'k')).to eq(%w[mine])
    end

    it 'shadows a template local with its own variable' do
      partial = partial_for(<<~ERB)
        <div>
          <% message = 'x' %><p><%= message %></p>
          <ul live-stream="messages"><%= live_stream_for :messages do |message| %><li><%= message.body %></li><% end %></ul>
        </div>
      ERB

      expect(renderer_for(partial, {}).__lc_stream_row_0(message.new(1, 'b'), 'k')).to eq(%w[b])
    end
  end
end
