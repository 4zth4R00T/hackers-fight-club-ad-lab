import { execSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const root = process.cwd();
const step = (n, t) => console.log(`\n[${n}/4] ${t}`);

step(1, 'Tailwind');
execSync('npx tailwindcss -i ./src/styles.css -o ./public/app.css --minify', { stdio: 'inherit' });

step(2, 'Astro');
execSync('npx astro build', { stdio: 'inherit' });

step(3, 'Astro bundle dependencies');
for (const p of ['cookie']) {
  const from = join(root, 'node_modules', 'astro', 'node_modules', p);
  const to = join(root, 'dist-astro', 'node_modules', p);
  if (!existsSync(from)) {
    console.log(`   ${p}: using the top level copy`);
    continue;
  }
  rmSync(to, { recursive: true, force: true });
  mkdirSync(join(root, 'dist-astro', 'node_modules'), { recursive: true });
  cpSync(from, to, { recursive: true });
  console.log(`   ${p}: copied into the bundle`);
}

step(4, 'TypeScript');
execSync('npx tsc -p tsconfig.json', { stdio: 'inherit' });

console.log('\nBuild complete.\n');
