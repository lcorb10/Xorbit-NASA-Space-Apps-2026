// Para cada material de un .glb: cuántas mallas lo usan y la caja que ocupan (en el mundo).
// Sirve para reconocer piezas de un modelo sin textura (p. ej. tanque, propulsores, orbitador).
// Uso: node data/tools/glb_materials_bounds.js <archivo.glb>
const fs = require('fs');
const file = process.argv[2];
const b = fs.readFileSync(file);
const L = b.readUInt32LE(12);
const j = JSON.parse(b.slice(20, 20 + L).toString('utf8'));
const mul = (a, c) => { const r = new Array(16).fill(0); for (let i = 0; i < 4; i++) for (let k = 0; k < 4; k++) for (let m = 0; m < 4; m++) r[k * 4 + i] += a[m * 4 + i] * c[k * 4 + m]; return r; };
const trs = n => {
  if (n.matrix) return n.matrix;
  const [tx, ty, tz] = n.translation || [0, 0, 0], [x, y, z, w] = n.rotation || [0, 0, 0, 1], [sx, sy, sz] = n.scale || [1, 1, 1];
  return [(1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx, 2 * (x * z - y * w) * sx, 0, 2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy, 2 * (y * z + x * w) * sy, 0, 2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz, (1 - 2 * (x * x + y * y)) * sz, 0, tx, ty, tz, 1];
};
const ap = (m, p) => [0, 1, 2].map(i => m[i] * p[0] + m[4 + i] * p[1] + m[8 + i] * p[2] + m[12 + i]);
const per = {};
const visit = (idx, parent) => {
  const n = j.nodes[idx];
  const m = mul(parent, trs(n));
  if (n.mesh != null) for (const p of j.meshes[n.mesh].primitives) {
    const name = (j.materials[p.material] || {}).name || '?';
    const e = per[name] || (per[name] = { n: 0, mn: [1e9, 1e9, 1e9], mx: [-1e9, -1e9, -1e9], nodes: new Set() });
    e.n++; e.nodes.add(n.name);
    const a = j.accessors[p.attributes.POSITION];
    for (const cx of [a.min[0], a.max[0]]) for (const cy of [a.min[1], a.max[1]]) for (const cz of [a.min[2], a.max[2]]) {
      const w = ap(m, [cx, cy, cz]);
      for (let k = 0; k < 3; k++) { e.mn[k] = Math.min(e.mn[k], w[k]); e.mx[k] = Math.max(e.mx[k], w[k]); }
    }
  }
  for (const c of n.children || []) visit(c, m);
};
const id = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
for (const r of j.scenes[j.scene || 0].nodes) visit(r, id);
for (const [k, e] of Object.entries(per)) {
  const c = e.mn.map((v, i) => ((v + e.mx[i]) / 2).toFixed(1)), s = e.mx.map((v, i) => (v - e.mn[i]).toFixed(1));
  console.log(`${k.padEnd(22)} mallas=${String(e.n).padStart(3)} centro=(${c.join(',')}) tamaño=(${s.join(',')}) nodos=${[...e.nodes].slice(0, 3).join('|')}`);
}
