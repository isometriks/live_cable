# frozen_string_literal: true
require "zeitwerk"

module LiveCable
  class Engine < ::Rails::Engine
    initializer 'live_cable.paths' do |app|
      live_path = app.root.join('app/live')

      if Dir.exist?(live_path)
        loader = Zeitwerk::Loader.for_gem
        loader.setup
        loader.eager_load_dir(live_path)
      end
    end

    config.to_prepare do
      LiveCable::Registry.reset!

      live_path = Rails.root.join('app/live')

      if Dir.exist?(live_path) && !Rails.configuration.eager_load
        Rails.autoloaders.main.eager_load_dir(live_path.to_s)
      end
    end
  end
end
