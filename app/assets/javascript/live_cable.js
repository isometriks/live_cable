import LiveObserver from 'live_cable_observer'
import SubscriptionManager from 'live_cable_subscriptions'
import DOM from 'live_cable_dom'

const observer = new LiveObserver()
observer.start()

document.addEventListener('turbo:before-render', (event) => {
  SubscriptionManager.prune(event.detail.newBody)
})

document.addEventListener('turbo:load', () => {
  DOM.mutate(document.documentElement)
  updateCacheControl()
})

/**
 * Ensure pages with live components are never stored in Turbo's page cache.
 *
 * Turbo's back/forward cache restores a snapshot of the page taken at
 * navigate time. A restored snapshot would reconnect Stimulus controllers
 * to subscriptions that were already closed server-side, causing a cold
 * re-render that may fail. Preventing caching forces a fresh server fetch
 * on back/forward, so components are always pre-rendered before their
 * ActionCable subscription connects.
 *
 * If the developer has already set a turbo-cache-control meta tag (e.g.
 * "no-store"), that value is left untouched so they can override this
 * behaviour per-page.
 */
function updateCacheControl() {
  // A meta tag without our marker was placed by the developer — leave it alone
  const devMeta = document.querySelector('meta[name="turbo-cache-control"]:not([data-live-cable])')
  if (devMeta) return

  const ourMeta = document.querySelector('meta[name="turbo-cache-control"][data-live-cable]')
  const hasLiveComponents = !!document.querySelector('[data-controller~="live"]')

  if (hasLiveComponents && !ourMeta) {
    const meta = document.createElement('meta')
    meta.name = 'turbo-cache-control'
    meta.content = 'no-cache'
    meta.dataset.liveCable = ''
    document.head.appendChild(meta)
  } else if (!hasLiveComponents && ourMeta) {
    ourMeta.remove()
  }
}

export default observer
