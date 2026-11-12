# frozen_string_literal: true

require 'rails_helper'

# An inlined live partial must render exactly what the same partial renders
# as a plain .html.erb partial. live/lp_parity renders the partials in
# live/lp_parity/ and live/lp_parity_plain renders .html.erb copies of them,
# so the two components' HTML must match byte for byte. This also guards the
# Herb internals the inliner relies on (see Compiler#inline_partial).
RSpec.describe 'Live partial parity' do
  include LiveCable::Testing

  views = Rails.root.join('app/views/live')

  def without_root_attributes(html)
    html.sub(/\A<div [^>]*>/, '<div>').gsub(/(name="authenticity_token" value=")[^"]*/, '\\1')
  end

  it 'keeps the plain copies identical to the live partials' do
    expect(File.read(views.join('lp_parity_plain.html.live.erb'))).to eq(
      File.read(views.join('lp_parity.html.live.erb')).gsub('live/lp_parity/', 'live/lp_parity_plain/')
    )

    Dir[views.join('lp_parity/_*.html.live.erb')].each do |path|
      copy = views.join('lp_parity_plain', File.basename(path).sub('.html.live.erb', '.html.erb'))
      expect(File.read(copy)).to eq(File.read(path).gsub('live/lp_parity/', 'live/lp_parity_plain/'))
    end
  end

  [true, false].each do |structured|
    context(structured ? 'with structured blocks' : 'without structured blocks') do
      before do
        skip 'Rails 7.1 gives a strict-locals .html.erb partial no local_assigns' if ActionView.gem_version < Gem::Version.new('7.2')
      end

      around do |example|
        previous = LiveCable.configuration.structured_blocks
        LiveCable.configuration.structured_blocks = structured
        ActionView::LookupContext::DetailsKey.clear
        example.run
      ensure
        LiveCable.configuration.structured_blocks = previous
        ActionView::LookupContext::DetailsKey.clear
      end

      it 'renders the same HTML over the socket' do
        live = live_mount('lp_parity')
        plain = live_mount('lp_parity_plain')

        expect(without_root_attributes(live.rendered_html)).to eq(without_root_attributes(plain.rendered_html))

        live.perform(:bump)
        plain.perform(:bump)

        expect(live.rendered).to have_css('.badge', text: 'in if: 3')
        expect(without_root_attributes(live.rendered_html)).to eq(without_root_attributes(plain.rendered_html))
      end

      it 'renders the same HTML on prerender' do
        live, plain = %w[lp_parity lp_parity_plain].map do |name|
          ApplicationController.render(inline: "<%= live('#{name}', id: 'page') %>")
        end

        expect(without_root_attributes(live)).to eq(without_root_attributes(plain))
      end
    end
  end
end
