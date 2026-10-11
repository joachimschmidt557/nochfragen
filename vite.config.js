import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { paraglideVitePlugin } from '@inlang/paraglide-js';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    paraglideVitePlugin({
      project: './project.inlang',
      outdir: './src/lib/paraglide',
      strategy: ['url', 'baseLocale']
    }),

    sveltekit({
      preprocess: [vitePreprocess({ script: true })],
      adapter: adapter(),
      paths: { relative: false },
      csp: { directives: { 'script-src': ['self'] } },
      prerender: { entries: ['/', '/de/'] }
    })
  ]
});
