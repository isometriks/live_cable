# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The cache helper in a .live.erb template' do
  include LiveCable::Testing

  around do |example|
    store = ActionController::Base.cache_store
    caching = ActionController::Base.perform_caching
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.perform_caching = true
    example.run
  ensure
    ActionController::Base.cache_store = store
    ActionController::Base.perform_caching = caching
  end

  def cached_keys
    ActionController::Base.cache_store.instance_variable_get(:@data).keys
  end

  def prerender(component, id: 'page')
    Capybara.string(ApplicationController.render(inline: "<%= live('#{component}', id: '#{id}') %>"))
  end

  describe 'keys' do
    it 'keeps two components that use the same key apart over the socket' do
      rows = live_mount('cached_rows')
      header = live_mount('cached_header', connection: rows.connection)

      expect(rows.rendered).to have_css('[data-testid="header"]', exact_text: 'Rows')
      expect(header.rendered).to have_css('[data-testid="header"]', exact_text: 'Header')
    end

    it 'keeps two components that use the same key apart on a page load' do
      page = Capybara.string(
        ApplicationController.render(inline: "<%= live('cached_rows', id: 'a') %><%= live('cached_header', id: 'b') %>")
      )

      expect(page).to have_css('[live-id="a"] [data-testid="header"]', exact_text: 'Rows')
      expect(page).to have_css('[live-id="b"] [data-testid="header"]', exact_text: 'Header')
    end

    it "carries the component template's digest on page loads and socket renders alike" do
      prerender('cached_header')
      live_mount('cached_header')

      expect(cached_keys).to match([%r{\Aviews/live/cached_header:\h{32}/cached-rows-header\z}])
    end
  end

  describe 'around a component rendered with live(...)' do
    let(:child_a) { '[data-testid="row-a"] > [data-testid="child-component"]' }

    it 'renders the child on a page loaded after a socket render' do
      live_mount('cached_rows')

      expect(prerender('cached_rows')).to have_css(child_a, text: 'Child a')
    end

    it 'sends the child to a connection that renders the fragment after another one' do
      live_mount('cached_rows')

      expect(live_mount('cached_rows', id: 'other').rendered).to have_css(child_a, text: 'Child a')
    end

    it 'renders the child on the socket after a page load' do
      prerender('cached_rows')
      rows = live_mount('cached_rows')

      expect(rows.component.owned_children.map(&:live_id)).to contain_exactly('child/row-a', 'child/row-b')
      expect(rows.rendered).to have_css(child_a, text: 'Child a')
    end

    it 'keeps the children whose fragment the last render already held' do
      rows = live_mount('cached_rows')

      rows.perform(:add)

      expect(rows.component.owned_children.map(&:live_id)).to contain_exactly(*%w[child/row-a child/row-b child/row-c])
      expect(rows.rendered).to have_css(child_a, text: 'Child a')
    end

    it 'still caches the fragments that render no child' do
      live_mount('cached_rows')

      expect(cached_keys.grep(/cached-rows-header/).size).to eq(1)
      expect(cached_keys.grep(%r{cached-row/})).to be_empty
    end

    it 'still caches a page fragment around a component' do
      ApplicationController.render(inline: "<% cache 'page' do %><%= live('cached_rows', id: 'page') %><% end %>")

      expect(cached_keys.grep(%r{/page\z}).size).to eq(1)
    end
  end
end
