# frozen_string_literal: true

require 'rails'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'action_cable/engine'
require 'propshaft'
require_relative '../../spec_helper'

Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.secret_key_base = 'test_secret_key_base'
    config.hosts.clear

    # Session configuration
    config.session_store :cookie_store, key: '_dummy_session'
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, config.session_options

    # ActionCable configuration
    config.action_cable.url = '/cable'
    config.action_cable.mount_path = '/cable'
    config.action_cable.disable_request_forgery_protection = true

    # Asset configuration with Propshaft
    config.assets.paths << Rails.root.join('../../../app/assets/javascript')
    # Stimulus and ActionCable ship their JavaScript inside Ruby gems, but
    # morphdom has no gem equivalent. Rather than committing a copy under
    # vendor/javascript (the usual importmap workflow), it is served straight
    # out of node_modules so package.json stays the single source of truth for
    # its version. This means `yarn install` is a prerequisite for the system
    # tests - see the ruby_tests job in .github/workflows/ci.yml.
    config.assets.paths << Rails.root.join('../../node_modules/morphdom/dist')
    config.assets.prefix = '/assets'

    # View paths
    config.paths['app/views'].unshift(File.expand_path('../../../app/views', __dir__))

    # Component paths
    config.autoload_paths << File.expand_path('../app/components', __dir__)

    # Logging
    config.log_level = :debug
    config.logger = Logger.new($stdout)
  end
end
