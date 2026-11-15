# Audio del juego

Descargado el 13 nov 2026. Todos los archivos se revisaron con ffprobe (audio válido) y se convirtieron a OGG Vorbis.

## Sonidos de la NASA (dominio público)
Colección «NASA Audio Highlight Reels, Soundbites and Launch Sounds» en Internet Archive
(https://archive.org/details/NasaAudioHighlightReels), marcada Public Domain Mark 1.0.

| Archivo | Origen | Recorte |
|---|---|---|
| nasa/engine_loop.ogg | Launch-Sound_Saturn-V.mp3 | 22–82 s, fundido cruzado para bucle |
| nasa/liftoff_roar.ogg | Launch-Sound_Shuttle-Launch-Close.mp3 | 14–64 s, fundido de salida |
| nasa/control_room.ogg | Launch-Sound_Blockhouse-Background-Noise.mp3 | bucle, +24 dB |
| nasa/far_rumble.ogg | Launch-Sound_Far-Rumble.mp3 | completo |
| nasa/apollo11_liftoff.ogg | Apollo11Highlights.mp3 | 117,6–139,6 s: «Sequence starts… six, five… zero. All engines running. Liftoff, we have a liftoff…» |

## Música (CC0, OpenGameArt)
| Archivo | Pista | Autor | Página |
|---|---|---|---|
| music/menu.ogg | Space Music: Out There | yd | https://opengameart.org/content/space-music-out-there |
| music/workshop.ogg | First Light Particles | Yoiyami | https://opengameart.org/content/first-light-particles-%E2%80%93-cc0-atmospheric-pianoambient-track |
| music/space.ogg | Space Echo | Centurion_of_war | https://opengameart.org/content/space-echo |
| music/launch.ogg | Eclipse Legion | vitalezzz | https://opengameart.org/content/eclipse-legion |
| music/challenge.ogg | Fast fight / battle music (looped) | XCVG (sobre música de Ville Nousiainen) | https://opengameart.org/content/fast-fight-battle-music-looped |
| music/victory.ogg | Victory Theme for RPG | cynicmusic | https://opengameart.org/content/victory-theme-for-rpg |
| music/moon.ogg | Starfield Romance | Yoiyami | https://opengameart.org/content/starfield-romance-%E2%80%93-cc0-ambient-emotional-space-theme-yoiyami-blue-series-%E2%80%93-no3 |
| music/landing.ogg | tension and distress | allen yatsura | https://opengameart.org/content/tension-and-distress |

## Voz de Houston
assets/voice/en/*.ogg: generada con VoiceStudio (motor OmniVoice) a partir de los textos de
data/comms.json y data/tutorial.json con tools/voz_houston.py, con filtro de radio (ffmpeg).
