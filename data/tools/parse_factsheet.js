// Convierte la NASA Planetary Fact Sheet (HTML) en data/planets.json.
// Uso: node data/tools/parse_factsheet.js <factsheet.html> <salida.json>
const fs = require('fs');
const [, , src, out] = process.argv;
const html = fs.readFileSync(src, 'utf8');
const rows = [...html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)].map(m =>
  [...m[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(c =>
    c[1].replace(/<sup>(.*?)<\/sup>/gi, '^$1').replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim()));
const header = rows.find(r => r.includes('EARTH'));
const bodies = header.slice(1).map(s => s.toLowerCase());
const num = s => { const v = parseFloat(s.replace(/,/g, '').replace(/\*/g, '')); return Number.isFinite(v) ? v : null; };
const out_ = {};
bodies.forEach(b => out_[b] = {});
const keys = {
  'Mass (10^24kg)': 'mass_1e24_kg', 'Diameter (km)': 'diameter_km', 'Density (kg/m^3)': 'density_kg_m3',
  'Gravity (m/s^2)': 'gravity_m_s2', 'Escape Velocity (km/s)': 'escape_velocity_km_s',
  'Rotation Period (hours)': 'rotation_period_h', 'Length of Day (hours)': 'day_length_h',
  'Distance from Sun (10^6km)': 'distance_sun_1e6_km', 'Perihelion (10^6km)': 'perihelion_1e6_km',
  'Aphelion (10^6km)': 'aphelion_1e6_km', 'Orbital Period (days)': 'orbital_period_days',
  'Orbital Velocity (km/s)': 'orbital_velocity_km_s', 'Orbital Inclination (degrees)': 'orbital_inclination_deg',
  'Orbital Eccentricity': 'orbital_eccentricity', 'Obliquity to Orbit (degrees)': 'obliquity_deg',
  'Mean Temperature (C)': 'mean_temperature_c', 'Surface Pressure (bars)': 'surface_pressure_bar',
  'Number of Moons': 'moons', 'Ring System?': 'rings', 'Global Magnetic Field?': 'magnetic_field',
};
const seen = [];
for (const r of rows) {
  const label = r[0] && r[0].replace(/\s+/g, '');
  const k = Object.entries(keys).find(([l]) => l.replace(/\s+/g, '') === label);
  if (!k || r.length < bodies.length + 1) continue;
  seen.push(k[1]);
  bodies.forEach((b, i) => {
    const raw = r[i + 1];
    out_[b][k[1]] = ['rings', 'magnetic_field'].includes(k[1]) ? (raw === 'Yes' ? true : raw === 'No' ? false : null)
      : (raw === 'Unknown' ? null : num(raw));
  });
}
// Para la Luna, la tabla de NASA da distancias a la Tierra, no al Sol
if (out_.moon) {
  const m = out_.moon;
  for (const k of ['distance_sun_1e6_km', 'perihelion_1e6_km', 'aphelion_1e6_km']) {
    m[k.replace('distance_sun', 'distance_earth').replace(/^(perihelion|aphelion)/, k.startsWith('peri') ? 'perigee' : 'apogee')] = m[k];
    delete m[k];
  }
  m.distance_sun_1e6_km = out_.earth.distance_sun_1e6_km;
}
// Irradiancia solar derivada: 1361 W/m² a 1 UA (149.6e6 km), cae con 1/r²
for (const b of bodies) {
  const d = out_[b].distance_sun_1e6_km;
  if (d) out_[b].solar_irradiance_w_m2_derived = Math.round(1361 * (149.6 / d) ** 2 * 10) / 10;
}
const missing = Object.values(keys).filter(k => !seen.includes(k));
fs.writeFileSync(out, JSON.stringify({
  _source: 'NASA NSSDC Planetary Fact Sheet - Metric, https://nssdc.gsfc.nasa.gov/planetary/factsheet/',
  _retrieved: new Date().toISOString().slice(0, 10),
  _notes: 'Luna: la tabla de NASA da distancias a la Tierra (distance_earth, perigee, apogee); distance_sun se toma igual a la de la Tierra. solar_irradiance_w_m2_derived = 1361*(1 UA/d)^2, calculado, no viene de la tabla.',
  bodies: out_,
}, null, 2));
console.log('cuerpos:', bodies.join(', '), '| campos:', seen.length, '| faltan:', missing.join(', ') || 'ninguno');
