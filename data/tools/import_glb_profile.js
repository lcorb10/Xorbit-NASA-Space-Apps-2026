// Convierte modelos .glb descargados en piezas de perfil para el juego.
// Mide el radio del cuerpo a cada altura (perfil de revolución) y detecta aletas.
// Así una pieza de internet funciona igual que las nuestras y que las que dibuje el jugador.
//
// Uso: node data/tools/import_glb_profile.js <spec.json> <salida.json>
// spec.json: { "source": {...}, "parts": [ { "file": "...glb", "id": "...", "kind": "nose|tank|engine|...", "name": {...} } ] }
const fs = require('fs');
const path = require('path');

const BINS = 32;

function readGlb(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'glTF') throw new Error(file + ' no es glTF binario');
  const jsonLen = b.readUInt32LE(12);
  const json = JSON.parse(b.slice(20, 20 + jsonLen).toString('utf8'));
  const binStart = 20 + jsonLen + 8;
  const bin = b.slice(binStart, binStart + b.readUInt32LE(20 + jsonLen));
  return { json, bin };
}

function nodeMatrix(n) {
  // Solo traslación y escala (los modelos de Kenney no traen rotaciones en los nodos de piezas)
  const t = n.translation || [0, 0, 0];
  const s = n.scale || [1, 1, 1];
  if (n.rotation && Math.abs(n.rotation[3]) < 0.9999) throw new Error('rotación de nodo no soportada');
  if (n.matrix) throw new Error('matriz de nodo no soportada');
  return { t, s };
}

function triangles({ json, bin }) {
  const tris = [];
  const visit = (idx, parent) => {
    const n = json.nodes[idx];
    const m = nodeMatrix(n);
    const tr = parent.t.map((v, i) => v + m.t[i] * parent.s[i]);
    const s = parent.s.map((v, i) => v * m.s[i]);
    if (n.mesh != null) {
      for (const prim of json.meshes[n.mesh].primitives) {
        if (prim.mode != null && prim.mode !== 4) continue; // solo triángulos
        const acc = json.accessors[prim.attributes.POSITION];
        const bv = json.bufferViews[acc.bufferView];
        const stride = bv.byteStride || 12;
        const off = (bv.byteOffset || 0) + (acc.byteOffset || 0);
        const pos = i => [0, 1, 2].map(k => bin.readFloatLE(off + i * stride + k * 4) * s[k] + tr[k]);
        let idxs;
        if (prim.indices != null) {
          const ia = json.accessors[prim.indices];
          const ib = json.bufferViews[ia.bufferView];
          const io = (ib.byteOffset || 0) + (ia.byteOffset || 0);
          const size = { 5121: 1, 5123: 2, 5125: 4 }[ia.componentType];
          const rd = { 1: o => bin.readUInt8(o), 2: o => bin.readUInt16LE(o), 4: o => bin.readUInt32LE(o) }[size];
          idxs = Array.from({ length: ia.count }, (_, i) => rd(io + i * size));
        } else idxs = Array.from({ length: acc.count }, (_, i) => i);
        for (let i = 0; i + 2 < idxs.length; i += 3) tris.push([pos(idxs[i]), pos(idxs[i + 1]), pos(idxs[i + 2])]);
      }
    }
    for (const c of n.children || []) visit(c, { t: tr, s });
  };
  const scene = json.scenes[json.scene || 0];
  for (const r of scene.nodes) visit(r, { t: [0, 0, 0], s: [1, 1, 1] });
  return tris;
}

function profileOf(tris) {
  let pts = tris.flat();
  // Centrar el eje de giro en el centro de la caja (x, z): el origen de los modelos puede estar en una esquina
  const cx = (Math.min(...pts.map(p => p[0])) + Math.max(...pts.map(p => p[0]))) / 2;
  const cz = (Math.min(...pts.map(p => p[2])) + Math.max(...pts.map(p => p[2]))) / 2;
  tris = tris.map(tr => tr.map(([x, y, z]) => [x - cx, y, z - cz]));
  pts = tris.flat();
  const ys = pts.map(p => p[1]);
  const y0 = Math.min(...ys), y1 = Math.max(...ys);
  const h = y1 - y0;
  // Cortar la malla a cada altura; en cada corte, el radio más lejano por dirección (64 sectores).
  // Cuerpo = mediana de las direcciones (igual en todas); aletas = el máximo.
  const SECT = 64;
  const grid = [];
  for (let k = 0; k <= BINS; k++) {
    const f = Math.min(Math.max(k / BINS, 0.004), 0.996); // evitar cortar justo en las tapas
    const y = y1 - f * h;
    const row = new Array(SECT).fill(0);
    for (const tr of tris) {
      const cut = [];
      for (let e = 0; e < 3; e++) {
        const p = tr[e], q = tr[(e + 1) % 3];
        if ((p[1] - y) * (q[1] - y) < 0) {
          const u = (y - p[1]) / (q[1] - p[1]);
          cut.push([p[0] + u * (q[0] - p[0]), p[2] + u * (q[2] - p[2])]);
        }
      }
      if (cut.length !== 2) continue;
      for (let i = 0; i <= 24; i++) {
        const x = cut[0][0] + (cut[1][0] - cut[0][0]) * i / 24;
        const z = cut[0][1] + (cut[1][1] - cut[0][1]) * i / 24;
        const s = Math.floor(((Math.atan2(z, x) + Math.PI) / (2 * Math.PI)) * SECT) % SECT;
        row[s] = Math.max(row[s], Math.hypot(x, z));
      }
    }
    grid.push(row);
  }
  const body = [], outer = [];
  for (const row of grid) {
    const filled = row.filter(r => r > 0).sort((a, b) => a - b);
    if (filled.length < SECT / 2) { body.push(null); outer.push(null); continue; }
    body.push(filled[Math.floor(filled.length / 2)]);
    outer.push(filled[filled.length - 1]);
  }
  // Rellenar franjas vacías interpolando
  for (let i = 0; i <= BINS; i++) if (body[i] == null) {
    let a = i - 1; while (a >= 0 && body[a] == null) a--;
    let b = i + 1; while (b <= BINS && body[b] == null) b++;
    const va = a >= 0 ? body[a] : body[b], vb = b <= BINS ? body[b] : va;
    body[i] = (va + vb) / 2; outer[i] = body[i];
  }
  const rmax = Math.max(...body);
  // Aletas: franjas donde algo sobresale más de 12 % del radio del cuerpo
  const finBins = [];
  for (let i = 0; i <= BINS; i++) if (outer[i] > body[i] * 1.12 + 0.01) finBins.push(i);
  let fins = null;
  if (finBins.length >= 2) {
    const span = Math.max(...finBins.map(i => outer[i] - body[i]));
    const rootBins = finBins.length;
    const tipBins = finBins.filter(i => outer[i] - body[i] >= span * 0.85).length;
    fins = {
      span: +(span / (2 * rmax)).toFixed(3),         // en diámetros
      root: +((rootBins / BINS)).toFixed(3),          // en largos de la pieza
      tip: +(Math.max(tipBins, 1) / BINS).toFixed(3),
      bottom_offset: +((BINS - Math.max(...finBins)) / BINS).toFixed(3),
    };
  }
  // Perfil normalizado [r/rmax, y/h] de arriba hacia abajo, sin puntos colineales
  // Redondeado al 1 % para quitar el ruido de las caras planas (octágonos)
  let prof = body.map((r, i) => [+(Math.round((r / rmax) * 100) / 100).toFixed(2), +(i / BINS).toFixed(3)]);
  prof = simplify(prof, 0.01);
  return { aspect: +(h / (2 * rmax)).toFixed(3), profile: prof, fins, model_radius: +rmax.toFixed(4), model_height: +h.toFixed(4), model_center: [+cx.toFixed(4), +y0.toFixed(4), +cz.toFixed(4)] };
}

// Douglas-Peucker: quita puntos que se apartan menos de eps de la línea entre vecinos
function simplify(pts, eps) {
  if (pts.length < 3) return pts;
  const [a, b] = [pts[0], pts[pts.length - 1]];
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
  let far = 0, idx = 0;
  for (let i = 1; i < pts.length - 1; i++) {
    const d = Math.abs(dy * (pts[i][0] - a[0]) - dx * (pts[i][1] - a[1])) / len;
    if (d > far) { far = d; idx = i; }
  }
  if (far <= eps) return [a, b];
  return simplify(pts.slice(0, idx + 1), eps).slice(0, -1).concat(simplify(pts.slice(idx), eps));
}

const [, , specFile, outFile] = process.argv;
const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
const base = path.dirname(specFile);
const out = { _generated_by: 'data/tools/import_glb_profile.js', _source: spec.source, parts: [] };
for (const p of spec.parts) {
  const glb = readGlb(path.join(base, p.file));
  const r = profileOf(triangles(glb));
  out.parts.push({ ...p, aspect: r.aspect, profile: r.profile, fins: r.fins, model_radius: r.model_radius, model_height: r.model_height, model_center: r.model_center });
  console.log(p.id.padEnd(22), 'alto/diám', r.aspect, '| puntos', r.profile.length, '| aletas', r.fins ? JSON.stringify(r.fins) : 'no');
}
fs.writeFileSync(outFile, JSON.stringify(out, null, 1) + '\n');
