import LiveController from "live_cable_controller"

export default function LiveCableBlessing(constructor) {
  Object.assign(constructor.prototype, {
    liveCableAction(action, params = {}) {
      this.context.logDebugActivity("liveCableAction", {
        action,
        params,
      })

      this.dispatch('call', {
        detail: {
          action,
          params,
        },
        prefix: null,
      })
    }
  })
}
