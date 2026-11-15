extends Node
## Música y ambiente. Cada pantalla tiene su pista y pasa de una a otra con un fundido:
## menú, misiones y ajustes → "Out There"; taller → piano ambiental y, de fondo, el
## murmullo de la sala de control de la NASA; vuelo → silencio con el rugido de los
## motores y, ya en el espacio, una pista espacial (la pide la vista de vuelo).
## Música CC0 de OpenGameArt; sonidos de la NASA (dominio público). Ver assets/audio/FUENTE.md.

const TRACKS := {
	"menu": "res://assets/audio/music/menu.ogg",
	"workshop": "res://assets/audio/music/workshop.ogg",
	"space": "res://assets/audio/music/space.ogg",
	"launch": "res://assets/audio/music/launch.ogg", # Eclipse Legion (épica, despegue)
	"challenge": "res://assets/audio/music/challenge.ogg", # Fast fight (retos de la tripulación)
	"victory": "res://assets/audio/music/victory.ogg", # Victory Theme (misión cumplida)
	"moon": "res://assets/audio/music/moon.ogg", # Starfield Romance (caminata lunar)
	"landing": "res://assets/audio/music/landing.ogg", # Tension and distress (descenso)
}
const AMBIENCE := {
	"control": "res://assets/audio/nasa/control_room.ogg",
}
const BY_SCENE := {
	"main_menu": ["menu", ""], "level_select": ["menu", ""], "settings": ["menu", ""],
	"workshop": ["workshop", "control"], "flight": ["", ""],
}
const FADE := 1.5
const MUSIC_DB := -9.0
const AMB_DB := -14.0

var flight_music := "" # la vista de vuelo elige ("" o "space")
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _cur := "-"
var _amb: AudioStreamPlayer
var _amb_cur := "-"
var _check := 0.0
var _scene_path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Music"
	_amb.volume_db = -80.0
	add_child(_amb)
	apply_volume()


## Volumen de la música (ajustes): 0..1, aparte del volumen general.
func apply_volume() -> void:
	var v := float(Game.settings.get("music", 0.6))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(v, 0.0001)))


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.4
	var scene := get_tree().current_scene
	var path := scene.scene_file_path.get_file().get_basename() if scene else ""
	if path != _scene_path:
		_scene_path = path
		if path != "flight":
			flight_music = ""
	var pick: Array = BY_SCENE.get(path, ["", ""])
	var music: String = flight_music if path == "flight" else str(pick[0])
	_play(music)
	_ambience(str(pick[1]))


func _play(id: String) -> void:
	if id == _cur:
		return
	_cur = id
	var old := _players[_active]
	var tw := create_tween()
	tw.tween_property(old, "volume_db", -80.0, FADE)
	tw.tween_callback(old.stop)
	if id == "" or not TRACKS.has(id):
		return
	_active = 1 - _active
	var p := _players[_active]
	var s := load(TRACKS[id]) as AudioStreamOggVorbis
	s.loop = true
	p.stream = s
	p.volume_db = -40.0
	p.play()
	create_tween().tween_property(p, "volume_db", MUSIC_DB, FADE)


func _ambience(id: String) -> void:
	if id == _amb_cur:
		return
	_amb_cur = id
	if id == "" or not AMBIENCE.has(id):
		create_tween().tween_property(_amb, "volume_db", -80.0, FADE).finished.connect(func() -> void:
			if _amb_cur == "":
				_amb.stop())
		return
	var s := load(AMBIENCE[id]) as AudioStreamOggVorbis
	s.loop = true
	_amb.stream = s
	_amb.volume_db = -40.0
	_amb.play()
	create_tween().tween_property(_amb, "volume_db", AMB_DB, FADE)


## Baja la música mientras suena un video del manual.
func duck(on: bool) -> void:
	var i := AudioServer.get_bus_index("Music")
	if i >= 0:
		AudioServer.set_bus_mute(i, on)
