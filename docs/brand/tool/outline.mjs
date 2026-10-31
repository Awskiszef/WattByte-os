// Minimal TrueType outliner: text -> SVG path data (simple + composite glyphs, cmap fmt 4/12, hmtx, no kerning).
import { readFileSync } from 'node:fs';

export function loadFont(file) {
  const b = readFileSync(file);
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const n = dv.getUint16(4);
  const t = {};
  for (let i = 0; i < n; i++) {
    const o = 12 + i * 16;
    t[String.fromCharCode(...b.subarray(o, o + 4))] = { off: dv.getUint32(o + 8), len: dv.getUint32(o + 12) };
  }
  const head = t.head.off;
  const upem = dv.getUint16(head + 18);
  const locaFmt = dv.getInt16(head + 50);
  const numGlyphs = dv.getUint16(t.maxp.off + 4);
  const nHM = dv.getUint16(t.hhea.off + 34);
  const loca = (g) => (locaFmt ? dv.getUint32(t.loca.off + g * 4) : dv.getUint16(t.loca.off + g * 2) * 2);
  const adv = (g) => dv.getUint16(t.hmtx.off + Math.min(g, nHM - 1) * 4);

  function cmap(cp) {
    const base = t.cmap.off;
    const nt = dv.getUint16(base + 2);
    for (let i = 0; i < nt; i++) {
      const so = base + dv.getUint32(base + 4 + i * 8 + 4);
      const fmt = dv.getUint16(so);
      if (fmt === 4) {
        const segX2 = dv.getUint16(so + 6);
        const endO = so + 14, startO = endO + segX2 + 2, deltaO = startO + segX2, rangeO = deltaO + segX2;
        for (let s = 0; s < segX2 / 2; s++) {
          const end = dv.getUint16(endO + s * 2), start = dv.getUint16(startO + s * 2);
          if (cp >= start && cp <= end) {
            const ro = dv.getUint16(rangeO + s * 2), delta = dv.getInt16(deltaO + s * 2);
            if (ro === 0) return (cp + delta) & 0xffff;
            const g = dv.getUint16(rangeO + s * 2 + ro + (cp - start) * 2);
            return g ? (g + delta) & 0xffff : 0;
          }
        }
      } else if (fmt === 12) {
        const ng = dv.getUint32(so + 12);
        for (let k = 0; k < ng; k++) {
          const go = so + 16 + k * 12;
          const s = dv.getUint32(go), e = dv.getUint32(go + 4);
          if (cp >= s && cp <= e) return dv.getUint32(go + 8) + (cp - s);
        }
      }
    }
    return 0;
  }

  // returns contours: arrays of {x,y,on}
  function glyph(g, depth = 0) {
    const s = loca(g), e = loca(g + 1);
    if (s === e) return [];
    let p = t.glyf.off + s;
    const nc = dv.getInt16(p);
    p += 10;
    if (nc >= 0) {
      const ends = [];
      for (let i = 0; i < nc; i++, p += 2) ends.push(dv.getUint16(p));
      const np = nc ? ends[nc - 1] + 1 : 0;
      p += 2 + dv.getUint16(p);
      const flags = [];
      while (flags.length < np) {
        const f = dv.getUint8(p++);
        flags.push(f);
        if (f & 8) { let r = dv.getUint8(p++); while (r--) flags.push(f); }
      }
      const xs = [], ys = [];
      let v = 0;
      for (let i = 0; i < np; i++) {
        const f = flags[i];
        if (f & 2) { const d = dv.getUint8(p++); v += f & 16 ? d : -d; } else if (!(f & 16)) { v += dv.getInt16(p); p += 2; }
        xs.push(v);
      }
      v = 0;
      for (let i = 0; i < np; i++) {
        const f = flags[i];
        if (f & 4) { const d = dv.getUint8(p++); v += f & 32 ? d : -d; } else if (!(f & 32)) { v += dv.getInt16(p); p += 2; }
        ys.push(v);
      }
      const out = [];
      let st = 0;
      for (const en of ends) {
        const c = [];
        for (let i = st; i <= en; i++) c.push({ x: xs[i], y: ys[i], on: !!(flags[i] & 1) });
        out.push(c);
        st = en + 1;
      }
      return out;
    }
    if (depth > 4) return [];
    let out = [], more = true;
    while (more) {
      const fl = dv.getUint16(p), gi = dv.getUint16(p + 2);
      p += 4;
      let dx, dy;
      if (fl & 1) { dx = dv.getInt16(p); dy = dv.getInt16(p + 2); p += 4; } else { dx = dv.getInt8(p); dy = dv.getInt8(p + 1); p += 2; }
      let a = 1, bb = 0, c = 0, d = 1;
      const f2 = (o) => dv.getInt16(o) / 16384;
      if (fl & 8) { a = d = f2(p); p += 2; } else if (fl & 0x40) { a = f2(p); d = f2(p + 2); p += 4; } else if (fl & 0x80) { a = f2(p); bb = f2(p + 2); c = f2(p + 4); d = f2(p + 6); p += 8; }
      if (!(fl & 2)) throw new Error('point-matched composites unsupported');
      for (const ct of glyph(gi, depth + 1)) out.push(ct.map((q) => ({ x: a * q.x + c * q.y + dx, y: bb * q.x + d * q.y + dy, on: q.on })));
      more = !!(fl & 0x20);
    }
    return out;
  }

  return { upem, cmap, glyph, adv };
}

const r = (n) => +n.toFixed(2);

// contour -> SVG path d, scaled, y flipped, translated
export function contourPath(c, sx, ox, oy) {
  const X = (x) => r(ox + x * sx), Y = (y) => r(oy - y * sx);
  const pts = c.slice();
  if (!pts.length) return '';
  // start on an on-curve point
  let si = pts.findIndex((q) => q.on);
  let list;
  if (si === -1) {
    const m = { x: (pts[0].x + pts[1].x) / 2, y: (pts[0].y + pts[1].y) / 2, on: true };
    list = [m, ...pts.slice(1), pts[0]];
  } else list = [...pts.slice(si), ...pts.slice(0, si)];
  let d = `M${X(list[0].x)} ${Y(list[0].y)}`;
  list.push(list[0]); // last element is on-curve: closes any trailing off-curve run
  const n = list.length;
  let i = 1;
  const at = (k) => list[k];
  while (i < n) {
    const cur = at(i);
    if (cur.on) { d += `L${X(cur.x)} ${Y(cur.y)}`; i++; continue; }
    const nxt = at(i + 1);
    let end;
    if (nxt.on) { end = nxt; i += 2; } else { end = { x: (cur.x + nxt.x) / 2, y: (cur.y + nxt.y) / 2 }; i += 1; }
    d += `Q${X(cur.x)} ${Y(cur.y)} ${X(end.x)} ${Y(end.y)}`;
  }
  return d + 'Z';
}

// text -> { d, width } at font size `size`, baseline at (x, y); tracking in em
export function textPath(font, text, size, x, y, tracking = 0) {
  const s = size / font.upem;
  let cx = x, d = '';
  for (const ch of text) {
    const g = font.cmap(ch.codePointAt(0));
    for (const c of font.glyph(g)) d += contourPath(c, s, cx, y);
    cx += font.adv(g) * s + tracking * size;
  }
  return { d, width: cx - x - tracking * size };
}
