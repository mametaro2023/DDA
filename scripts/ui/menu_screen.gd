extends Control
## 選曲画面。左に曲、右に難易度カード。MOD・操作・音・ゲームの設定は「OPTIONS」(options_panel.gd)に分けてある。
## .osz は、プロジェクト直下 / songs / 実行ファイルの隣 / user://songs を自動検出し、ドラッグ&ドロップや「開く」でも追加できる。
##
## 操作: ↑↓ 選択、← → / Tab で「曲 ⇔ 難易度」の切替、Enter 開始、O で設定、Esc でタイトルへ。マウスでも全部できる(難易度のダブルクリックで開始)。

signal play_requested(loader, bm, settings: Dictionary)
signal back_requested

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

const BG_TINT := Color(0.34, 0.34, 0.4)

## 難易度カードの弾数バー(平均・最大)の満点
const BAR_MAX := 500.0

var settings: Dictionary = {}

var _songs: Array = []          # [{path, title, artist}]
var _loader                     # 選択中の OszLoader
var _gens: Array = []           # 難易度リストと同じ並びの、MOD 適用前の弾幕(生成結果)
var _ratings: Array = []        # 同じ並びの DDA 難易度(MOD 適用後)
var _song_sel := -1
var _diff_sel := -1
var _focus_diff := true         # ↑↓ の対象: true = 難易度 / false = 曲
var _song_cards: Array = []
var _diff_cards: Array = []

var _bg: TextureRect            # 今見えている背景(もう 1 枚 _bg2 と交代でクロスフェードする)
var _bg2: TextureRect
var _bg_holder: Control
var _intro_nodes: Array = []       # 入場アニメーションで滑り込むもの
var _buttons: Array = []           # ホバーで少し大きくなるボタン
var _lv_shown := {}             # 難易度名 → 表示中の Lv(MOD で変わるとき、前の値から数え直す)
var _song_box: VBoxContainer
var _diff_box: VBoxContainer
var _diff_scroll: ScrollContainer
var _song_scroll: ScrollContainer
var _title_l: Label
var _artist_l: Label
var _meta_l: Label
var _detail_l: Label
var _mod_bar: HBoxContainer
var _status: Label
var _audio: AudioStreamPlayer
var _dialog: FileDialog
var _options: Control


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
	if UiStyle.animate:   # 背景画像をごくゆっくり拡大・縮小する(ずっと動き続ける)
		var drift := create_tween().set_loops()
		drift.tween_property(_bg_holder, "scale", Vector2(1.08, 1.08), 22.0).from(Vector2(1.02, 1.02)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(_bg_holder, "scale", Vector2(1.02, 1.02), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.05, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	add_child(Ambient.new())   # 背景で漂うリング

	# --- 左: 曲リスト ---
	_intro_nodes.append(_place(UiStyle.label("DDA", 30, UiStyle.ACCENT, true), 36, 20, 200, 40))
	_intro_nodes.append(_place(UiStyle.caption("OSU! DANMAKU DODGER"), 38, 62, 300, 16))
	var back_btn := Button.new()
	back_btn.text = "◀  タイトル"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): back_requested.emit())
	_intro_nodes.append(_place(back_btn, 312, 24, 124, 32))
	_buttons.append(back_btn)
	_intro_nodes.append(_place(UiStyle.caption("SONGS"), 38, 96, 200, 16))
	_song_scroll = ScrollContainer.new()
	_song_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_song_scroll, 32, 118, 404, 494)
	_song_box = VBoxContainer.new()
	_song_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_song_box.add_theme_constant_override("separation", 6)
	_song_scroll.add_child(_song_box)
	var open_btn := Button.new()
	open_btn.text = ".osz を開く…"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
	_intro_nodes.append(_place(open_btn, 32, 626, 404, 40))
	_buttons.append(open_btn)

	# --- 右: 曲情報 + 難易度カード ---
	_title_l = UiStyle.label("", 28, UiStyle.TEXT, true)
	_title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(_title_l, 468, 26, 780, 40)
	_artist_l = UiStyle.label("", 16, UiStyle.TEXT_DIM)
	_artist_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(_artist_l, 468, 70, 780, 24)
	_meta_l = UiStyle.label("", 13, UiStyle.TEXT_FAINT)
	_place(_meta_l, 468, 98, 780, 20)
	_place(UiStyle.caption("DIFFICULTY"), 470, 146, 780, 16)
	_diff_scroll = ScrollContainer.new()
	_diff_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(_diff_scroll, 468, 168, 780, 384)
	_diff_box = VBoxContainer.new()
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_box.add_theme_constant_override("separation", 6)
	_diff_scroll.add_child(_diff_box)

	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.35), UiStyle.LINE, 1, 5, 14, 8))
	_intro_nodes.append(_place(detail, 468, 562, 780, 38))
	_detail_l = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	detail.add_child(_detail_l)

	# --- 下部バー: MOD / OPTIONS / PLAY ---
	_mod_bar = HBoxContainer.new()
	_mod_bar.add_theme_constant_override("separation", 8)
	_intro_nodes.append(_place(_mod_bar, 468, 626, 520, 40))
	var opt_btn := Button.new()
	opt_btn.text = "設定"
	opt_btn.focus_mode = Control.FOCUS_NONE
	opt_btn.pressed.connect(func(): open_options(0))
	_intro_nodes.append(_place(opt_btn, 996, 626, 118, 40))
	_buttons.append(opt_btn)
	var play := Button.new()
	play.text = "PLAY"
	play.focus_mode = Control.FOCUS_NONE
	play.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9), Color(0, 0, 0, 0), 0, 4, 16, 8))
	play.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	play.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		play.add_theme_color_override(k, Color(0.02, 0.06, 0.1))
	play.add_theme_font_override("font", UiStyle.bold())
	play.pressed.connect(_start)
	_intro_nodes.append(_place(play, 1124, 626, 124, 40))
	_buttons.append(play)
	_status = UiStyle.label("", 12, UiStyle.TEXT_FAINT)   # 読み込みに失敗したときのメッセージ用
	_place(_status, 470, 680, 780, 18)

	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -6.0
	add_child(_audio)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.osz ; osu! beatmap"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_add_song_and_select)
	add_child(_dialog)

	get_window().files_dropped.connect(_on_files_dropped)
	_refresh_mod_bar()
	_intro()
	_scan()
	_rebuild_song_cards()
	if not _songs.is_empty():
		var pick := 0
		for i in range(_songs.size()):
			if _songs[i].path == settings.last_song:
				pick = i
		_select_song(pick)


func _exit_tree() -> void:
	var w := get_window()
	if w != null and w.files_dropped.is_connected(_on_files_dropped):
		w.files_dropped.disconnect(_on_files_dropped)


## 画面を開いたときの入場: 見出し・下部バー・ボタンが順に滑り込み、ボタンはホバーで少し大きくなる。
func _intro() -> void:
	var k := 0
	for c in _intro_nodes:
		UiStyle.pop_in(c, 0.05 + k * 0.05, Vector2(0, 18) if c.position.y > 500.0 else Vector2(-24, 0), 0.5)
		k += 1
	for b in _buttons:
		UiStyle.hover_scale(b)


func _bg_layer() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.modulate = Color(BG_TINT.r, BG_TINT.g, BG_TINT.b, 0.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_holder.add_child(t)
	return t


## 背景画像を、前の画像からクロスフェードで切り替える。
func _set_background(tex: Texture2D) -> void:
	var cur := _bg
	var nxt := _bg2
	nxt.texture = tex
	var to_a := 1.0 if tex != null else 0.0
	UiStyle.tween(nxt, "modulate:a", 0.0, to_a, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	UiStyle.tween(cur, "modulate:a", cur.modulate.a, 0.0, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_bg = nxt
	_bg2 = cur


func _place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	add_child(c)
	return c


# --- 曲の検出 ---

func _search_dirs() -> Array:
	return SongLibrary.search_dirs()


func _scan() -> void:
	_songs.clear()
	for d in _search_dirs():
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".osz"):
				_add_song(d.path_join(f))


## 追加して一覧の index を返す(重複は既存の index、読めなければ -1)。カードは _rebuild_song_cards で作る。
func _add_song(path: String) -> int:
	path = path.replace("\\", "/")
	for i in range(_songs.size()):
		if _songs[i].path == path:
			return i
	var l = OszLoader.new()
	if not l.open(path):
		return -1
	var bm = l.difficulties[0]
	_songs.append({"path": path, "title": bm.title, "artist": bm.artist})
	l.close()
	return _songs.size() - 1


func _add_song_and_select(path: String) -> void:
	var i := _add_song(path)
	if i < 0:
		_status.text = "読み込めませんでした: " + path.get_file()
		return
	_rebuild_song_cards()
	_select_song(i)


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.to_lower().ends_with(".osz"):
			_add_song_and_select(f)
			return
	_status.text = ".osz ファイル以外は読み込めません"


# --- 曲リスト ---

func _rebuild_song_cards() -> void:
	for c in _song_box.get_children():
		c.queue_free()
	_song_cards.clear()
	for i in range(_songs.size()):
		var card := UiStyle.card(56, func(): _focus_diff = false; _select_song(i))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UiStyle.label(_songs[i].title, 15, UiStyle.TEXT, true)
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(t)
		var a := UiStyle.label(_songs[i].artist, 12, UiStyle.TEXT_DIM)
		a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(a)
		card.add_child(v)
		card.mouse_entered.connect(func(): card.set_meta("hover", true); _restyle_song(i))
		card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_song(i))
		_song_box.add_child(UiStyle.wrap_card(card, 56))
		_song_cards.append(card)
		_restyle_song(i)
		UiStyle.enter_card(card, 0.08 + i * 0.06, -40.0)   # 左から順に滑り込む


func _restyle_song(i: int) -> void:
	if i < 0 or i >= _song_cards.size():
		return
	var c: PanelContainer = _song_cards[i]
	var sel := (i == _song_sel)
	var hover := bool(c.get_meta("hover", false))
	UiStyle.style_card(c, sel, not _focus_diff, UiStyle.ACCENT, hover)
	UiStyle.shift_card(c, (10.0 if not _focus_diff else 6.0) if sel else (4.0 if hover else 0.0))   # 選択中・ホバー中は少し右へ


func _select_song(i: int) -> void:
	if _songs.is_empty():
		return
	i = clampi(i, 0, _songs.size() - 1)
	if i == _song_sel and _loader != null:
		_restyle_all()
		return
	var l = OszLoader.new()
	if not l.open(_songs[i].path):
		_status.text = l.error
		return
	if _loader != null:
		_loader.close()
	_loader = l
	var old := _song_sel
	_song_sel = i
	_restyle_song(old)
	_restyle_song(i)
	_song_scroll.ensure_control_visible(_song_cards[i])

	var first = _loader.difficulties[0]
	_title_l.text = first.title
	_artist_l.text = first.artist
	_meta_l.text = "BPM %.0f     Creator  %s" % [60000.0 / first.beat_length_at(first.first_time()), first.creator]
	var k := 0
	for lab in [_title_l, _artist_l, _meta_l]:   # 曲情報は順に滑り込む
		UiStyle.pop_in(lab, k * 0.07, Vector2(30, 0), 0.45)
		k += 1
	_set_background(_loader.load_image(first.background) if first.background != "" else null)
	# DDA 難易度(画面内の弾数。MOD なしの状態)の低い順に並べ替える
	var pairs: Array = []
	for bm in _loader.difficulties:
		pairs.append({"bm": bm, "g": PatternGen.generate(bm, {"density_mul": settings.density_mul})})
	pairs.sort_custom(func(a, b): return a.g.rating.score < b.g.rating.score)
	_loader.difficulties = pairs.map(func(p): return p.bm)
	_gens = pairs.map(func(p): return p.g)
	_rate_all()
	_diff_sel = mini(2, _gens.size() - 1)
	# 直前にプレイした曲に戻ったときは、そのとき選んだ難易度を選んだ状態にする
	if _songs[i].path == settings.last_song and settings.last_diff != "":
		for k2 in range(_loader.difficulties.size()):
			if _loader.difficulties[k2].version == settings.last_diff:
				_diff_sel = k2
	_lv_shown.clear()
	_rebuild_diff_cards(true)
	_play_preview(first)


func _play_preview(bm) -> void:
	_audio.stop()
	var s: AudioStream = _loader.load_audio(bm.audio_filename)
	if s == null:
		return
	_audio.stream = s
	_audio.play(maxf(bm.preview_time / 1000.0, 0.0))


# --- 難易度カード ---

## 全難易度について、今の MOD を適用した弾幕で難易度を測り直す。
func _rate_all() -> void:
	var p := Mods.params(settings.mods)
	_ratings = _gens.map(func(g): return PatternGen.summary(Mods.apply(g, p)))


## animate_in = true(曲を選び直したとき)は、カードが右から滑り込み、Lv が 0 から数え上がる。MOD などで作り直すときは、前の Lv から数え直す。
func _rebuild_diff_cards(animate_in := false) -> void:
	for c in _diff_box.get_children():
		c.queue_free()
	_diff_cards.clear()
	for i in range(_ratings.size()):
		var bm = _loader.difficulties[i]
		var r: Dictionary = _ratings[i]
		var col := UiStyle.level_color(r.level)
		var card := UiStyle.card(68, func(): _focus_diff = true; _select_diff(i), func(): _start())
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Lv(大きく。値で色が変わる)
		var lv := VBoxContainer.new()
		lv.custom_minimum_size = Vector2(92, 0)
		lv.add_theme_constant_override("separation", -2)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(UiStyle.caption("LV"))
		var lv_l := UiStyle.label("%.2f" % r.level, 30, col, true)
		lv.add_child(lv_l)
		h.add_child(lv)
		# 名前と補助情報
		var nm := VBoxContainer.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.alignment = BoxContainer.ALIGNMENT_CENTER
		nm.add_theme_constant_override("separation", 3)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_l := UiStyle.label(bm.version, 17, UiStyle.TEXT, true)
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.add_child(name_l)
		var sub := "本家★≈%.2f" % r.stars
		if absf(r.level - r.base_level) >= 0.005:
			sub += "     MODなし  Lv %.2f" % r.base_level   # MOD 適用後との差が分かるように
		nm.add_child(UiStyle.label(sub, 12, UiStyle.TEXT_DIM))
		h.add_child(nm)
		# 弾数バー(平均と最大)
		var bars_box := VBoxContainer.new()
		bars_box.custom_minimum_size = Vector2(210, 0)
		bars_box.alignment = BoxContainer.ALIGNMENT_CENTER
		bars_box.add_theme_constant_override("separation", 4)
		bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars_box.add_child(UiStyle.label("平均 %d  ·  最大 %d 発" % [int(round(r.mean)), int(r.peak)], 12, UiStyle.TEXT_DIM))
		var bars := _bars(clampf(r.mean / BAR_MAX, 0.0, 1.0), clampf(r.peak / BAR_MAX, 0.0, 1.0), col)
		bars_box.add_child(bars)
		h.add_child(bars_box)
		card.add_child(h)
		card.mouse_entered.connect(func(): card.set_meta("hover", true); _restyle_diff(i))
		card.mouse_exited.connect(func(): card.set_meta("hover", false); _restyle_diff(i))
		_diff_box.add_child(UiStyle.wrap_card(card, 68))
		_diff_cards.append(card)
		_restyle_diff(i)
		var delay := (0.1 + i * 0.07) if animate_in else 0.0
		if animate_in:
			UiStyle.enter_card(card, delay, 50.0)
		# Lv は数え上がり(または前の値から)、弾数バーは左から伸びる
		var key: String = bm.version
		var from_lv: float = 0.0 if animate_in else float(_lv_shown.get(key, r.level))
		var set_lv := func(v: float):
			lv_l.text = "%.2f" % v
			lv_l.add_theme_color_override("font_color", UiStyle.level_color(v))
			_lv_shown[key] = v
		UiStyle.tween_value(lv_l, from_lv, r.level, 0.55, set_lv, delay + (0.1 if animate_in else 0.0))
		var state: Dictionary = bars.get_meta("state")
		var grow := func(v: float):
			state.p = v
			bars.queue_redraw()
		UiStyle.tween_value(bars, 0.0, 1.0, 0.7, grow, delay + 0.15)
	_update_detail()
	_refresh_mod_bar()
	if _diff_sel >= 0 and _diff_sel < _diff_cards.size():
		# カードのレイアウト確定後にスクロール位置を合わせる
		_diff_scroll.ensure_control_visible.call_deferred(_diff_cards[_diff_sel])


## 平均・最大の弾数を、2 本の細いバーで表す。
func _bars(mean_f: float, peak_f: float, col: Color) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(210, 14)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var state := {"p": 1.0}   # 0 → 1 で左から伸びる
	b.set_meta("state", state)
	b.draw.connect(func():
		var w: float = b.size.x * state.p
		b.draw_rect(Rect2(0, 1, w, 4), Color(1, 1, 1, 0.1))
		b.draw_rect(Rect2(0, 1, w * mean_f, 4), col)
		b.draw_rect(Rect2(0, 9, w, 4), Color(1, 1, 1, 0.1))
		b.draw_rect(Rect2(0, 9, w * peak_f, 4), Color(col.r, col.g, col.b, 0.5)))
	return b


func _restyle_diff(i: int) -> void:
	if i < 0 or i >= _diff_cards.size():
		return
	var c: PanelContainer = _diff_cards[i]
	var col: Color = UiStyle.level_color(_ratings[i].level)
	var sel := (i == _diff_sel)
	var hover := bool(c.get_meta("hover", false))
	UiStyle.style_card(c, sel, _focus_diff, col, hover)
	UiStyle.shift_card(c, (10.0 if _focus_diff else 6.0) if sel else (4.0 if hover else 0.0))


func _restyle_all() -> void:
	for i in range(_song_cards.size()):
		_restyle_song(i)
	for i in range(_diff_cards.size()):
		_restyle_diff(i)


func _select_diff(i: int) -> void:
	if _diff_cards.is_empty():
		return
	i = clampi(i, 0, _diff_cards.size() - 1)
	var old := _diff_sel
	_diff_sel = i
	_restyle_all()
	_diff_scroll.ensure_control_visible(_diff_cards[i])
	_update_detail()
	if _options != null and old != i:
		_options.refresh_mod_info()


## 選択中の難易度の詳細(弾速・弾径・弾数・長さ)。
func _update_detail() -> void:
	if _diff_sel < 0 or _diff_sel >= _ratings.size():
		_detail_l.text = ""
		return
	var r: Dictionary = _ratings[_diff_sel]
	var bm = _loader.difficulties[_diff_sel]
	UiStyle.tween(_detail_l, "modulate:a", 0.25, 1.0, 0.25)   # 選択が変わると、詳細がふわっと入れ替わる
	var secs := int(round((bm.last_time() - bm.first_time()) / 1000.0))
	_detail_l.text = "弾速 %d px/s     弾径 %.1f     平均 %d 発 / 最大 %d 発     イベント %d     長さ %d:%02d" % [
		int(round(r.speed)), r.size, int(round(r.mean)), int(r.peak), _gens[_diff_sel].events.size(), secs / 60, secs % 60]


# --- 下部バー(付けている MOD) ---

func _refresh_mod_bar() -> void:
	for c in _mod_bar.get_children():
		c.queue_free()
	var p := Mods.params(settings.mods)
	if p.ids.is_empty():
		_mod_bar.add_child(UiStyle.label("MOD なし", 13, UiStyle.TEXT_FAINT))
		return
	for id in p.ids:
		var m := Mods.find(id)
		_mod_bar.add_child(UiStyle.chip(m.name, m.color))
	_mod_bar.add_child(UiStyle.label("ベーススコア ×%.4f" % p.score_mul, 13, UiStyle.TEXT_DIM))


# --- 設定パネル ---

func open_options(section := 0) -> void:
	if _options != null:
		return
	_options = OptionsPanel.new()
	_options.setup(settings, _mod_preview_text)
	_options.changed.connect(_on_option_changed)
	_options.closed.connect(_close_options)
	add_child(_options)
	_options.show_section(section)


func _close_options() -> void:
	if _options == null:
		return
	Settings.save_all(settings)
	_options.queue_free()
	_options = null


func _on_option_changed(kind: String) -> void:
	if _loader == null:
		return
	match kind:
		"mods":
			_rate_all()
			_rebuild_diff_cards()
		"density":
			for i in range(_gens.size()):
				_gens[i] = PatternGen.generate(_loader.difficulties[i], {"density_mul": settings.density_mul})
			_rate_all()
			_rebuild_diff_cards()


## 設定パネルの MOD 欄に出す、選択中の難易度の MOD 適用後 Lv。
func _mod_preview_text() -> String:
	if _diff_sel < 0 or _diff_sel >= _ratings.size():
		return ""
	var r: Dictionary = _ratings[_diff_sel]
	var bm = _loader.difficulties[_diff_sel]
	var s := "選択中の難易度  %s   Lv %.2f" % [bm.version, r.level]
	if absf(r.level - r.base_level) >= 0.005:
		s += "   (MODなし %.2f)" % r.base_level
	return s


# --- 開始 ---

func _start() -> void:
	if _loader == null or _diff_sel < 0:
		return
	if _song_sel >= 0:
		settings.last_song = _songs[_song_sel].path
		settings.last_diff = _loader.difficulties[_diff_sel].version
	Settings.save_all(settings)
	_audio.stop()
	play_requested.emit(_loader, _loader.difficulties[_diff_sel], settings)


func _input(event: InputEvent) -> void:
	if _options != null or not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:
			var d := -1 if event.keycode == KEY_UP else 1
			if _focus_diff:
				_select_diff(_diff_sel + d)
			elif not event.echo:   # 曲の切替は重い(難易度の再計算)ので、押しっぱなしでは進めない
				_select_song(_song_sel + d)
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_RIGHT, KEY_TAB:
			_focus_diff = (event.keycode == KEY_RIGHT) or (event.keycode == KEY_TAB and not _focus_diff)
			_restyle_all()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				_start()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if not event.echo:
				_audio.stop()
				back_requested.emit()
			get_viewport().set_input_as_handled()
		KEY_O:
			if not event.echo:
				open_options(0)
			get_viewport().set_input_as_handled()


# --- 開発用(スクリーンショット) ---

## MOD を指定して付けた状態にする。
func debug_set_mods(ids: Array) -> void:
	settings.mods = ids
	if _loader != null:
		_rate_all()
		_rebuild_diff_cards()
	_refresh_mod_bar()
