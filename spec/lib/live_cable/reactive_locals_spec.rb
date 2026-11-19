# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactive variables as locals in a .live.erb template' do
  include LiveCable::Testing

  def mount(tmpl)
    @component = live_mount('reactive_locals', tmpl:)
  end

  def text(testid)
    @component.rendered.find(%([data-testid="#{testid}"])).text.strip
  end

  it 'reads the reactive on the right of an assignment to its own name' do
    mount('self_assign')

    expect(text('sorted')).to eq('a,b,c')

    @component.perform(:add_item)

    expect(text('sorted')).to eq('a,ab,b,c')
  end

  it 'adds to the reactive with an operator assignment' do
    mount('op_assign')

    expect(text('count')).to eq('11')

    @component.perform(:bump)

    expect(text('count')).to eq('12')
  end

  it 'keeps a set reactive through ||= and falls back once it is nil' do
    mount('or_assign')

    expect(text('nickname')).to eq('Ann')

    @component.perform(:clear_nickname)

    expect(text('nickname')).to eq('nobody')
  end

  it 'gives the template local_assigns with the reactive values, not the reassigned locals' do
    mount('local_assigns')

    expect(text('count')).to eq('11')
    expect(text('assigns')).to eq('1 true')

    @component.perform(:bump)

    expect(text('assigns')).to eq('2 true')
  end

  it 'fetches from local_assigns' do
    mount('local_assigns')

    expect(text('fetch')).to eq('1 none')

    @component.perform(:bump)

    expect(text('fetch')).to eq('2 none')
  end

  it 'answers defined? for a reactive as a local and for a component method as a method' do
    mount('defined')

    expect(text('defined')).to eq('local-variable method')
  end

  it 'reads, reassigns and re-renders a reactive named like an Object method' do
    mount('kernel_name')

    expect(text('display')).to eq('compact')
    expect(text('shouted')).to eq('compact!')

    @component.perform(:widen)

    expect(text('display')).to eq('wide')
    expect(text('shouted')).to eq('wide!')
  end

  it 'keeps the reactive when an earlier tag reassigns its name in an if that does not run' do
    mount('earlier_reassign')

    expect(text('label')).to eq('plain')

    @component.perform(:toggle)

    expect(text('label')).to eq('PLAIN')

    @component.perform(:relabel)

    expect(text('label')).to eq('FANCY')
  end

  it 'renders a reactive read only inside an if once the if runs' do
    mount('false_if')

    expect(@component.rendered).to have_no_css('[data-testid="hidden"]')

    @component.perform(:bump_hidden)
    @component.perform(:toggle)

    expect(text('hidden')).to eq('1')

    @component.perform(:bump_hidden)

    expect(text('hidden')).to eq('2')
  end

  it 'keeps what a block adds to a reactive for later tags' do
    mount('block_write')

    expect(text('total')).to eq('106')

    @component.perform(:add_row)

    expect(text('total')).to eq('110')
  end

  it 'leaves out the parts that read only unchanged reactives' do
    mount('skip')
    @component.clear_broadcasts

    @component.perform(:bump_other)

    sent = @component.broadcasts(:_refresh).sole[:_refresh][:p].compact
    expect(sent).to include('1')
    expect(sent).not_to include('compact')
    expect(text('label')).to eq('PLAIN')
  end

  it 're-renders a part reading a reassigned reactive when the reactive changes' do
    mount('skip')

    @component.perform(:relabel)

    expect(text('label')).to eq('FANCY')
  end

  it 'renders the same on the page load' do
    html = ApplicationController.render(inline: "<%= live('reactive_locals', id: 'page', tmpl: 'local_assigns') %>")
    page = Capybara.string(html)

    expect(page).to have_css('[data-testid="count"]', exact_text: '11')
    expect(page).to have_css('[data-testid="assigns"]', exact_text: '1 true')
  end
end
