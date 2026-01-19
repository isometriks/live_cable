# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require 'bundler/setup'
require_relative 'dummy/config/environment'
require 'rspec/rails'
require 'capybara/rspec'

# Configure Capybara to use Puma server
Capybara.server = :puma, { Silent: true }

# Use data-testid
Capybara.configure do |config|
  config.test_id = 'data-testid'
end

# Configure Capybara for system tests
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,1400')
  options.add_argument('--disable-search-engine-choice-screen')

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

Capybara.javascript_driver = :headless_chrome
Capybara.default_driver = :rack_test
Capybara.app = Dummy::Application

# Increase wait time for JavaScript/WebSocket operations
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:each, type: :system) do
    driven_by :headless_chrome
  end

  # Ensure ActionCable is properly set up for tests
  config.before(:each, type: :system) do
    ActionCable.server.restart
  end

  config.after(:each, type: :system) do
    ActionCable.server.restart
  end
end
