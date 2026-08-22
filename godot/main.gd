extends Node2D
## Viewer for the document. The world is the artifact; this is a window onto it.

const WS := preload("res://world.gd")

const ORIGIN_Y := 24.0
var ORIGIN := Vector2(24, 24)
var PX := 10
var COL_X := 1032          # right column origin
var COL_W := 864

var world: WorldSim
var px: PackedByteArray
var tex: ImageTexture
var playing := true
var tps := 30.0
var acc := 0.0
var dirty := true
var frame := 0
var last_hash := 0
var fork_tick := -1

var lbl_tick: Label
var lbl_pop: Label
var lbl_genes: Label
var lbl_hash: Label
var lbl_fork: Label
var btn_play: Button
var sld_speed: HSlider
var sld_time: HSlider
var graph: Control

func _ready() -> void:
	world = WS.new_seeded(20260822)
	px = PackedByteArray()
	px.resize(WS.W * WS.H * 4)
	var sprite: Sprite2D = $WorldSprite
	tex = ImageTexture.create_from_image(_compose_image())
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_layout(sprite)
	_build_ui()

func _layout(sprite: Sprite2D) -> void:
	## measure, don't assume: fit the world square to the actual window,
	## hug the control column against it — no stranded gaps at any size.
	var vp := get_viewport().get_visible_rect().size
	var side := mini(vp.y - 48.0, vp.x * 0.52 - 48.0)
	PX = clampi(int(side / WS.W), 4, 16)
	ORIGIN = Vector2(24, (vp.y - PX * WS.W) / 2.0)
	sprite.position = ORIGIN
	sprite.scale = Vector2(PX, PX)
	COL_X = int(ORIGIN.x + PX * WS.W + 40)
	COL_W = int(vp.x - COL_X - 32)

func _process(delta: float) -> void:
	frame += 1
	if playing:
		acc += delta * tps
		var steps := int(acc)
		acc -= steps
		steps = mini(steps, 500)
		for k in range(steps):
			world.tick_step()
		if steps > 0:
			dirty = true
			sld_time.set_value_no_signal(world.tick)
			sld_time.max_value = maxi(int(sld_time.max_value), world.tick)
	if dirty:
		dirty = false
		tex.update(_compose_image())
	_maybe_capture()
	if frame % 10 == 0:
		_update_hud()

# ---------------------------------------------------------------- render
func _compose_image() -> Image:
	var n := WS.W * WS.H
	px.resize(n * 4)
	for i in range(n):
		var b := world.plants[i]
		var cap := maxi(1, world.fert[i])
		var ripe := (b * 100) / cap                       # 0..100
		px[i * 4] = 12 + (cap * 10) / 160 + ripe / 5      # soil warmth + ripening
		px[i * 4 + 1] = 14 + (b * 400) / (cap + b * 2)    # plant green, hyperbolic: sparse grass stays visible
		px[i * 4 + 2] = 11
		px[i * 4 + 3] = 255
	for c in world.creatures:
		var col := Color.from_hsv((c.genes.hue as int) / 360.0, 0.9, 1.0)
		var cx: int = c.x as int
		var cy: int = c.y as int
		var arms_x := [0, 1, -1, 0, 0]
		var arms_y := [0, 0, 0, 1, -1]
		for arm in range(5):   # plus-shaped: reads as organism, not confetti
			var xx: int = cx + arms_x[arm]
			var yy: int = cy + arms_y[arm]
			if xx < 0 or xx >= WS.W or yy < 0 or yy >= WS.H:
				continue
			var j := (yy * WS.W + xx) * 4
			px[j] = int(col.r8); px[j + 1] = int(col.g8); px[j + 2] = int(col.b8)
	return Image.create_from_data(WS.W, WS.H, false, Image.FORMAT_RGBA8, px)

func _draw_graph() -> void:
	var rect := Rect2(Vector2.ZERO, graph.size)
	graph.draw_rect(rect, Color(0, 0, 0, 0.45))
	graph.draw_rect(rect, Color(1, 1, 1, 0.15), false, 1.0)
	_draw_curve(world.stats_plant, Color(0.35, 0.9, 0.4, 0.8), rect, 2.0)
	_draw_curve(world.stats_pop, Color(1, 1, 1, 0.95), rect, 3.0)

func _draw_curve(arr: PackedInt32Array, col: Color, rect: Rect2, width := 3.0) -> void:
	var n := arr.size()
	if n < 2:
		return
	var mx := 1
	for v in arr:
		mx = maxi(mx, v)
	var pts := PackedVector2Array()
	pts.resize(n)
	for k in range(n):
		var fx := rect.position.x + rect.size.x * k / float(n - 1)
		var fy := rect.end.y - rect.size.y * 0.9 * arr[k] / mx
		pts[k] = Vector2(fx, fy)
	graph.draw_polyline(pts, col, width)

# ---------------------------------------------------------------- HUD
func _update_hud() -> void:
	lbl_tick.text = "tick %d   speed %d tps" % [world.tick, int(tps)]
	var pop := world.creatures.size()
	var avg_eff := 0
	var avg_spd := 0
	var avg_sense := 0
	if pop > 0:
		for c in world.creatures:
			avg_eff += c.genes.eff
			avg_spd += c.genes.speed
			avg_sense += c.genes.sense
		avg_eff /= pop; avg_spd /= pop; avg_sense /= pop
	var plants_now: int = world.stats_plant[-1] if world.stats_plant.size() > 0 else 0
	lbl_pop.text = "pop %d   plants %d" % [pop, plants_now]
	lbl_genes.text = "avg genes  eff %d%%  spd %d  sense %d" % [avg_eff, avg_spd, avg_sense]
	if frame % 30 == 0:
		last_hash = world.state_hash()
		lbl_hash.text = "hash %016X" % (last_hash & 0x7FFFFFFFFFFFFFFF)
	lbl_fork.text = "forked @ tick %d" % fork_tick if fork_tick >= 0 else ""
	if frame % 5 == 0:
		graph.queue_redraw()

# ---------------------------------------------------------------- controls
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	var x := COL_X
	lbl_tick = _mk_label(ui, Vector2(x, 28))
	lbl_pop = _mk_label(ui, Vector2(x, 64))
	lbl_genes = _mk_label(ui, Vector2(x, 100))
	lbl_hash = _mk_label(ui, Vector2(x, 136))
	lbl_fork = _mk_label(ui, Vector2(x, 172))

	btn_play = Button.new()
	btn_play.text = "pause"
	btn_play.position = Vector2(x, 214)
	btn_play.size = Vector2(140, 44)
	btn_play.add_theme_font_size_override("font_size", 20)
	btn_play.pressed.connect(_on_play)
	ui.add_child(btn_play)

	var btn_fork := Button.new()
	btn_fork.text = "fork timeline (F)"
	btn_fork.position = Vector2(x + 160, 214)
	btn_fork.size = Vector2(220, 44)
	btn_fork.add_theme_font_size_override("font_size", 20)
	btn_fork.pressed.connect(_fork)
	ui.add_child(btn_fork)

	var btn_new := Button.new()
	btn_new.text = "new world (N)"
	btn_new.position = Vector2(x + 400, 214)
	btn_new.size = Vector2(210, 44)
	btn_new.add_theme_font_size_override("font_size", 20)
	btn_new.pressed.connect(_on_new)
	ui.add_child(btn_new)

	var lbl_speed := Label.new()
	lbl_speed.text = "speed"
	lbl_speed.position = Vector2(x, 284)
	ui.add_child(lbl_speed)
	sld_speed = HSlider.new()
	sld_speed.min_value = 0
	sld_speed.max_value = 240
	sld_speed.step = 10
	sld_speed.value = 30
	sld_speed.position = Vector2(x + 90, 290)
	sld_speed.size = Vector2(COL_W - 110, 24)
	sld_speed.value_changed.connect(func(v): tps = v)
	ui.add_child(sld_speed)

	var lbl_time := Label.new()
	lbl_time.text = "timeline"
	lbl_time.position = Vector2(x, 332)
	ui.add_child(lbl_time)
	sld_time = HSlider.new()
	sld_time.min_value = 0
	sld_time.max_value = 60
	sld_time.step = 1
	sld_time.value = 0
	sld_time.position = Vector2(x + 110, 340)
	sld_time.size = Vector2(COL_W - 130, 24)
	sld_time.value_changed.connect(_on_scrub)
	ui.add_child(sld_time)

	graph = Control.new()
	graph.position = Vector2(x, 396)
	graph.size = Vector2(COL_W, get_viewport().get_visible_rect().size.y * 0.38)
	graph.draw.connect(_draw_graph)
	ui.add_child(graph)

	var gy := 396.0 + graph.size.y
	var help := Label.new()
	help.text = "space pause/run    arrows scrub time    F fork    N new world    T speed cycle    R record frames"
	help.position = Vector2(x, gy + 20)
	help.modulate = Color(1, 1, 1, 0.5)
	ui.add_child(help)

	lbl_debug = Label.new()
	lbl_debug.position = Vector2(x, gy + 52)
	lbl_debug.modulate = Color(0.5, 1, 0.5, 0.85)
	lbl_debug.add_theme_font_size_override("font_size", 18)
	ui.add_child(lbl_debug)

func _mk_label(parent: Node, pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", 22)
	parent.add_child(l)
	return l

func _on_play() -> void:
	playing = not playing
	btn_play.text = "run" if not playing else "pause"

func _on_new() -> void:
	_new_world(Time.get_ticks_usec())

func _on_scrub(t: float) -> void:
	var target := int(t)
	if target == world.tick:
		return
	playing = false
	btn_play.text = "run"
	world.restore_to_tick(target)
	dirty = true

func _fork() -> void:
	## mutate only the future's dice; state and shared past stay intact.
	world.seed_i ^= mix_of_tick()
	fork_tick = world.tick
	dirty = true

func mix_of_tick() -> int:
	return WorldSim.mix64(world.tick * 2654435761 + 1)

func _new_world(seed_val: int) -> void:
	world = WS.new_seeded(seed_val)
	fork_tick = -1
	sld_time.set_value_no_signal(0)
	sld_time.max_value = 60
	acc = 0.0
	playing = true
	btn_play.text = "pause"
	dirty = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		_toggle_pause()
	elif event.is_action_pressed("scrub_back"):
		_jump(-60)
	elif event.is_action_pressed("scrub_fwd"):
		_jump(60)
	elif event.is_action_pressed("jump_back"):
		_jump(-600)
	elif event.is_action_pressed("jump_fwd"):
		_jump(600)
	elif event.is_action_pressed("fork_timeline"):
		_fork()
	elif event.is_action_pressed("speed_cycle"):
		var i := SPEED_PRESETS.find(int(tps))
		tps = SPEED_PRESETS[(i + 1) % SPEED_PRESETS.size()] if i >= 0 else SPEED_PRESETS[0]
		sld_speed.set_value_no_signal(tps)
		_note("speed %d tps" % int(tps))
	elif event.is_action_pressed("record_toggle"):
		_toggle_record()

var lbl_debug: Label
var debug_lines: PackedStringArray = PackedStringArray()
var recording := false
var frame_idx := 0
var last_rec_tick := -1000000
const SPEED_PRESETS := [30, 90, 240]

func _note(s: String) -> void:
	debug_lines.append(s)
	if debug_lines.size() > 4:
		debug_lines = debug_lines.slice(debug_lines.size() - 4)
	lbl_debug.text = "\n".join(debug_lines)

func _toggle_record() -> void:
	recording = not recording
	if recording:
		frame_idx = 0
		var dir := "user://frames"
		DirAccess.make_dir_recursive_absolute(dir)
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + "/" + f)
	_last_note_rec()

func _last_note_rec() -> void:
	_note("recording %s  frames=%d" % ["ON" if recording else "OFF", frame_idx])

func _maybe_capture() -> void:
	if not recording or world.tick - last_rec_tick < 30:
		return
	last_rec_tick = world.tick
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://frames/frame_%05d.png" % frame_idx)
	frame_idx += 1

func _toggle_pause() -> void:
	playing = not playing
	btn_play.text = "run" if not playing else "pause"
	_note("pause btn: playing=%s t=%d" % [playing, world.tick])

func _jump(delta_ticks: int) -> void:
	var target := clampi(world.tick + delta_ticks, 0, int(sld_time.max_value))
	_note("jump %+d: %d -> %d" % [delta_ticks, world.tick, target])
	if target == world.tick:
		return
	playing = false
	btn_play.text = "run"
	world.restore_to_tick(target)
	sld_time.set_value_no_signal(target)
	dirty = true
