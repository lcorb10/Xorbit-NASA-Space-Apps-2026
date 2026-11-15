# Xorbit

Xorbit es nuestro proyecto para el **NASA Space Apps Challenge 2026**, en el reto
[Space Mission Design Game](https://www.spaceappschallenge.org/2026/challenges/space-mission-design-game/).
Lo hicimos Sebastián y María Cecilia desde Barranquilla, Colombia.

La idea es simple: tú diseñas el cohete y la nave, eliges los instrumentos, la energía y la antena,
y después lo lanzas para ver hasta dónde llega. Si falla, el juego te dice por qué. Si sale bien,
te dice qué tan bien. Todo lo que pasa en el vuelo sale de la física real (Δv, empuje contra peso,
estabilidad, presión dinámica, etapas), no de animaciones hechas a mano.

**English summary.** Xorbit is a rocket and mission design game made for the NASA Space Apps
Challenge 2026 (Space Mission Design Game challenge). You build a rocket on a budget, fit a
spacecraft with instruments, power and communications, and fly it. The flight is computed with real
physics, and the game explains why each design works or fails. The game is in English by default
and can be switched to Spanish.

## Descargar y jugar

1. Ve a [Releases](../../releases) y baja `Xorbit-Windows.zip`.
2. Descomprímelo y abre `Xorbit.exe`.

Funciona en Windows 10 y 11 de 64 bits. Se recomienda una tarjeta gráfica dedicada, porque el
Centro Espacial y el vuelo son en 3D. Se puede jugar con teclado y ratón o con mandos
(DualShock, Xbox, Joy-Con).

## Qué se hace en el juego

- **Taller.** Armas el cohete pieza por pieza: puntas, tanques, motores, aletas, separadores y la
  bahía de carga. Puedes diseñar tus propias piezas con un torno, o cargar cohetes reales
  (Mercury-Redstone, Electron, Falcon 9, Atlas V, Saturno V) para ver por qué funcionan.
- **Nave.** Le pones instrumentos, paneles solares, baterías o un RTG, y una antena. El juego
  revisa la energía, los datos por día contra lo que la estación de tierra puede bajar, y la vida
  útil según la radiación del destino.
- **Análisis.** Antes de lanzar ves el Δv de cada etapa, el empuje contra peso, el centro de masa
  contra el centro de presión, el costo y el presupuesto. Hay un botón para pedirle ayuda a Houston
  y otro que corre una prueba de viabilidad (muchos vuelos simulados con variaciones).
- **Vuelo.** El cohete sale del VAB en el crawler, va a la plataforma 39A, cuenta regresiva y
  despegue. Ves el ascenso, la separación de etapas, la llegada a la órbita y, en las misiones más
  lejanas, el viaje en el mapa con cada maniobra y su Δv.
- **Tripulación.** De 1 a 4 jugadores en la misma pantalla (pantalla partida o por turnos). Cada uno
  tiene un puesto y unos retos cortos durante el vuelo: cuenta regresiva, max-Q, separación,
  encendido hacia la Luna. En la Luna el comandante baja, camina con la gravedad lunar y planta
  la bandera.
- **Informe.** Al final ves qué pasó, las estrellas que ganaste y qué mejorar.

## Misiones

| # | Misión |
|---|---|
| 0 | Llegar al espacio (100 km) |
| 1 | Órbita baja |
| 2 | Órbita geoestacionaria |
| 3 | Órbita lunar |
| 4 | Aterrizaje lunar |
| 5 | Órbita de Marte |
| 6 | Rover en Marte |
| 7 | Júpiter |
| 8 | Salir del sistema solar |
| 9 | Las estrellas |

Cada misión da más presupuesto y desbloquea piezas nuevas. Las primeras tienen un tutorial guiado
con Houston por radio.

## Cómo responde al reto

El reto pide un juego donde se diseñe una misión completa con sus restricciones reales. Lo que
hicimos para eso:

- Presupuesto y costo por pieza, por material y por operación de la estación de tierra.
- Los recursos de la nave que pide la NASA en sus documentos del reto: masa, energía, datos,
  comunicaciones, vida útil y tiempo de construcción.
- Los cuatro segmentos de una misión: lanzamiento, espacio, tierra y usuarios.
- Los niveles de madurez del concepto (CML) que usa la NASA al diseñar misiones.
- Datos reales: planetas de la NASA Planetary Fact Sheet, motores reales, sonidos y modelos 3D de
  la NASA.

## Qué hay en este repositorio

Está el proyecto completo de Godot para que se pueda ver cómo está hecho:

| Carpeta | Qué hay |
|---|---|
| `scripts/core/` | La física y la lógica sin gráficos: análisis del cohete, simulación del vuelo, costos, la nave |
| `scripts/three_d/` | Todo lo 3D: hangar, Centro Espacial, vuelo, viaje, aterrizaje, tripulación |
| `scripts/ui/` | Las pantallas: menú, misiones, taller, tutorial, informe |
| `data/` | Todo el contenido en JSON: piezas, motores, materiales, misiones, textos en inglés y español |
| `assets/` | Modelos, texturas, música, sonidos y voces. Cada carpeta tiene un `FUENTE.md` con el origen y la licencia |
| `scenes/` | Escenas de Godot |

Para abrirlo hace falta [Godot 4.7.2](https://godotengine.org/). Se abre `project.godot` y se
corre con F5. Para exportar el `.exe` está el preset `Windows` en `export_presets.cfg`.

## Créditos

- **Equipo:** Sebastián y María Cecilia.
- **Motor:** Godot Engine 4.7 (MIT).
- **NASA:** modelos 3D de NASA 3D Resources (Saturno V, transbordador, Jupiter-C, crawler, VAB,
  módulo lunar, Perseverance, Juno, Voyager y la sala de control de Houston), sonidos del archivo de
  la NASA (despegue y cuenta regresiva del Apolo 11), Blue Marble y City Lights de NASA Earth
  Observatory, Planetary Fact Sheet, fichas del MMRTG y del motor iónico NSTAR, y el informe del
  motor de descenso del Apolo.
- **Modelos y texturas libres:** Kenney (CC0), Quaternius (CC0), Poly Haven (CC0), ambientCG (CC0),
  MakeHuman (CC0), Solar System Scope (CC BY 4.0).
- **Música:** OpenGameArt (CC0), de yd, Centurion_of_war, Yoiyami, vitalezzz, Ville Nousiainen y
  XCVG, cynicmusic y allen yatsura.
- **Tierra en alta resolución:** Wikimedia Commons ("Whole world - land and oceans").
- **Voz de Houston:** generada con VoiceStudio (OmniVoice).
- **Datos de motores:** oddurs/tsi (MIT). Ideas de mecánica: Kerbal Space Program y The Open
  Space Program.
- **Fuentes:** Barlow Condensed e IBM Plex Mono (SIL Open Font License).

El detalle de cada recurso está en el `FUENTE.md` de su carpeta.
