# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A child id in the parent render' do
  include LiveCable::Testing

  let(:markup) { '"></LiveCable><img src=x onerror=alert(1)><LiveCable child-live-id="x' }

  def parts(list)
    list.broadcasts(:_refresh).last[:_refresh][:p].join
  end

  it "doesn't put markup from a child's id into the page" do
    list = live_mount('tag_list')

    list.perform(:add, name: markup)

    expect(parts(list)).not_to include('<img')
    expect(list.rendered).to have_css('[data-testid="tag"]', exact_text: markup)
  end

  it "doesn't put markup from the id of a child whose render halted" do
    list = live_mount('tag_list')

    list.perform(:add, name: markup, hidden: '1')

    expect(parts(list)).not_to include('<img')
  end

  it 'renders a child whose id has a quote' do
    list = live_mount('tag_list')

    list.perform(:add, name: 'say "hi"')

    expect(list.rendered).to have_css('[data-testid="tag"]', exact_text: 'say "hi"')
  end
end
