# frozen_string_literal: true

module LiveCable
  class Engine < ::Rails::Engine
    config.before_configuration do |app|
      # Setup autoloader to use Live namespace for components
      Rails.autoloaders.main.push_dir(app.root.join('app/live'), namespace: Live)

      # Add LiveCable to importmap
      app.config.importmap.paths << root.join('config/importmap.rb')
    end

    initializer 'live_cable.assets_precompile' do |app|
      app.config.assets.precompile << %w[live_cable/**/*.js]
    end
  end
end
