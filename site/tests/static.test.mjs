import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, stat, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const root = new URL('../', import.meta.url);
test('entry points and local assets resolve under the GitHub repository subpath', async () => {
  const html = await readFile(new URL('index.html', root), 'utf8');
  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /<h1>/);
  assert.match(html, /releases\/latest/);
  for (const match of html.matchAll(/(?:src|href)="(\.\/[^"#]+)"/g)) {
    assert.ok((await stat(new URL(match[1], root))).isFile(), match[1]);
  }
  const js = await readFile(new URL('main.js', root), 'utf8');
  for (const match of js.matchAll(/\.\/assets\/([a-z0-9.-]+)/g)) {
    assert.ok((await stat(new URL(`assets/${match[1]}`, root))).isFile(), match[1]);
  }
  assert.doesNotMatch(html, /(?:src|href)="\/(?!\/)/, 'no broken root-relative paths on project Pages');
  assert.ok((await stat(new URL('assets/social.jpg', root))).isFile());
});
test('the published site is self contained and has a small asset budget', async () => {
  const files = await readdir(new URL('assets/', root));
  const sizes = await Promise.all(files.map(name => stat(new URL(`assets/${name}`, root))));
  assert.ok(sizes.reduce((n, s) => n + s.size, 0) < 1_500_000, 'keep the complete visual asset set below 1.5 MB');
  const html = await readFile(new URL('index.html', root), 'utf8');
  assert.doesNotMatch(html, /<script[^>]+src="https?:/);
  assert.match(html, /<noscript>/);
  assert.match(html, /aria-live="polite"/);
  const css = await readFile(new URL('style.css', root), 'utf8');
  assert.match(css, /prefers-reduced-motion:reduce/);
});
