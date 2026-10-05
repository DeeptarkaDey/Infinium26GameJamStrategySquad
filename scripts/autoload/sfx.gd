extends Node
## Sound effects, synthesised in code (no audio files): each sound is a short
## recipe of tones, pitch sweeps and filtered noise, rendered to an
## AudioStreamWAV the first time it plays and cached. Autoloaded as `Sfx`.
##
##   Sfx.play("coin")                    # UI / player sounds, full volume
##   Sfx.play_at("hit", enemy.global_position)  # quieter the further from the player
##
## Volume lives on the "SFX" bus and is saved in user://settings.cfg.

const RATE := 22050
const VOICES := 16
const SETTINGS_PATH := "user://settings.cfg"
## The same sound can't restart more often than this (ms): ten simultaneous hits
## sound like one good hit instead of a roar.
const REPEAT_GAP_MS := 45
## Sounds further than this from the player are silent (px).
const HEAR_RANGE := 1100.0

var volume := 0.8:
	set(v):
		volume = clampf(v, 0.0, 1.0)
		var bus := AudioServer.get_bus_index("SFX")
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(bus, volume <= 0.001)

var _cache: Dictionary = {}  ## name -> AudioStreamWAV
var _ready_all := false
var _task := -1
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}  ## name -> msec
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus and pauses still click
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "SFX")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	var cfg := ConfigFile.new()
	volume = float(cfg.get_value("audio", "sfx_volume", 0.8)) if cfg.load(SETTINGS_PATH) == OK else 0.8
	# Rendering everything takes about a second, so it happens on a worker thread
	# at startup; a sound needed before then is rendered on the spot.
	_task = WorkerThreadPool.add_task(_render_all, false, "Sfx synth")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "sfx_volume", volume)
	cfg.save(SETTINGS_PATH)


func play(sound: String, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if volume <= 0.001 or not RECIPES.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -1000)) < REPEAT_GAP_MS:
		return
	_last_played[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _stream(sound)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## A sound from somewhere in the world: fades with distance from the player.
func play_at(sound: String, pos: Vector2, volume_db: float = 0.0) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var d := player.global_position.distance_to(pos) if player else 0.0
	if d >= HEAR_RANGE:
		return
	play(sound, volume_db + linear_to_db(lerpf(1.0, 0.15, d / HEAR_RANGE)))


func _stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _render(RECIPES[sound].call())
	return _cache[sound]


## True once every sound is rendered (tests wait on this for determinism).
func is_ready() -> bool:
	return _ready_all


func _render_all() -> void:
	var built := {}
	for sound: String in RECIPES:
		built[sound] = _render(RECIPES[sound].call())
	_finish_render.call_deferred(built)


func _finish_render(built: Dictionary) -> void:
	for sound: String in built:
		if not _cache.has(sound):
			_cache[sound] = built[sound]
	_ready_all = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _render(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# --- Synth building blocks ----------------------------------------------------------

## A tone sweeping from f0 to f1 Hz. wave: "sine", "square", "saw", "tri".
## Envelope: `attack` s linear rise, then exponential decay shaped by `curve`.
static func tone(f0: float, f1: float, dur: float, wave: String = "sine", vol: float = 0.5,
		attack: float = 0.004, curve: float = 3.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		var f := f0 * pow(f1 / f0, k)
		phase = fmod(phase + f / RATE, 1.0)
		var s := 0.0
		match wave:
			"square": s = 1.0 if phase < 0.5 else -1.0
			"saw": s = phase * 2.0 - 1.0
			"tri": s = 4.0 * absf(phase - 0.5) - 1.0
			_: s = sin(phase * TAU)
		out[i] = s * vol * _env(float(i) / RATE, dur, attack, curve)
	return out


## White noise through a one-pole low-pass whose cutoff sweeps c0 -> c1 Hz.
static func noise(dur: float, vol: float = 0.5, c0: float = 4000.0, c1: float = 800.0,
		attack: float = 0.002, curve: float = 3.0, seed_value: int = 1) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var y := 0.0
	for i in n:
		var k := float(i) / n
		var cutoff := c0 * pow(c1 / c0, k)
		var a := clampf(1.0 - exp(-TAU * cutoff / RATE), 0.0, 1.0)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * vol * 2.2 * _env(float(i) / RATE, dur, attack, curve)
	return out


static func _env(t: float, dur: float, attack: float, curve: float) -> float:
	if t < attack:
		return t / attack
	return exp(-curve * (t - attack) / maxf(dur - attack, 0.001))


## Sums `layers` ([samples, start_seconds] pairs) into one buffer.
static func mix(layers: Array) -> PackedFloat32Array:
	var length := 0
	for l: Array in layers:
		length = maxi(length, int(float(l[1]) * RATE) + (l[0] as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(length)
	for l: Array in layers:
		var buf: PackedFloat32Array = l[0]
		var off := int(float(l[1]) * RATE)
		for i in buf.size():
			out[off + i] += buf[i]
	# Layers can stack past full scale; bring the peak back under it instead of clipping.
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	if peak > 0.95:
		for i in out.size():
			out[i] *= 0.95 / peak
	return out


## Notes played one after another (a little fanfare or chime).
static func arp(freqs: Array, step: float, wave: String = "tri", vol: float = 0.35, ring: float = 0.25) -> PackedFloat32Array:
	var layers: Array = []
	for i in freqs.size():
		layers.append([tone(freqs[i], freqs[i], step + ring, wave, vol, 0.003, 4.0), i * step])
	return mix(layers)


# --- The sound library -------------------------------------------------------------
## Every sound the game can play. Names are what callers pass to play().

static var RECIPES := {
	# Combat: the samurai.
	"swing": func() -> PackedFloat32Array: return noise(0.16, 0.45, 5500.0, 900.0, 0.02, 2.5, 3),
	"swing_light": func() -> PackedFloat32Array: return noise(0.1, 0.35, 7000.0, 2000.0, 0.01, 2.5, 4),
	"swing_heavy": func() -> PackedFloat32Array: return mix([[noise(0.28, 0.55, 3000.0, 400.0, 0.04, 2.0, 5), 0.0], [tone(140.0, 70.0, 0.25, "sine", 0.3), 0.0]]),
	"thrust": func() -> PackedFloat32Array: return mix([[noise(0.12, 0.4, 6000.0, 1500.0, 0.005, 3.0, 6), 0.0], [tone(900.0, 500.0, 0.08, "saw", 0.12), 0.0]]),
	"bow": func() -> PackedFloat32Array: return mix([[tone(220.0, 180.0, 0.22, "tri", 0.4, 0.002, 5.0), 0.0], [noise(0.08, 0.3, 6000.0, 3000.0, 0.002, 4.0, 7), 0.0]]),
	"staff": func() -> PackedFloat32Array: return mix([[tone(600.0, 1400.0, 0.18, "square", 0.12), 0.0], [tone(900.0, 2000.0, 0.18, "sine", 0.25), 0.0]]),
	"dash": func() -> PackedFloat32Array: return noise(0.2, 0.4, 1500.0, 6000.0, 0.05, 3.0, 8),
	"hit": func() -> PackedFloat32Array: return mix([[tone(180.0, 60.0, 0.12, "sine", 0.6), 0.0], [noise(0.07, 0.45, 3000.0, 600.0, 0.001, 4.0, 9), 0.0]]),
	"crit": func() -> PackedFloat32Array: return mix([[tone(240.0, 70.0, 0.16, "sine", 0.6), 0.0], [noise(0.1, 0.5, 6000.0, 1200.0, 0.001, 4.0, 10), 0.0], [tone(1400.0, 900.0, 0.12, "tri", 0.2), 0.02]]),
	"hurt": func() -> PackedFloat32Array: return mix([[tone(160.0, 80.0, 0.22, "square", 0.25), 0.0], [noise(0.15, 0.35, 1800.0, 300.0, 0.001, 3.0, 11), 0.0]]),
	"player_die": func() -> PackedFloat32Array: return mix([[tone(330.0, 55.0, 0.9, "tri", 0.4, 0.01, 2.0), 0.0], [noise(0.6, 0.2, 1000.0, 100.0, 0.01, 2.0, 12), 0.0]]),
	"enemy_die": func() -> PackedFloat32Array: return mix([[tone(500.0, 90.0, 0.25, "square", 0.18), 0.0], [noise(0.22, 0.4, 2500.0, 200.0, 0.001, 3.0, 13), 0.0]]),
	# Skills, powers and elements.
	"dart": func() -> PackedFloat32Array: return tone(1200.0, 1800.0, 0.12, "sine", 0.3, 0.002, 4.0),
	"whirl": func() -> PackedFloat32Array: return noise(0.35, 0.45, 1200.0, 5000.0, 0.08, 1.5, 14),
	"thunder": func() -> PackedFloat32Array: return mix([[noise(0.06, 0.7, 9000.0, 4000.0, 0.001, 2.0, 15), 0.0], [noise(0.55, 0.5, 900.0, 120.0, 0.01, 2.5, 16), 0.04]]),
	"flare": func() -> PackedFloat32Array: return mix([[noise(0.4, 0.4, 800.0, 4000.0, 0.02, 2.0, 17), 0.0], [tone(300.0, 900.0, 0.35, "sine", 0.25), 0.0]]),
	"sacred": func() -> PackedFloat32Array: return mix([[tone(523.0, 523.0, 0.9, "sine", 0.22, 0.05, 2.0), 0.0], [tone(659.0, 659.0, 0.9, "sine", 0.2, 0.05, 2.0), 0.03], [tone(784.0, 784.0, 0.9, "sine", 0.2, 0.05, 2.0), 0.06], [tone(1046.0, 1046.0, 0.8, "sine", 0.12, 0.05, 2.0), 0.09]]),
	"burn": func() -> PackedFloat32Array: return noise(0.25, 0.35, 3000.0, 1200.0, 0.01, 3.0, 18),
	"freeze": func() -> PackedFloat32Array: return arp([2093.0, 2637.0, 3136.0], 0.04, "sine", 0.18, 0.15),
	"zap": func() -> PackedFloat32Array: return mix([[tone(1800.0, 300.0, 0.12, "saw", 0.18), 0.0], [noise(0.1, 0.3, 8000.0, 3000.0, 0.001, 3.0, 19), 0.0]]),
	"poison": func() -> PackedFloat32Array: return arp([300.0, 380.0, 260.0], 0.05, "sine", 0.25, 0.08),
	# Pickups and loot.
	"coin": func() -> PackedFloat32Array: return arp([1318.0, 1975.0], 0.06, "square", 0.12, 0.12),
	"pickup": func() -> PackedFloat32Array: return arp([660.0, 880.0, 1320.0], 0.05, "tri", 0.3, 0.2),
	"potion_pickup": func() -> PackedFloat32Array: return tone(400.0, 900.0, 0.15, "sine", 0.35, 0.005, 3.0),
	"drink": func() -> PackedFloat32Array: return mix([[tone(300.0, 500.0, 0.08, "sine", 0.35), 0.0], [tone(320.0, 560.0, 0.08, "sine", 0.35), 0.11], [arp([784.0, 988.0, 1318.0], 0.06, "tri", 0.2), 0.24]]),
	"chest": func() -> PackedFloat32Array: return mix([[tone(110.0, 160.0, 0.3, "saw", 0.15, 0.02, 2.0), 0.0], [arp([784.0, 988.0, 1175.0, 1568.0], 0.07, "tri", 0.3), 0.18]]),
	"pot": func() -> PackedFloat32Array: return mix([[noise(0.2, 0.55, 5000.0, 900.0, 0.001, 4.0, 20), 0.0], [tone(900.0, 600.0, 0.06, "tri", 0.15), 0.0]]),
	"key": func() -> PackedFloat32Array: return arp([1046.0, 1318.0, 1568.0, 2093.0], 0.07, "sine", 0.3, 0.3),
	"quest": func() -> PackedFloat32Array: return arp([587.0, 784.0, 988.0], 0.09, "tri", 0.3, 0.3),
	"quest_done": func() -> PackedFloat32Array: return arp([523.0, 659.0, 784.0, 1046.0, 784.0, 1046.0], 0.08, "square", 0.12, 0.35),
	"equip": func() -> PackedFloat32Array: return mix([[noise(0.08, 0.3, 7000.0, 3000.0, 0.001, 4.0, 21), 0.0], [tone(1500.0, 1500.0, 0.2, "tri", 0.15, 0.002, 5.0), 0.02]]),
	"buy": func() -> PackedFloat32Array: return arp([988.0, 1318.0, 1760.0], 0.05, "square", 0.12, 0.2),
	# Rooms and the world.
	"seal": func() -> PackedFloat32Array: return mix([[tone(90.0, 60.0, 0.4, "square", 0.25, 0.002, 3.0), 0.0], [noise(0.25, 0.5, 2000.0, 300.0, 0.001, 3.0, 22), 0.0]]),
	"clear": func() -> PackedFloat32Array: return arp([523.0, 659.0, 784.0, 1046.0], 0.08, "square", 0.13, 0.35),
	"reward": func() -> PackedFloat32Array: return arp([784.0, 1046.0, 1318.0, 1568.0], 0.06, "tri", 0.3, 0.35),
	"page_turn": func() -> PackedFloat32Array: return noise(0.35, 0.4, 900.0, 3500.0, 0.12, 2.5, 23),
	"portal": func() -> PackedFloat32Array: return mix([[tone(200.0, 1200.0, 0.6, "sine", 0.25, 0.05, 1.5), 0.0], [noise(0.6, 0.2, 500.0, 4000.0, 0.1, 1.5, 24), 0.0]]),
	"hope_up": func() -> PackedFloat32Array: return arp([659.0, 880.0], 0.08, "sine", 0.22, 0.3),
	"hope_down": func() -> PackedFloat32Array: return arp([440.0, 330.0], 0.1, "sine", 0.22, 0.35),
	# Enemies.
	"shoot": func() -> PackedFloat32Array: return tone(900.0, 400.0, 0.1, "square", 0.1, 0.002, 3.0),
	"slam": func() -> PackedFloat32Array: return mix([[tone(80.0, 40.0, 0.4, "sine", 0.6, 0.002, 2.5), 0.0], [noise(0.3, 0.5, 1200.0, 150.0, 0.001, 3.0, 25), 0.0]]),
	"charge": func() -> PackedFloat32Array: return noise(0.3, 0.35, 600.0, 2500.0, 0.05, 2.0, 26),
	"hop": func() -> PackedFloat32Array: return tone(180.0, 320.0, 0.1, "sine", 0.3, 0.004, 4.0),
	"screech": func() -> PackedFloat32Array: return mix([[tone(1400.0, 2200.0, 0.25, "saw", 0.12), 0.0], [noise(0.25, 0.2, 6000.0, 3000.0, 0.01, 3.0, 27), 0.0]]),
	"warning": func() -> PackedFloat32Array: return tone(880.0, 880.0, 0.12, "square", 0.1, 0.002, 2.0),
	# Bosses.
	"roar": func() -> PackedFloat32Array: return mix([[tone(110.0, 70.0, 1.0, "saw", 0.25, 0.08, 1.8), 0.0], [noise(1.0, 0.35, 700.0, 200.0, 0.1, 1.8, 28), 0.0]]),
	"boom": func() -> PackedFloat32Array: return mix([[tone(70.0, 35.0, 0.6, "sine", 0.7, 0.002, 2.2), 0.0], [noise(0.5, 0.55, 1500.0, 100.0, 0.001, 2.5, 29), 0.0]]),
	"splash": func() -> PackedFloat32Array: return noise(0.45, 0.5, 4000.0, 600.0, 0.01, 2.5, 30),
	"dive": func() -> PackedFloat32Array: return mix([[noise(0.5, 0.45, 2500.0, 300.0, 0.02, 2.0, 31), 0.0], [tone(300.0, 90.0, 0.4, "sine", 0.3), 0.0]]),
	"wave": func() -> PackedFloat32Array: return noise(1.4, 0.5, 400.0, 1800.0, 0.3, 1.2, 32),
	"fwoom": func() -> PackedFloat32Array: return mix([[noise(0.35, 0.5, 600.0, 2500.0, 0.02, 2.5, 33), 0.0], [tone(120.0, 60.0, 0.3, "sine", 0.3), 0.0]]),
	"puff": func() -> PackedFloat32Array: return noise(0.4, 0.3, 1200.0, 400.0, 0.06, 2.0, 34),
	"laser": func() -> PackedFloat32Array: return mix([[tone(220.0, 230.0, 1.6, "saw", 0.12, 0.05, 0.6), 0.0], [tone(440.0, 470.0, 1.6, "square", 0.06, 0.05, 0.6), 0.0]]),
	"shimmer": func() -> PackedFloat32Array: return arp([2093.0, 1568.0, 2637.0, 1975.0], 0.03, "sine", 0.18, 0.12),
	"boss_die": func() -> PackedFloat32Array: return mix([[tone(200.0, 40.0, 1.4, "saw", 0.25, 0.01, 1.6), 0.0], [noise(1.2, 0.4, 2000.0, 80.0, 0.01, 1.8, 35), 0.0], [arp([523.0, 659.0, 784.0, 1046.0], 0.12, "sine", 0.2, 0.6), 0.9]]),
	# Interface.
	"blip": func() -> PackedFloat32Array: return tone(620.0, 620.0, 0.03, "square", 0.06, 0.001, 3.0),
	"ui_tick": func() -> PackedFloat32Array: return tone(1200.0, 1000.0, 0.035, "tri", 0.18, 0.001, 4.0),
	"ui_select": func() -> PackedFloat32Array: return arp([880.0, 1320.0], 0.04, "tri", 0.22, 0.08),
	"ui_open": func() -> PackedFloat32Array: return noise(0.12, 0.25, 2000.0, 5000.0, 0.02, 3.0, 36),
	"ui_close": func() -> PackedFloat32Array: return noise(0.12, 0.25, 5000.0, 1500.0, 0.005, 3.0, 37),
	"error": func() -> PackedFloat32Array: return tone(200.0, 160.0, 0.15, "square", 0.12, 0.002, 2.0),
}
