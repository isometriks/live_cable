# frozen_string_literal: true

# Pins for the dummy app used by the system tests.
#
# Everything here resolves through Propshaft to a local file, so the browser
# never reaches out to a CDN while tests run. That matters more than it looks:
# until Stimulus and ActionCable have loaded, no live component has an event
# handler attached, so clicks are silently dropped and websocket-delivered
# updates never arrive. When those came from cdn.jsdelivr.net, a slow or blocked
# fetch surfaced as unreproducible system-test failures in CI.
#
# @rails/actioncable and the @isometriks/live_cable modules are pinned by the
# gem's own config/importmap.rb, which the engine appends to importmap.paths.

# Shipped by the stimulus-rails gem.
pin '@hotwired/stimulus', to: 'stimulus.min.js'

# Served from node_modules (see config/application.rb) rather than committed to
# vendor/javascript, so package.json stays the single source of truth. There is
# no Ruby gem to fall back on here: turbo-rails morphs with idiomorph, bundled
# inside turbo.js, so it exposes nothing importable for morphdom.
#
# This re-pins the jspm.io URL set by the gem's config/importmap.rb - this file
# is drawn last, so it takes precedence.
pin 'morphdom', to: 'morphdom-esm.js'
