# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'live_cable'
  s.version     = '0.0.1'
  s.summary     = 'Live Components over ActionCable'
  s.description = ''
  s.authors     = ['Craig Blanchette']
  s.email       = 'craig.blanchette@gmail.com'
  s.files       = Dir[
    # 'README.md',
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
  s.add_dependency 'herb', '~> 0.8', '< 0.9'
  s.add_dependency 'zeitwerk', '~> 2.6'
end
