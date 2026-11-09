import { defineConfig } from 'astro/config';

const site = process.env.SITE_URL || 'https://4zth4r00t.github.io';
const base = process.env.BASE_PATH || '/hackers-fight-club-ad-lab';

export default defineConfig({
  site,
  base,
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'always' },
  compressHTML: true,
  vite: { server: { fs: { allow: ['..'] } } },
});
