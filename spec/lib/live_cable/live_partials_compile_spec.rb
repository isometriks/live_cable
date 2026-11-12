# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Compiling live partials' do
  def compile(source, virtual_path: 'live/lp_err/host', identifier: "#{virtual_path}.html")
    identifier = Rails.root.join("app/views/#{identifier}.live.erb").to_s
    template = ActionView::Template.new(source, identifier, LiveCable::Rendering::Handler,
      locals: [], format: :html, virtual_path:)
    LiveCable::Rendering::Handler.call(template, source)
  end

  def compile_error(source, **)
    compile(source, **)
  rescue LiveCable::Rendering::LivePartials::CompileError => e
    e.message
  else
    raise 'expected a compile error'
  end

  host = 'app/views/live/lp_err/host.html.live.erb'

  describe 'locals' do
    it 'names a missing local and what the partial declares' do
      expect(compile_error("<div>\n<%= render 'live/lp_err/strict' %></div>")).to eq(
        "#{host}:2: render 'live/lp_err/strict' is missing label " \
        '(app/views/live/lp_err/_strict.html.live.erb declares locals: (label:, tone: "info"))'
      )
    end

    it 'names an unknown local' do
      expect(compile_error("<%= render 'live/lp_err/strict', label: 'a', size: 2 %>")).to include(
        "render 'live/lp_err/strict' passes unknown size:"
      )
    end

    it 'asks for a strict-locals comment when a partial without one is given locals' do
      expect(compile_error("<%= render 'live/lp_err/bare', title: 'a' %>")).to eq(
        "#{host}:1: passes title: to app/views/live/lp_err/_bare.html.live.erb, which declares no locals. " \
        'Live partials need a strict-locals comment: add <%# locals: (title:) -%> as its first line'
      )
    end

    it 'only takes keyword locals' do
      expect(compile_error("<%= render 'live/lp_err/positional' %>")).to include(
        '_positional.html.live.erb: locals: (label) declares positional or block arguments'
      )
    end

    it 'needs literal locals' do
      expect(compile_error("<%= render 'live/lp_err/strict', opts %>")).to include('passes its locals as opts')
      expect(compile_error("<%= render 'live/lp_err/strict', **opts %>")).to include('passes **opts')
      expect(compile_error("<%= render partial: 'live/lp_err/strict', locals: opts %>")).to include(
        'passes its locals as opts'
      )
    end
  end

  describe 'render forms' do
    it 'rejects a render that is not the whole of an output tag, with the rewrite' do
      expect(compile_error("<%= render 'live/lp_err/bare' if show %>")).to eq(
        "#{host}:1: render 'live/lp_err/bare' isn't the whole of an output tag, so it can't inline a live " \
        'partial (app/views/live/lp_err/_bare.html.live.erb). ' \
        "Write <% if show %><%= render 'live/lp_err/bare' %><% end %>"
      )
      expect(compile_error("<% render 'live/lp_err/bare' %>")).to include("isn't the whole of an output tag")
      expect(compile_error("<%= render('live/lp_err/bare') || 'none' %>")).to include("isn't the whole")
      expect(compile_error("<%= tag.div(render('live/lp_err/bare')) %>")).to include("isn't the whole")
    end

    it 'rejects a block render and layout:' do
      expect(compile_error("<%= render 'live/lp_err/bare' do %>x<% end %>")).to include('Live partials take no block')
      expect(compile_error("<%= render layout: 'live/lp_err/bare' do %>x<% end %>")).to include(
        "_bare.html.live.erb can't be rendered with layout:"
      )
    end

    it 'rejects options it cannot inline' do
      expect(compile_error("<%= render partial: 'live/lp_err/bare', spacer_template: 'x' %>")).to include(
        "can't be rendered with spacer_template: (live partials support locals:, object:, as: and collection:)"
      )
    end

    it 'names the full path for a bare name' do
      expect(compile_error("<%= render 'strict', label: 'a' %>")).to eq(
        "#{host}:1: render 'strict' reaches live partial app/views/live/lp_err/_strict.html.live.erb. " \
        "Bare partial names resolve against the controller's prefixes, which differ between the page and " \
        "the socket; use render 'live/lp_err/strict'"
      )
    end

    it 'leaves renders of plain partials, dynamic paths and comments alone' do
      expect do
        compile("<%= render 'live/lp/plain', label: 'a' %><%= render name %><%# render 'live/lp_err/bare' %>")
      end.not_to raise_error
    end

    it 'rejects object: with collection:' do
      expect(compile_error("<%= render partial: 'live/lp_err/bare', object: 1, collection: [] %>")).to include(
        'passes both object: and collection:'
      )
    end
  end

  describe 'constructs inside a partial' do
    {
      'yields' => '_yields.html.live.erb:1 can\'t yield',
      'returns' => '_returns.html.live.erb:1 can\'t `return`',
      'cached' => '_cached.html.live.erb:1 can\'t use `cache`',
      'ivar' => '_ivar.html.live.erb:1 uses @user',
      'read_before' => '_read_before.html.live.erb:1 reads `tone` before assigning it; use `self.tone`',
      'unclosed' => '_unclosed.html.live.erb:1: Opening tag `<div>`',
      'bad_ruby' => '_bad_ruby.html.live.erb:1: unexpected',
    }.each do |name, message|
      it "rejects #{name}" do
        expect(compile_error("<%= render 'live/lp_err/#{name}' %>")).to include(message)
      end
    end

    it 'allows HTML5 omitted end tags and comments at the end of tags' do
      expect { compile("<%= render 'live/lp_err/omitted' %><%= render 'live/lp_err/commented' %>") }.not_to raise_error
    end

    it 'rejects recursion with the chain' do
      expect(compile_error("<%= render 'live/lp_err/self' %>")).to start_with(
        'app/views/live/lp_err/_self.html.live.erb renders itself (live/lp_err/_self -> live/lp_err/_self)'
      )
      expect(compile_error("<%= render 'live/lp_err/cycle_a' %>")).to include(
        '(live/lp_err/_cycle_a -> live/lp_err/_cycle_b -> live/lp_err/_cycle_a)'
      )
    end
  end

  describe "the caller's locals" do
    it 'rejects a read of a local of the template that renders it' do
      expect(compile_error("<% item = 1 %><%= render 'live/lp_err/reads_item' %>")).to eq(
        'app/views/live/lp_err/_reads_item.html.live.erb:1 reads `item`, a local of the template that renders ' \
        "it (#{host}). Pass it as a local, or rename one of them."
      )
    end

    it 'rejects a read of a block parameter around the render' do
      expect(compile_error(<<~ERB)).to include('reads `item`, a local of the template that renders it')
        <ul><% items.each do |item| %><%= render 'live/lp_err/reads_item' %><% end %></ul>
      ERB
    end

    it 'rejects an assignment inside a block to a name the caller has' do
      expect(compile_error("<% total = 0 %><%= render 'live/lp_err/assigns_total' %>")).to include(
        '_assigns_total.html.live.erb:1 assigns `total` inside a block, and `total` is a local of the template'
      )
    end
  end

  describe 'partial files' do
    it 'rejects a plain partial next to a live one' do
      expect(compile_error("<%= render 'live/lp_err/dup' %>")).to include(
        '_dup.html.erb and app/views/live/lp_err/_dup.html.live.erb both exist'
      )
    end

    it 'rejects a request variant the caller has no sibling for' do
      expect(compile_error("<%= render 'live/lp_err/phone' %>")).to include(
        '_phone.html+phone.live.erb would be rendered for some requests, but ' \
        "#{host} has no +phone request variant of its own"
      )
    end

    it "inlines the caller's own request variant" do
      source = compile("<%= render 'live/lp_err/phone' %>", identifier: 'live/lp_err/host.html+phone')

      expect(source).to include('<p>phone</p>')
      expect(source).not_to include('desktop')
    end

    it 'rejects a locale the caller has no sibling for' do
      locales = I18n.available_locales
      I18n.available_locales = %i[en fr]

      expect(compile_error("<%= render 'live/lp_err/greet' %>")).to include(
        "_greet.fr.html.live.erb would be rendered for some requests, but #{host} has no fr locale of its own"
      )
    ensure
      I18n.available_locales = locales
    end
  end
end
