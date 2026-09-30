extends Control
## タイトル画面。「プレイ / マルチプレイ / 遊び方 / 設定」の 4 項目。背景は、ランダムに選んだ曲の画像で、その曲を流しておく
## (曲が終わったら、別のランダムな曲へ)。遊び方と設定は、この画面の上に重ねるパネル(曲は流れ続ける)。
## 曲が 1 つもないときは、無音で暗い背景のまま。
##
## 操作: ↑↓ で選び、Enter で決定。マウスでも操作できる。

signal play_requested
signal multi_requested

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const HowToPanel = preload("res://scripts/ui/howto_panel.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

const BG_TINT := Color(0.4, 0.4, 0.46)
const ITEMS := [["プレイ", "PLAY"], ["マルチプレイ", "MULTIPLAYER"], ["遊び方", "HOW TO PLAY"], ["設定", "SETTINGS"]]
const MUSIC_DB := -4.0

var settings: Dictionary = {}

var _sel := 0
var _cards: Array = []
var _bg_holder: Control
var _bg: TextureRect
var _bg2: TextureRect
var _audio: AudioStreamPlayer
var _last_path := ""
var _overlay: Control        # 開いているパネル(遊び方 / 設定)
var _leaving := false


func _ready() -> void:
	settings = Settings.load_all()
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	_bg_holder = Control.new()
	_bg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_holder.pivot_offset = Vector2(640, 360)
	_bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_holder)
	_bg = _bg_layer()
	_bg2 = _bg_layer()
	if UiStyle.animate:   # 背景画像をごくゆっくり拡大・縮小し続ける
		var drift := create_tween().set_loops()
		drift.tween_property(_bg_holder, "scale", Vector2(1.08, 1.08), 24.0).from(Vector2(1.02, 1.02)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_bg_holder, "scale", Vector2(1.02, 1.02), 24.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 左が暗く右が明るい影(文字を読みやすく、背景の絵は右に残す)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.05, 0.3)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var grad := Control.new()
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grad.draw.connect(func():
		var c0 := Color(0.02, 0.025, 0.05, 0.85)
		var c1 := Color(0.02, 0.025, 0.05, 0.0)
		grad.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(760, 0), Vector2(760, 720), Vector2(0, 720)]), PackedColorArray([c0, c1, c1, c0])))
	add_child(grad)
	add_child(Ambient.new())

	# --- タイトルの文字 ---
	var logo := UiStyle.label("DDA", 132, UiStyle.ACCENT, true)
	logo.position = Vector2(104, 92)
	add_child(logo)
	var sub := UiStyle.label("OSU! DANMAKU DODGER", 20, UiStyle.TEXT_DIM)
	sub.position = Vector2(112, 250)
	add_child(sub)
	var ver := UiStyle.chip("BETA   v%s" % _version(), UiStyle.GOLD)
	ver.position = Vector2(112, 292)
	add_child(ver)
	UiStyle.pop_in(logo, 0.05, Vector2(-30, 0), 0.6)
	UiStyle.pop_in(sub, 0.15, Vector2(-30, 0), 0.6)
	UiStyle.pop_in(ver, 0.25, Vector2(-30, 0), 0.6)

	# --- 項目 ---
	var box := VBoxContainer.new()
	box.position = Vector2(104, 380)
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	for i in range(ITEMS.size()):
		var card := UiStyle.card(58, func(): _activate(i))
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 14)
		var name_l := UiStyle.label(ITEMS[i][0], 24, UiStyle.TEXT, true)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_l)
		var en := UiStyle.caption(ITEMS[i][1])
		en.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(en)
		card.add_child(h)
		card.mouse_entered.connect(func(): _select(i))
		var holder := UiStyle.wrap_card(card, 58)
		box.add_child(holder)
		_cards.append(card)
	_restyle()
	for i in range(_cards.size()):
		UiStyle.enter_card(_cards[i], 0.3 + 0.08 * i, -40.0)

	# 背景と曲は、最初の画面を出してから読み込む(読み込みで最初のフレームが遅れないように)
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -40.0
	_audio.finished.connect(_play_random)
	add_child(_audio)
	_play_random.call_deferred()


func _version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	return v.replace("-beta", "")


func _bg_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.modulate = Color(BG_TINT.r, BG_TINT.g, BG_TINT.b, 0.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_holder.add_child(t)
	return t


## 背景を、新しい画像へクロスフェードで入れ替える。
func _set_background(tex: Texture2D) -> void:
	var cur := _bg
	var nxt := _bg2
	nxt.texture = tex
	UiStyle.tween(nxt, "modulate:a", 0.0, 1.0 if tex != null else 0.0, 1.2, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	UiStyle.tween(cur, "modulate:a", cur.modulate.a, 0.0, 1.2, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_bg = nxt
	_bg2 = cur


# --- ランダムな曲 ---

## ランダムな曲(と、その中のランダムな譜面)を選んで、背景にして流す。直前と同じ曲は避ける。読めない曲は飛ばす。
func _play_random() -> void:
	if _leaving:
		return
	var paths := SongLibrary.find_all()
	if paths.is_empty():
		return
	paths.shuffle()
	if paths.size() > 1:
		paths.erase(_last_path)
	for path in paths:
		var l = OszLoader.new()
		if not l.open(path):
			continue
		var bm = l.difficulties[randi() % l.difficulties.size()]
		var stream: AudioStream = l.load_audio(bm.audio_filename)
		var tex: Texture2D = l.load_image(bm.background) if bm.background != "" else null
		l.close()
		if stream == null:
			continue
		_last_path = path
		_set_background(tex)
		_audio.stream = stream
		_audio.volume_db = -40.0
		_audio.play(maxf(bm.preview_time / 1000.0, 0.0))
		UiStyle.tween(_audio, "volume_db", -40.0, MUSIC_DB, 1.6)   # 曲は、ふわっと入る
		return


## 曲を小さくして止める。
func _fade_music(dur: float) -> void:
	if _audio == null or not _audio.playing:
		return
	if not UiStyle.animate:
		_audio.stop()
		return
	var t := _audio.create_tween()
	t.tween_property(_audio, "volume_db", -50.0, dur)
	t.tween_callback(_audio.stop)


# --- 項目の選択 ---

func _select(i: int) -> void:
	if i == _sel or _overlay != null or _leaving:
		return
	_sel = i
	_restyle()


func _restyle() -> void:
	for i in range(_cards.size()):
		var sel := (i == _sel)
		UiStyle.style_card(_cards[i], sel, true, UiStyle.ACCENT, false)
		UiStyle.shift_card(_cards[i], 14.0 if sel else 0.0)


func _activate(i: int) -> void:
	if _overlay != null or _leaving:
		return
	_sel = i
	_restyle()
	match i:
		0:
			_leaving = true
			_fade_music(0.35)
			if UiStyle.animate:
				await get_tree().create_timer(0.3).timeout
			play_requested.emit()
		1:
			_leaving = true
			_fade_music(0.35)
			if UiStyle.animate:
				await get_tree().create_timer(0.3).timeout
			multi_requested.emit()
		2:
			_open(HowToPanel.new())
		3:
			var p := OptionsPanel.new()
			p.setup(settings, Callable())
			_open(p)


func _open(panel: Control) -> void:
	_overlay = panel
	panel.closed.connect(_close_overlay)
	add_child(panel)
	if panel.has_method("show_section"):
		panel.show_section(0)


func _close_overlay() -> void:
	if _overlay == null:
		return
	Settings.save_all(settings)   # 設定パネルで変えた内容を保存(遊び方パネルでも害はない)
	_overlay.queue_free()
	_overlay = null


func _input(event: InputEvent) -> void:
	if _overlay != null or _leaving or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:
			_select(posmod(_sel + (-1 if event.keycode == KEY_UP else 1), ITEMS.size()))
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_activate(_sel)
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _audio != null:
		_audio.stop()
