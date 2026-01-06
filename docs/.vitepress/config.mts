import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "LiveCable",
  description: "Phoenix LiveView-style components for Ruby on Rails with ActionCable",
  themeConfig: {
    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API', link: '/api/component' }
    ],

    sidebar: [
      {
        text: 'Guide',
        items: [
          { text: 'Getting Started', link: '/guide/getting-started' },
          { text: 'Installation', link: '/guide/installation' },
          { text: 'Components', link: '/guide/components' },
          { text: 'Reactive Variables', link: '/guide/reactive-variables' },
          { text: 'Lifecycle Callbacks', link: '/guide/lifecycle-callbacks' },
          { text: 'Actions & Events', link: '/guide/actions-events' },
          { text: 'Compound Components', link: '/guide/compound-components' },
          { text: 'Streaming', link: '/guide/streaming' },
          { text: 'Architecture', link: '/guide/architecture' }
        ]
      },
      {
        text: 'API Reference',
        items: [
          { text: 'Component', link: '/api/component' },
          { text: 'Helpers', link: '/api/helpers' }
        ]
      }
    ],

    socialLinks: [
      { icon: 'github', link: 'https://github.com/isometriks/live_cable' }
    ]
  }
})
