# frozen_string_literal: true

require 'simplecov'
require 'simplecov-json'

SimpleCov.start do
  enable_coverage :branch

  skip '/spec/'
  skip '/node_modules/'

  # Track the gem's own code (cover also includes unloaded files on disk,
  # the historical track_files behaviour)
  cover 'lib/**/*.rb', 'app/**/*.rb'

  # Name the command so results can be merged across CI jobs
  command_name ENV.fetch('COVERAGE_NAME', 'rspec').to_s

  formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::JSONFormatter]
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(formatters)
end

require 'bundler/setup'
require 'active_record'
require 'action_cable'

# Setup test database
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
)

# Load the gem
require_relative '../lib/live_cable'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed
end
