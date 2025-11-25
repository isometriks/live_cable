# frozen_string_literal: true

module LiveCable
  class Engine < ::Rails::Engine
    config.before_configuration do |app|
      Rails.autoloaders.main.push_dir(app.root.join("app/live"), namespace: Live)
    end
  end
end
