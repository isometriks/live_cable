# frozen_string_literal: true

require_relative 'lib/live_cable/version'

Gem::Specification.new do |s|
  s.name        = 'live_cable'
  s.version     = LiveCable::VERSION
  s.summary     = 'Live Components over ActionCable'
  s.description = 'Phoenix LiveView-style live components for Ruby on Rails. Server-side state management ' \
                  'over ActionCable with reactive variables, automatic change detection, and Stimulus integration.'
  s.authors     = ['Craig Blanchette']
  s.email       = 'craig.blanchette@gmail.com'
  s.license     = 'MIT'
  s.files       = Dir[
    'README.md',
    'LICENSE',
    'app/**/*',
    'lib/**/*',
    'config/**/*'
  ]

  s.metadata['allowed_push_host'] = 'https://rubygems.org'
  s.metadata['rubygems_mfa_required'] = 'true'
  s.metadata['source_code_uri'] = 'https://github.com/isometriks/live_cable'

  s.homepage = 'https://rubygems.org/gems/live_cable'
  s.required_ruby_version = '>= 3.4'

  s.add_dependency 'actioncable', '>= 7.0'
  s.add_dependency 'actionview', '>= 7.0'
  s.add_dependency 'activemodel', '>= 7.0'
  s.add_dependency 'activesupport', '>= 7.0'
  s.add_dependency 'herb', '~> 0.8'
  s.add_dependency 'zeitwerk', '~> 2.6'
end
