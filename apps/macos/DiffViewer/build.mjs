import { build } from 'esbuild';
import { cpSync, rmSync } from 'node:fs';

const out = '../vendor/diff-viewer';
rmSync(out, { recursive: true, force: true });
await build({
  entryPoints: { viewer: 'src/viewer.ts', worker: '@pierre/diffs/worker/worker.js' },
  outdir: out,
  bundle: true,
  splitting: true,
  format: 'esm',
  minify: true,
  target: 'safari26',
  chunkNames: 'chunks/[name]-[hash]',
  legalComments: 'none',
  logLevel: 'warning',
});
cpSync('src/index.html', `${out}/index.html`);
