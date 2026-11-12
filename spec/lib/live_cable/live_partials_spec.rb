# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Live partials' do
  include LiveCable::Testing

  def mount(name)
    component = live_mount(name)
    component.clear_broadcasts
    component
  end

  def changed_parts(component)
    component.broadcasts(:_refresh).last[:_refresh][:p].compact
  end

  describe 'dependency tracking' do
    it "renders the partials with the component's state" do
      chat = mount('lp_chat')

      expect(chat.rendered).to have_css('[data-testid="messages"] li', count: 2)
      expect(chat.rendered).to have_css('[data-testid="badge-lobby"]', text: 'Lobby: 1')
      expect(chat.rendered).to have_css('.badge.one[data-testid="badge-static"]', text: 'static: 1')
      expect(chat.rendered).to have_css('[data-testid="panel"]', text: 'empty')
      expect(chat.rendered).to have_css('[data-testid="outer"] [data-testid="inner"]', text: 'f/1')
      expect(chat.rendered).to have_css('[data-testid="plain"]', text: 'Lobby')
    end

    it 'sends only the partial whose state changed' do
      chat = mount('lp_chat')

      chat.perform(:add_message)

      expect(changed_parts(chat)).to eq([{ 'd' => { '0' => { 'n' => 3, 'r' => { '2' => ['new'] } } } }])
      expect(chat.rendered).to have_css('[data-testid="messages"] li', count: 3)
    end

    it 'sends the values of a partial whose arguments changed' do
      chat = mount('lp_chat')

      chat.perform(:rename)

      expect(chat.rendered).to have_css('[data-testid="badge-renamed"]', text: 'Renamed: 1')
      expect(chat.rendered).to have_css('[data-testid="plain"]', text: 'Renamed')
      expect(chat.rendered).to have_css('[data-testid="badge-static"]', text: 'static: 1')
      expect(changed_parts(chat)).to include({ 'd' => { '1' => 'renamed', '2' => 'Renamed' } })
    end

    it 'tracks a read in a nested partial and in a default' do
      chat = mount('lp_chat')

      chat.perform(:bump)

      expect(chat.rendered).to have_css('[data-testid="inner"]', text: 'f/2')
      expect(chat.rendered).to have_css('[data-testid="scaled"]', text: '20')
      expect(chat.rendered).to have_css('[data-testid="badge-lobby"]', text: 'Lobby: 2')
      expect(chat.rendered).to have_css('[data-testid="bump"]', text: 'Bump 2')
      expect(changed_parts(chat).size).to eq(4)
    end

    it 'tracks an argument passed to a nested partial' do
      chat = mount('lp_chat')

      chat.perform(:change_footer)

      expect(changed_parts(chat)).to eq([{ 'd' => { '0' => 'g' } }])
      expect(chat.rendered).to have_css('[data-testid="inner"]', text: 'g/1')
    end

    it 'tracks state read inside a branch of the partial' do
      chat = mount('lp_chat')

      chat.perform(:toggle)

      expect(chat.rendered).to have_no_css('[data-testid="panel"]')

      chat.set_reactive(:draft, 'typing')
      chat.perform(:toggle)

      expect(chat.rendered).to have_css('[data-testid="panel"]', text: 'typing')
    end

    it 'keeps a child component rendered in a partial across renders that skip it' do
      chat = mount('lp_chat')
      kid = chat.component.owned_children.find { |child| child.live_id == 'counter/kid' }
      expect(kid).not_to be_nil

      chat.perform(:rename)

      expect(chat.component.owned_children).to include(kid)
      expect(chat.connection.get_component('counter/kid')).to equal(kid)
    end
  end

  it "renders a partial that holds the component's root element" do
    shell = mount('lp_shell')

    expect(shell.rendered).to have_css('section[live-id="test"][data-testid="shell"] h2', text: 'Inbox')

    shell.perform(:retitle)

    expect(shell.rendered).to have_css('section[live-id="test"] h2', text: 'Archive')
  end

  describe 'locals' do
    it "keeps the partial's own locals apart from the caller's" do
      component = mount('lp_locals')

      expect(component.rendered).to have_css('.badge.many', text: 'x: 2')
      expect(component.rendered).to have_css('[data-testid="css"]', text: 'outer/caller')
    end

    it 'gives self.x and x() the component, not a local of the caller' do
      component = mount('lp_locals')

      expect(component.rendered).to have_css('[data-testid="tone"]', text: 'comp|comp')
    end

    it 'gives local_assigns the locals passed at the call site, as Rails does' do
      rows = mount('lp_rows')

      expect(rows.rendered).to have_css('[data-testid="assigns"]', text: '[:label]|false|info')
    end

    it 'binds object: to a local named after the partial' do
      rows = mount('lp_rows')

      expect(rows.rendered).to have_css('[data-testid="summary"]', text: '2 todos')
    end
  end

  describe 'collection:' do
    it 'renders each item with its counter and iteration' do
      rows = mount('lp_rows')

      expect(rows.rendered.all('[data-testid="rows"] li').map(&:text)).to eq(
        ['0:false Milk (Todos)', '1:true Eggs (Todos)']
      )
    end

    it 'sends a keyed loop, so an added item sends its row' do
      rows = mount('lp_rows')

      rows.perform(:add)

      collection = changed_parts(rows).first
      expect(collection['o']).to eq([['u', 'todo-2', { '2' => 'false' }], ['a', 'todo-3', %w[3 2 true Bread Todos]]])
      expect(rows.rendered).to have_css('[data-testid="rows"] li#todo-3', text: '2:true Bread (Todos)')
    end

    it 'sends only the changed values of a partial rendered in a loop body' do
      rows = mount('lp_rows')

      rows.perform(:rename_first)

      expect(changed_parts(rows)).to eq([{ 'o' => [['u', 'todo-1', { '3' => 'Oat milk' }]] },
        { 'r' => { '0' => { '3' => 'Oat milk' } } }])
      expect(rows.rendered).to have_css('[data-testid="each"] li#todo-1', text: 'Oat milk')
    end
  end

  describe "t('.key')" do
    it "uses the partial's scope over the socket and on prerender" do
      rows = mount('lp_rows')
      rows.perform(:retitle)
      page = Capybara.string(ApplicationController.render(inline: "<%= live('lp_rows', id: 'page') %>"))

      [rows.rendered, page].each do |html|
        expect(html).to have_css('[data-testid="lp-hello"]', text: 'Hello from the partial')
      end
    end
  end

  it 'leaves the compiled template unchanged for plain .html.erb partials' do
    chat = mount('lp_chat')

    chat.perform(:rename)

    expect(changed_parts(chat)).to include("<span data-testid=\"plain\">Renamed</span>\n")
  end
end
