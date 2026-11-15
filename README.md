# Xorbit

Xorbit is our project for the **NASA Space Apps Challenge 2026**, in the
[Space Mission Design Game](https://www.spaceappschallenge.org/2026/challenges/space-mission-design-game/)
challenge. It was made by Sebastián and María Cecilia in Barranquilla, Colombia.

The idea is simple: you design the rocket and the spacecraft, choose the instruments, the power
source and the antenna, and then you launch it to see how far it gets. If it fails, the game tells
you why. If it works, it tells you how well. Everything that happens in the flight comes from real
physics (delta-v, thrust-to-weight, stability, dynamic pressure, staging), not from hand-made
animations.

The game is in English by default and can be switched to Spanish from the main menu.

**Website:** https://lcorb10.github.io/Xorbit-NASA-Space-Apps-2026/ (trailer, screenshots and download).

## Download and play

1. Go to [Releases](../../releases) and download `Xorbit-Windows.zip`.
2. Unzip it and open `Xorbit.exe`.

It runs on 64-bit Windows 10 and 11. A dedicated graphics card is recommended, since the Space
Center and the flight are in 3D. You can play with keyboard and mouse or with gamepads
(DualShock, Xbox, Joy-Con).

## What you do in the game

- **Workshop.** You build the rocket part by part: noses, tanks, engines, fins, decouplers and the
  payload bay. You can design your own parts on a lathe, or load real rockets (Mercury-Redstone,
  Electron, Falcon 9, Atlas V, Saturn V) to see why they work.
- **Spacecraft.** You add instruments, solar panels, batteries or an RTG, and an antenna. The game
  checks power, data per day against what the ground station can download, and lifetime under the
  radiation of the destination.
- **Analysis.** Before launch you see the delta-v of each stage, thrust-to-weight, center of mass
  against center of pressure, cost and budget. There is a button to ask Houston for help and
  another one that runs a feasibility check (many simulated flights with variations).
- **Flight.** The rocket leaves the VAB on the crawler, rolls out to pad 39A, counts down and lifts
  off. You watch the ascent, stage separation, orbit insertion and, in the farther missions, the
  trip on the map with each manoeuvre and its delta-v.
- **Crew.** From 1 to 4 players on the same screen (split screen or taking turns). Each player has
  a station and short challenges during the flight: countdown, max-Q, staging, the burn towards
  the Moon. On the Moon the commander steps out, walks in lunar gravity and plants the flag.
- **Report.** At the end you see what happened, the stars you earned and what to improve.

## Missions

| # | Mission |
|---|---|
| 0 | Reach space (100 km) |
| 1 | Low Earth orbit |
| 2 | Geostationary orbit |
| 3 | Lunar orbit |
| 4 | Moon landing |
| 5 | Mars orbit |
| 6 | Mars rover |
| 7 | Jupiter |
| 8 | Leave the Solar System |
| 9 | The stars |

Each mission adds budget and unlocks new parts. The first ones have a guided tutorial with Houston
on the radio.

## How it answers the challenge

The challenge asks for a game where players design a complete mission with real constraints. This
is what we built for that:

- Budget and cost per part, per material and per year of ground station operations.
- The spacecraft resources NASA lists in the challenge documents: mass, power, data,
  communications, lifetime and build time.
- The four segments of a mission: launch, space, ground and users.
- The Concept Maturity Levels (CML) NASA uses when designing missions.
- Real data: planets from the NASA Planetary Fact Sheet, real engines, NASA sounds and 3D models.

## What is in this repository

This is the full Godot project, so you can see how it is made:

| Folder | Contents |
|---|---|
| `scripts/core/` | Physics and logic without graphics: rocket analysis, flight simulation, costs, the spacecraft |
| `scripts/three_d/` | Everything in 3D: hangar, Space Center, flight, transfer, landing, crew |
| `scripts/ui/` | The screens: menu, missions, workshop, tutorial, report |
| `data/` | All the content in JSON: parts, engines, materials, missions, texts in English and Spanish |
| `assets/` | Models, textures, music, sounds and voices. Each folder has a `FUENTE.md` with the source and license |
| `scenes/` | Godot scenes |

To open it you need [Godot 4.7.2](https://godotengine.org/). Open `project.godot` and run it with
F5. The `Windows` preset in `export_presets.cfg` exports the `.exe`.

## Credits

- **Team:** Sebastián and María Cecilia.
- **Engine:** Godot Engine 4.7 (MIT).
- **NASA:** 3D models from NASA 3D Resources (Saturn V, Space Shuttle, Jupiter-C, crawler, VAB,
  lunar module, Perseverance, Juno, Voyager and the Houston control room), sounds from the NASA
  archive (launch and the Apollo 11 countdown), Blue Marble and City Lights from NASA Earth
  Observatory, Planetary Fact Sheet, MMRTG and NSTAR ion thruster fact sheets, and the Apollo
  descent engine report.
- **Free models and textures:** Kenney (CC0), Quaternius (CC0), Poly Haven (CC0), ambientCG (CC0),
  MakeHuman (CC0), Solar System Scope (CC BY 4.0).
- **High resolution Earth:** Wikimedia Commons ("Whole world - land and oceans").
- **Houston voice:** generated with VoiceStudio (OmniVoice).
- **Music:** OpenGameArt (CC0), by yd, Centurion_of_war, Yoiyami, vitalezzz, Ville Nousiainen and
  XCVG, cynicmusic and allen yatsura.
- **Engine data:** oddurs/tsi (MIT). Gameplay inspiration: Kerbal Space Program and The Open Space
  Program.
- **Fonts:** Barlow Condensed and IBM Plex Mono (SIL Open Font License).

The details of each asset are in the `FUENTE.md` file of its folder.
