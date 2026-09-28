// Writes brand/tokens/tokens.css from brand/tokens/tokens.json, the single source of truth. The website copies the
// result with site/tools/sync-brand.mjs; the app's Theme.swift and Motion.swift hold the same values.
//   node brand/scripts/tokens/build.mjs           write tokens.css
//   node brand/scripts/tokens/build.mjs --check   exit 1 when tokens.css is out of date
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const TOKENS_DIR = fileURLToPath(new URL('../../tokens/', import.meta.url));

const entries = (group) => Object.entries(group).filter(([key]) => !key.startsWith('$'));

/** A token's value, following {path.to.token} references. */
export function resolveValue(tokens, value) {
  const match = typeof value === 'string' && value.match(/^\{(.+)\}$/);
  if (!match) return value;
  const token = match[1].split('.').reduce((node, key) => node?.[key], tokens);
  if (!token) throw new Error(`unknown token reference ${value}`);
  return resolveValue(tokens, token.$value);
}

/**
 * SwiftUI's spring(response:dampingFraction:) as a CSS linear() easing, sampled evenly until the motion has settled
 * within 0.1 % of its target, and that settling time in seconds (rounded up to 10 ms).
 */
export function springEasing({ response, dampingFraction: zeta }, samples = 40) {
  const w0 = (2 * Math.PI) / response;
  let position;
  let envelope;
  if (zeta < 1) {
    const wd = w0 * Math.sqrt(1 - zeta * zeta);
    position = (t) => 1 - Math.exp(-zeta * w0 * t) * (Math.cos(wd * t) + ((zeta * w0) / wd) * Math.sin(wd * t));
    envelope = Math.hypot(1, (zeta * w0) / wd);
  } else {
    position = (t) => 1 - Math.exp(-w0 * t) * (1 + w0 * t);
    envelope = 4; // bounds (1 + w0 t) e^(-w0 t / 2) for every t
  }
  const decay = zeta < 1 ? zeta * w0 : w0 / 2;
  const seconds = Math.ceil((Math.log(envelope / 0.001) / decay) * 100) / 100;
  const points = [];
  for (let i = 0; i <= samples; i += 1) {
    const value = i === samples ? 1 : position((i / samples) * seconds);
    points.push(Number(value.toFixed(4)).toString());
  }
  return { easing: `linear(${points.join(', ')})`, seconds };
}

const fontStack = (family) => family.map((name) => (/\s/.test(name) || name === 'Inter' ? `"${name}"` : name)).join(', ');

/** tokens.css for a parsed tokens.json. */
export function renderTokensCss(tokens) {
  const color = (group, title) => [
    `  /* ${title} */`,
    ...entries(tokens.color[group]).map(([name, t]) => `  --tiroir-${name}: ${t.$value}; /* ${t.$description} */`),
    '',
  ];
  const glow = tokens.gradient.glow;
  const stops = glow.$value.map((stop) => ({ color: resolveValue(tokens, stop.color), position: stop.position }));
  const spring = tokens.motion.spring.drawer;
  const drawer = springEasing(spring.$value);
  const role = (t) => {
    const alias = t.$value.match(/^\{color\.(dark|light)\.(.+)\}$/);
    if (alias) return `var(--tiroir-${alias[2]});`;
    if (/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(t.$value)) return `${t.$value.toUpperCase()};${t.$description ? ` /* ${t.$description} */` : ''}`;
    throw new Error(`role value ${t.$value}: neither a palette alias nor a hex color`);
  };
  const css = [
    '/* Tiroir brand tokens.',
    ' * Generated from brand/tokens/tokens.json by brand/scripts/tokens/build.mjs:',
    ' * edit the JSON and run the script, never this file.',
    ' */',
    '',
    ':root {',
    ...color('dark', 'Dark palette: the website and the dark appearance'),
    ...color('light', 'Light palette'),
    `  /* ${glow.$description} */`,
    ...stops.map((stop, i) => `  --tiroir-glow-${i + 1}: ${stop.color};`),
    `  --tiroir-glow: linear-gradient(135deg, ${stops.map((stop, i) => `var(--tiroir-glow-${i + 1}) ${Math.round(stop.position * 100)}%`).join(', ')});`,
    '',
    '  /* Type: SF Pro through the system names, never shipped; Inter as the only webfont.',
    '     --tiroir-<style> is a font shorthand (weight size/line family); set letter-spacing',
    '     with --tiroir-<style>-tracking. */',
    `  --tiroir-font-sans: ${fontStack(tokens.font.family.sans.$value)};`,
    ...entries(tokens.font.weight).map(([name, t]) => `  --tiroir-weight-${name}: ${t.$value};`),
  ];
  for (const [name, t] of entries(tokens.type)) {
    const v = t.$value;
    css.push(
      `  --tiroir-${name}-size: ${v.fontSize};`,
      `  --tiroir-${name}-line: ${v.lineHeight};`,
      `  --tiroir-${name}-weight: ${v.fontWeight};`,
      `  --tiroir-${name}-tracking: ${v.letterSpacing};`,
      `  --tiroir-${name}: ${v.fontWeight} ${v.fontSize}/${v.lineHeight} var(--tiroir-font-sans);`,
    );
  }
  css.push('', '  /* Radii */', ...entries(tokens.radius).map(([name, t]) => `  --tiroir-radius-${name}: ${t.$value}; /* ${t.$description} */`));
  css.push('', '  /* Spacing: 4-point scale, the key is the multiple of 4 */', ...entries(tokens.space).map(([name, t]) => `  --tiroir-space-${name}: ${t.$value};`));
  css.push(
    '',
    `  /* Motion. The drawer spring: response ${spring.$value.response}, damping ${spring.$value.dampingFraction}, settled in ${drawer.seconds}s. */`,
    `  --tiroir-spring-drawer: ${drawer.easing};`,
    `  --tiroir-spring-drawer-duration: ${drawer.seconds}s;`,
    ...entries(tokens.motion.ease).map(([name, t]) => `  --tiroir-ease-${name}: cubic-bezier(${t.$value.join(', ')}); /* ${t.$description} */`),
    ...entries(tokens.motion.duration).map(([name, t]) => `  --tiroir-duration-${name}: ${t.$value}; /* ${t.$description} */`),
    '',
    '  /* Roles, dark appearance (the default) */',
    ...entries(tokens.role.dark).map(([name, t]) => `  --tiroir-${name}: ${role(t)}`),
    '}',
    '',
    '/* Roles, light appearance: opt in with data-tiroir-theme="light" on any element. */',
    '[data-tiroir-theme="light"] {',
    ...entries(tokens.role.light).map(([name, t]) => `  --tiroir-${name}: ${role(t)}`),
    '}',
    '',
  );
  return css.join('\n');
}

export function readTokens() {
  return JSON.parse(readFileSync(`${TOKENS_DIR}tokens.json`, 'utf8'));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const css = renderTokensCss(readTokens());
  const target = `${TOKENS_DIR}tokens.css`;
  if (process.argv.includes('--check')) {
    let current = '';
    try { current = readFileSync(target, 'utf8'); } catch { /* missing counts as out of date */ }
    if (current !== css) {
      console.error('brand/tokens/tokens.css is out of date: run node brand/scripts/tokens/build.mjs');
      process.exit(1);
    }
    console.log('brand/tokens/tokens.css is up to date');
  } else {
    writeFileSync(target, css);
    console.log(`wrote ${target}`);
  }
}
