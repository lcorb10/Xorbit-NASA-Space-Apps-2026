# Modelos 3D de la NASA

- Fuente: repositorio oficial **nasa/NASA-3D-Resources** (https://github.com/nasa/NASA-3D-Resources), carpeta `3D Models`.
  Descargados el 13 nov 2026. Revisados: firmas glTF válidas, sin archivos externos, Windows Defender sin amenazas.
- Uso: la NASA ofrece estos modelos para uso libre. Los emblemas de la NASA (logo y "meatball") tienen reglas
  propias: no se pueden usar para dar a entender que la NASA respalda el proyecto. El juego lo aclara en Créditos
  ("No está respaldado por la NASA"). El VAB trae el logo y la bandera pintados porque así es el edificio real.

| Archivo | Modelo original | Escala en el juego (tamaño real) |
|---|---|---|
| saturn_v.glb | Saturn V | ×8,51 → 110,6 m de alto |
| jupiter_c.glb | Explorer Jupiter-C Rocket | ×1,21 → 21,2 m |
| space_shuttle.glb | Space Shuttle (A) | ×1,34 → 56 m (orbitador + tanque + propulsores) |
| crawler.glb | Crawler | ×4,55 → 40 m de largo |
| vab.glb | Vehicle Assembly Building (VAB) | ×11,7 → 160 m de alto |

No incluidos (por ahora): Space Launch System Block 1 (solo viene en .7z de 88 MB), Ares 1 (viene inclinado),
Atlas 6 y Redstone 3 (en realidad son solo las cápsulas Mercury), Mobile Launcher.
`vista_modelos_nasa.png`: las imágenes de vista previa que trae el repositorio.

## Conversión para Godot (13 nov 2026)
Crawler, Space Shuttle, Jupiter-C y VAB venían con compresión **Draco**, que Godot no puede leer. Se convirtieron con
Blender 5.2 sin ventana (`data/tools/glb_undraco.py`) a .glb normales. Para que el juego sea liviano, el Crawler
(279.800 triángulos) y el Shuttle (212.970) se redujeron a unos 80.000 triángulos cada uno con un modificador Decimate.

## Naves (carpeta `spacecraft/`, agregadas el 13 nov)
Del mismo repositorio de la NASA: Apollo Lunar Module, Apollo Soyuz, Lunar Reconnaissance Orbiter (A),
Geostationary Operational Environmental Satellites, Mars 2020 Perseverance Rover, Juno (A), Voyager Probe (A).
Seis venían con compresión Draco (Godot no la lee): se descomprimieron con Blender 5.2 sin otros cambios.
La nave de mando y servicio del Apolo (CSM) no está publicada sola: la arma `scripts/three_d/spacecraft.gd`
con sus medidas reales.
