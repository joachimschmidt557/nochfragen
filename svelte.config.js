import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: [vitePreprocess({ script: true })],
  kit: {
    adapter: adapter(),
    paths: {
      relative: false
    },
    csp: {
      directives: {
        'script-src': ['self']
      }
    },
    prerender: {
      entries: ['/', '/de/']
    }
  }
};

export default config;
