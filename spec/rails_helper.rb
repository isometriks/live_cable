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

# The dummy app's importmap pulls Stimulus, ActionCable and morphdom over the
# network, so the gap between "server-rendered HTML is on screen" and "Stimulus
# has attached its handlers" is however long those fetches take. Buttons exist
# in the initial HTML, so clicking early succeeds but does nothing - the event
# has no listener yet and is silently dropped.
#
# Components render data-live-status-value="disconnected" server-side and flip
# to "subscribed" once ActionCable connects, so wait on that before interacting.
module LiveSystemHelpers
  def wait_for_live_components(wait: Capybara.default_max_wait_time)
    # Deliberately a predicate, not an expectation: pages without live
    # components return immediately, and a component that never connects still
    # fails on the example's own assertion rather than on a new error here.
    page.has_no_css?('[data-live-status-value="disconnected"]', wait:)
  end

  def visit(*, **)
    super
    wait_for_live_components
  end
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include LiveSystemHelpers, type: :system

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
