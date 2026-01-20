import { defineConfig } from 'vitest/config'
import path from 'path'

export default defineConfig({
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./test/setup.js']
  },
  resolve: {
    alias: {
      'live_cable_dom': path.resolve(__dirname, './app/assets/javascript/dom.js'),
    },
  }
})
