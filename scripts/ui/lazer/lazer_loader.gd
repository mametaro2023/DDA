extends "res://scripts/ui/lazer/lazer_screen.gd"
## lazer 風の開始前画面(ひとりプレイの、選曲 → プレイの間に挟む)。選曲の発進の演出で拡大した背景をそのまま続け、
## 曲名・難易度・選んだ MOD だけを見せて、約 WAIT 秒で自動的にプレイへ進む(Enter・クリック・Space ですぐ進む。Esc で選曲へ戻る)。
## 進行そのものには関わらない(表示だけ)。リトライ・マルチプレイ・リプレイは通さない(main.gd が、選曲から始めるときだけ挟む)。

signal go_requested
signal back_requested

const Mods = preload("res://scripts/mods.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const WAIT := 1.6          # 自動で進むまでの秒数
const INPUT_GUARD := 0.35  # 表示してからこの間は、キー・クリックを受けない(「プレイ」のダブルクリックで、そのまま始まらないように)
const FADE_IN := 0.25      # 内容が現れる秒数

var kind := "loader"
## false なら、自動では進まない(撮影・確認用)
var auto := true

var _loader
var _bm
var _pre: Dictionary = {}
var _tex: Texture2D
var _zoom := 1.0
var _t := 0.0
var _done := false
var _overlay_open := false
var _rows: Array = []

func setup(p_loader, p_bm, p_settings: Dictionary, p_pre: Dictionary, p_bg: Texture2D, p_zoom := 1.0) -> void:
	_loader = p_loader
	_bm = p_bm
	settings = p_settings
	_pre = p_pre
	_tex = p_bg
	_zoom = p_zoom


func _ready() -> void:
	backdrop_bright = true
	_build_base()
	if _tex == null and _bm.background != "":   # 選曲から画像を受け取れなかったとき(読み直す)
		_tex = _loader.load_image(_bm.background)
	set_background(_tex, true)
	# 選曲の発進の演出が終わった大きさ・速さのまま、同じ向きに(ズームインし続ける。止まったり戻ったりしない)
	var dur := WAIT + 0.6
	_bg_holder.scale = Vector2(_zoom, _zoom)
	var z1 := _zoom + LazerStyle.LAUNCH_ZOOM_SPEED * dur
	UiStyle.tween(_bg_holder, "scale", Vector2(_zoom, _zoom), Vector2(z1, z1), dur, 0.0, Tween.TRANS_LINEAR)
	_par = ((get_viewport().get_mouse_position() - Vector2(640, 360)) / Vector2(640, 360)).clampf(-1.0, 1.0)   # 視差も、選曲のときの続きから
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_content()

func _build_content() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	var title := LazerStyle.label(str(_bm.title), 44, LazerStyle.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(980, 0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 6)
	_add_row(col, title)
	var artist := LazerStyle.label(str(_bm.artist), 24, LazerStyle.TEXT_DIM)
	artist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	artist.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_add_row(col, artist)
	_add_gap(col, 22)

	# 難易度: Lv の札(星の色)・難易度名・譜面の作者
	var diff := HBoxContainer.new()
	diff.alignment = BoxContainer.ALIGNMENT_CENTER
	diff.add_theme_constant_override("separation", 12)
	diff.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := float(_pre.get("level", -1.0))
	if lv >= 0.0:
		diff.add_child(LazerStyle.pill("★ %.2f" % lv, LazerStyle.level_color(lv), 16))
	diff.add_child(LazerStyle.label(str(_bm.version), 22, LazerStyle.TEXT, true))
	if str(_bm.creator) != "":
		diff.add_child(LazerStyle.label("譜面  %s" % str(_bm.creator), 15, LazerStyle.TEXT_MUTE))
	_add_row(col, diff)

	# 選んだ MOD(なければ何も出さない)
	var p := Mods.params(settings.get("mods", []))
	if not p.ids.is_empty():
		_add_gap(col, 20)
		var mods := HBoxContainer.new()
		mods.alignment = BoxContainer.ALIGNMENT_CENTER
		mods.add_theme_constant_override("separation", 8)
		mods.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for id in p.ids:
			var m := Mods.find(id)
			var c: Color = m.color
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", LazerStyle.box(Color(c.r, c.g, c.b, 0.22), Color(c.r, c.g, c.b, 0.8), 1, 12, 10, 2))
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(LazerStyle.label(str(m.name), 15, c))
			mods.add_child(chip)
		_add_row(col, mods)

	# 選曲の画面が消えたあとに、上から順に、すばやくなめらかに現れる(再表示のちらつきや、跳ねる動きは入れない)
	for i in range(_rows.size()):
		var r: Control = _rows[i]
		r.modulate.a = 0.0
		UiStyle.tween(r, "modulate:a", 0.0, 1.0, FADE_IN, 0.03 * i, Tween.TRANS_SINE, Tween.EASE_OUT)


func _add_row(col: Control, c: Control) -> void:
	col.add_child(c)
	_rows.append(c)


func _add_gap(col: Control, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)


func _process(delta: float) -> void:
	super._process(delta)
	if _done:
		return
	if auto:
		_t += delta
	if auto and _t >= WAIT:
		_go()

func _go() -> void:
	if _done:
		return
	_done = true
	go_requested.emit()

func _back() -> void:
	if _done:
		return
	_done = true
	UiSfx.play("back")
	back_requested.emit()

## 設定などのパネルが開いている間は、キー・クリックを受けない(ui_set.gd の契約)
func on_overlay(open: bool, _panel: Control = null) -> void:
	_overlay_open = open

func _input(e: InputEvent) -> void:
	if _done or _overlay_open or _t < INPUT_GUARD:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				get_viewport().set_input_as_handled()
				_go()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_back()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_go()
