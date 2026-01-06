---
layout: home

hero:
  name: "LiveCable"
  text: "Phoenix LiveView for Rails"
  tagline: Server-side state management with real-time updates using ActionCable and Stimulus
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: View on GitHub
      link: https://github.com/isometriks/live_cable

features:
  - title: Server-Side State
    details: Component state is maintained on the server using ActionCable, eliminating the need for client-side state management
  - title: Reactive Variables
    details: Automatic UI updates when state changes with smart change tracking for Arrays, Hashes, and ActiveRecord models
  - title: Persistent Connections
    details: WebSocket connections persist across page navigations for better performance and state preservation
  - title: Action Dispatch
    details: Call server-side methods from the frontend with built-in parameter handling and security
  - title: Lifecycle Callbacks
    details: Hook into component lifecycle events with ActiveModel::Callbacks (before/after/around)
  - title: Stimulus Integration
    details: Seamless integration with Stimulus controllers and blessing API for custom interactions
---

