# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Comments and heredocs in output tags' do
  include LiveCable::Testing

  let(:component) { live_mount('expression_comments') }

  it 'renders an expression followed by a comment' do
    expect(component.rendered).to have_css('[data-testid="comment"]', exact_text: '1')
    expect(component.rendered).to have_css('[data-testid="raw-comment"]', exact_text: '1')
  end

  it 'renders a heredoc' do
    expect(component.rendered).to have_css('[data-testid="heredoc"]', exact_text: 'Count 1')
  end

  it 'renders a block whose opening tag ends in a comment' do
    expect(component.rendered).to have_css('[data-testid="block"] b', exact_text: '1')
  end

  it 're-renders them when the value changes' do
    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="comment"]', exact_text: '2')
    expect(component.rendered).to have_css('[data-testid="heredoc"]', exact_text: 'Count 2')
    expect(component.rendered).to have_css('[data-testid="block"] b', exact_text: '2')
  end

  it 'renders them on the page' do
    page = Capybara.string(ApplicationController.render(inline: "<%= live('expression_comments', id: 'page') %>"))

    expect(page).to have_css('[data-testid="comment"]', exact_text: '1')
    expect(page).to have_css('[data-testid="heredoc"]', exact_text: 'Count 1')
    expect(page).to have_css('[data-testid="block"] b', exact_text: '1')
  end
end
