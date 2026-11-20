# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The root element of a template that starts with a comment' do
  include LiveCable::Testing

  %w[comment_led comment_led_plain].each do |name|
    it "gets the live attributes in #{name}, on the page" do
      html = ApplicationController.render(inline: "<%= live('#{name}', id: 'x') %>")

      expect(html).to match(/<div[^>]*\blive-id="x"[^>]*data-testid="root"/)
      expect(html).not_to match(/<h2[^>]*live-id/)
    end

    it "gets the live attributes in #{name}, over the socket" do
      expect(live_mount(name).rendered_html).to match(/<div[^>]*\blive-id="test"[^>]*data-testid="root"/)
    end
  end

  it 'gets the live attributes on the root when text follows the comment, on the page and over the socket' do
    html = ApplicationController.render(inline: "<%= live('comment_text_led', id: 'x') %>")
    expect(html).to match(/<div[^>]*\blive-id="x"[^>]*data-testid="root"/)
    expect(html).not_to match(/<h2[^>]*live-id/)

    expect(live_mount('comment_text_led').rendered_html).to match(/<div[^>]*\blive-id="test"[^>]*data-testid="root"/)
  end

  context 'when templates are annotated with their file names' do
    around do |example|
      ActionView::Base.annotate_rendered_view_with_filenames = true
      ActionView::LookupContext::DetailsKey.clear
      example.run
    ensure
      ActionView::Base.annotate_rendered_view_with_filenames = false
      ActionView::LookupContext::DetailsKey.clear
    end

    it "puts a plain .html.erb component's live attributes on its root element" do
      html = ApplicationController.render(inline: "<%= live('plain_erb', id: 'x') %>")

      expect(html).to include('<!-- BEGIN')
      expect(html).to match(/<div[^>]*\blive-id="x"[^>]*data-testid="plain-erb-component"/)
    end

    %w[annotated_row annotated_blank text_led].each do |name|
      it "puts them on the root, not on a partial inside it, in #{name}" do
        html = ApplicationController.render(inline: "<%= live('#{name}', id: 'x') %>")

        expect(html).to match(/<div[^>]*\blive-id="x"[^>]*data-testid="root"/)
        expect(html).not_to match(/<p[^>]*live-id/)
      end
    end
  end
end
