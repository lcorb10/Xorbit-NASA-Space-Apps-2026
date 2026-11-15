// Caja que ocupa un .glb en coordenadas del mundo (aplica traslación, rotación y escala de los nodos).
// Uso: node data/tools/glb_bounds.js <archivo.glb> [...]
const fs = require('fs');

function readGlb(file) {
  const b = fs.readFileSync(file);
  const jsonLen = b.readUInt32LE(12);
  const json = JSON.parse(b.slice(20, 20 + jsonLen).toString('utf8'));
  return json;
}

function mul(a, b) {
  const r = new Array(16).fill(0);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) for (let k = 0; k < 4; k++) r[j * 4 + i] += a[k * 4 + i] * b[j * 4 + k];
  return r;
}

function trs(n) {
  if (n.matrix) return n.matrix;
  const [tx, ty, tz] = n.translation || [0, 0, 0];
  const [x, y, z, w] = n.rotation || [0, 0, 0, 1];
  const [sx, sy, sz] = n.scale || [1, 1, 1];
  return [
    (1 - 2 * (y * y + z * z)) * sx, (2 * (x * y + z * w)) * sx, (2 * (x * z - y * w)) * sx, 0,
    (2 * (x * y - z * w)) * sy, (1 - 2 * (x * x + z * z)) * sy, (2 * (y * z + x * w)) * sy, 0,
    (2 * (x * z + y * w)) * sz, (2 * (y * z - x * w)) * sz, (1 - 2 * (x * x + y * y)) * sz, 0,
    tx, ty, tz, 1];
}

function apply(m, p) {
  return [0, 1, 2].map(i => m[i] * p[0] + m[4 + i] * p[1] + m[8 + i] * p[2] + m[12 + i]);
}

for (const file of process.argv.slice(2)) {
  const j = readGlb(file);
  const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
  let tris = 0, textures = (j.images || []).length, external = (j.images || []).filter(i => i.uri).length;
  const visit = (idx, parent) => {
    const n = j.nodes[idx];
    const m = mul(parent, trs(n));
    if (n.mesh != null) {
      for (const p of j.meshes[n.mesh].primitives) {
        const a = j.accessors[p.attributes.POSITION];
        if (p.indices != null) tris += j.accessors[p.indices].count / 3;
        for (const cx of [a.min[0], a.max[0]]) for (const cy of [a.min[1], a.max[1]]) for (const cz of [a.min[2], a.max[2]]) {
          const w = apply(m, [cx, cy, cz]);
          for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], w[k]); mx[k] = Math.max(mx[k], w[k]); }
        }
      }
    }
    for (const c of n.children || []) visit(c, m);
  };
  const id = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  for (const r of j.scenes[j.scene || 0].nodes) visit(r, id);
  const size = mx.map((v, i) => +(v - mn[i]).toFixed(2));
  console.log(`${file.split(/[\\/]/).pop().padEnd(38)} tamaño x,y,z=${size.join(' × ')}  min=${mn.map(v => v.toFixed(1)).join(',')}  tris=${Math.round(tris)}  texturas=${textures} externas=${external}`);
}
