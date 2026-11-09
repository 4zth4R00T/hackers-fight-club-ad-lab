import { defineConfig } from 'astro/config';
import node from '@astrojs/node';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'middleware' }),
  srcDir: './astro',
  publicDir: './public',
  outDir: './dist-astro',
  build: { assets: 'assets' },
  server: { host: false },
  trailingSlash: 'ignore',
  compressHTML: true,
  devToolbar: { enabled: false },
  vite: {
    build: { sourcemap: false },
    logLevel: 'warn',
  },
});
