# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'live_cable'
  s.version     = '0.0.1'
  s.summary     = 'Live Components over ActionCable'
  s.description = ''
  s.authors     = ['Craig Blanchette']
  s.email       = 'craig.blanchette@gmail.com'
  s.files       = Dir[
    #'README.md',
    'lib/**/*'
  ]

  s.metadata['allowed_push_host'] = 'https://rubygems.org'
  s.metadata['rubygems_mfa_required'] = 'true'
  s.metadata['source_code_uri'] = 'https://github.com/isometriks/live_cable'

  s.homepage    = 'https://rubygems.org/gems/live_cable'
  s.required_ruby_version = '>= 3.4'
end
