import LiveObserver from 'live_cable_observer'
import SubscriptionManager from "live_cable_subscriptions"
import DOM from "live_cable_dom"

const observer = new LiveObserver()
observer.start()

document.addEventListener('turbo:visit', () => {
  SubscriptionManager.clear()
})

document.addEventListener('turbo:load', () => {
  DOM.mutate(document.documentElement)
})
