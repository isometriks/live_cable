# frozen_string_literal: true

require 'rails_helper'

# Every .live.erb fixture compiles to the Ruby it compiled to before
# collection streams, so the stream hooks in the compiler change nothing for
# a template without a stream. The digests come from that compile; refresh
# them with LIVE_CABLE_RECORD_COMPILES=1 only for a change that means to
# alter compiled output.
RSpec.describe 'Compiled template equivalence' do
  digests_path = File.expand_path('../../../fixtures/compiled_templates.yml', __dir__)
  views = Rails.root.join('app/views')
  fixtures = Dir[views.join('**/*.live.erb')]

  def compiled_digest(path, views)
    source = File.read(path)
    virtual_path = Pathname(path).relative_path_from(views).to_s.sub(/\..*\z/, '')
    template = ActionView::Template.new(source, path, LiveCable::Rendering::Handler,
      locals: [], format: :html, virtual_path:)

    output = begin
      LiveCable::Rendering::Handler.call(template, source)
    rescue LiveCable::Error => e
      "#{e.class}: #{e.message}"
    end

    Digest::SHA256.hexdigest(output)
  end

  def compiled_digests(fixtures, views, structured:)
    previous = LiveCable.configuration.structured_blocks
    LiveCable.configuration.structured_blocks = structured
    fixtures.to_h { |path| [Pathname(path).relative_path_from(views).to_s, compiled_digest(path, views)] }
  ensure
    LiveCable.configuration.structured_blocks = previous
  end

  it 'compiles every fixture byte for byte as before' do
    current = %w[structured plain].to_h do |mode|
      [mode, compiled_digests(fixtures, views, structured: mode == 'structured')]
    end

    if ENV['LIVE_CABLE_RECORD_COMPILES']
      File.write(digests_path, current.to_yaml)
      skip 'recorded'
    end

    recorded = YAML.load_file(digests_path)

    %w[structured plain].each do |mode|
      expected = recorded.fetch(mode).slice(*current[mode].keys)
      expect(current[mode].slice(*expected.keys)).to eq(expected), "#{mode} compiles changed"
    end
  end
end
