// Time-driven animation helpers. Every scene exposes window.SCENE =
// { duration, render(t) } where render is a pure function of t (seconds),
// so the renderer can seek to any frame deterministically.

export const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
export const prog = (t, a, b) => clamp((t - a) / (b - a));
export const lerp = (a, b, p) => a + (b - a) * p;

export const ease = {
  linear: p => p,
  out: p => 1 - Math.pow(1 - p, 3),
  out5: p => 1 - Math.pow(1 - p, 5),
  in: p => p * p * p,
  inOut: p => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
  expoOut: p => (p >= 1 ? 1 : 1 - Math.pow(2, -10 * p)),
  expoInOut: p =>
    p <= 0 ? 0 : p >= 1 ? 1 : p < 0.5 ? Math.pow(2, 20 * p - 10) / 2 : (2 - Math.pow(2, -20 * p + 10)) / 2,
  back: p => {
    const c1 = 1.4, c3 = c1 + 1;
    return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2);
  },
};

/** Eased 0..1 progress of a tween starting at `a` lasting `d` seconds. */
export const tw = (t, a, d, e = ease.out) => e(prog(t, a, a + d));

/** Visibility envelope: fades in at `a`, out at `b` (b optional). */
export function env(t, a, b = 1e6, fin = 0.6, fout = 0.5) {
  return Math.min(ease.out(prog(t, a, a + fin)), 1 - ease.inOut(prog(t, b, b + fout)));
}

export const $ = s => document.querySelector(s);
export const $$ = s => [...document.querySelectorAll(s)];

export function css(el, o) {
  if (typeof el === 'string') el = $(el);
  if (!el) return;
  for (const k in o) el.style[k] = o[k];
}

/** Apple-style text reveal: fade + rise + slight blur clearing. */
export function reveal(el, t, a, b = 1e6, dist = 28) {
  if (typeof el === 'string') el = $(el);
  const pin = ease.out5(prog(t, a, a + 0.9));
  const pout = ease.inOut(prog(t, b, b + 0.5));
  const o = Math.min(pin, 1 - pout);
  el.style.opacity = o;
  el.style.transform = `translateY(${(1 - pin) * dist - pout * 14}px)`;
  el.style.filter = o < 0.999 ? `blur(${(1 - pin) * 8 + pout * 6}px)` : 'none';
}

export function fmt(n, dec = 0) {
  return n.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec });
}

/** Deterministic PRNG so every frame agrees on "random" layouts. */
export function rng(seed = 1) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let x = s;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

export function register(duration, render) {
  window.SCENE = { duration, render };
  const q = new URLSearchParams(location.search);
  if (q.has('t')) render(parseFloat(q.get('t')));
  else if (q.has('play')) {
    const t0 = performance.now();
    const loop = () => {
      render(((performance.now() - t0) / 1000) % (duration + 1));
      requestAnimationFrame(loop);
    };
    loop();
  }
}
