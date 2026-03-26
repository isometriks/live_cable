# frozen_string_literal: true

pin '@rails/actioncable', to: 'actioncable.esm.js'
pin 'morphdom', to: 'https://ga.jspm.io/npm:morphdom@2.7.8/dist/morphdom-esm.js'

pin '@isometriks/live_cable/controller', to: 'controllers/live_controller.js'
pin '@isometriks/live_cable/blessing', to: 'live_cable_blessing.js'
pin '@isometriks/live_cable/subscriptions', to: 'subscriptions.js'
pin '@isometriks/live_cable/observer', to: 'observer.js'
pin '@isometriks/live_cable/dom', to: 'dom.js'
pin '@isometriks/live_cable', to: 'live_cable.js'
