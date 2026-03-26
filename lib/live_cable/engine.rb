# frozen_string_literal: true

module LiveCable
  class Engine < ::Rails::Engine
    config.before_configuration do |app|
      # Setup autoloader to use Live namespace for components
      live_component_dir = app.root.join('app/live')

      if live_component_dir.directory?
        Rails.autoloaders.main.push_dir(live_component_dir, namespace: Live)
      else
        warn("[LiveCable Warning] #{live_component_dir} does not exist for components.")
      end

      # Add LiveCable to importmap
      app.config.importmap.paths << root.join('config/importmap.rb')
    end

    initializer 'live_cable.assets_precompile' do |app|
      app.config.assets.precompile << %w[live_cable/**/*.js]
    end

    initializer 'live_cable.renderer' do |_app|
      ActionView::Template.register_template_handler(:'live.erb', Rendering::Handler)
    end

    initializer 'live_cable.active_record' do
      ActiveSupport.on_load :active_record do
        include ModelObserver
      end
    end
  end
end
