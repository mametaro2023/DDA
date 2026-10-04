extends Control
## タイトル画面。「プレイ / マルチプレイ / 遊び方 / 設定 / 終了」の 5 項目。背景は、ランダムに選んだ曲の画像で、その曲を流しておく
## (曲が終わったら、別のランダムな曲へ)。遊び方と設定は、この画面の上に重ねるパネル(曲は流れ続ける)。
## 曲が 1 つもないときは、無音で暗い背景のまま。
##
## 操作: ↑↓ で選び、Enter で決定。マウスでも操作できる。Esc で終了の確認(全画面のときはウィンドウの ✕ が見えないため、「終了」の項目もある)。

signal play_requested
signal multi_requested
signal update_requested
signal settings_requested(section: int)
## 「新しい UI で遊ぼう」から、別の UI セットを試す(main が設定を書き換えて、タイトルを作り直す)
signal ui_try_requested(ui_id: String)

const AttractBackdrop = preload("res://scripts/attract_backdrop.gd")
const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const HowToPanel = preload("res://scripts/ui/howto_panel.gd")
const QuitPanel = preload("res://scripts/ui/quit_panel.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerLogo = preload("res://scripts/ui/lazer/lazer_logo.gd")

const BG_TINT := Color(0.4, 0.4, 0.46)
const ITEMS := [["プレイ", "PLAY"], ["マルチプレイ", "MULTIPLAYER"], ["遊び方", "HOW TO PLAY"], ["設定", "SETTINGS"], ["終了", "QUIT"]]
const MUSIC_DB := -4.0
const ITEM_X := 104.0
const ITEM_Y := 340.0
const ITEM_W := 360.0
const ITEM_H := 54.0
const ITEM_GAP := 10.0
const PITCHES := [1.0, 1.122, 1.26, 1.5, 1.68]   # 項目ごとの選択音の高さ(↑↓ で音階のように聞こえる)

## 画面の種類(main が、いま何の画面かを知るのに使う。ui_set.gd の契約)
var kind := "title"
var settings: Dictionary = {}
var update_info: Dictionary = {}   # 新しいバージョンがあるとき、main が渡す(あとから見つかった場合は show_update)
var _update_btn: Button
var _ver_chip: Control      # 「BETA v…」のチップ(更新の案内は、その右隣に置く)

var _sel := 0
var _cards: Array = []
var _bg_holder: Control
var _bg: TextureRect
var _bg2: TextureRect
var _audio: AudioStreamPlayer
var _last_path := ""
var _overlay: Control        # 開いているパネル(遊び方 / 設定)
var _leaving := false
var _promo: Control           # 「新しい UI で遊ぼう」のカード(右下)
var _ambient: Node2D
var _letters: Array = []     # ロゴの 1 文字ずつ(入場のあと、ゆっくり浮き沈みする)
var _hl: Panel               # 選択中の項目の下で、上下になめらかに動く枠
var _hl_tween: Tween
var _par := Vector2.ZERO     # 背景の視差(マウスの位置に、ゆっくり追従)
var _t := 0.0


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
	_ambient = Ambient.new()
	add_child(_ambient)

	# --- タイトルの文字 ---
	# ロゴは 1 文字ずつ、上から弾んで落ちてくる
	var lx := 104.0
	var word := "Danmaku"
	for i in range(word.length()):
		var ch := word[i]
		var letter := UiStyle.label(ch, 112, UiStyle.ACCENT, true)
		letter.position = Vector2(lx, 104)
		add_child(letter)
		lx += UiStyle.bold().get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 112).x
		letter.set_meta("base_y", 104.0)
		_letters.append(letter)
		UiStyle.spring(letter, "position:y", 104.0 - 70.0, 104.0, 0.7, 0.04 + 0.06 * i)
		UiStyle.tween(letter, "modulate:a", 0.0, 1.0, 0.25, 0.04 + 0.06 * i)
	var ver := UiStyle.chip("BETA   v%s" % _version(), UiStyle.GOLD)
	ver.position = Vector2(112, 266)
	add_child(ver)
	_ver_chip = ver
	UiStyle.pop_in(ver, 0.25, Vector2(-30, 0), 0.6)

	# --- 項目 ---
	_hl = Panel.new()   # 選択中の枠。カードの下で、選ぶたびに上下へ弾みながら動く
	_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hl.add_theme_stylebox_override("panel", _hl_style())
	_hl.size = Vector2(ITEM_W - 10.0, ITEM_H)
	_hl.position = _hl_pos(_sel)
	add_child(_hl)
	var box := VBoxContainer.new()
	box.position = Vector2(ITEM_X, ITEM_Y)
	box.custom_minimum_size = Vector2(ITEM_W, 0)
	box.add_theme_constant_override("separation", int(ITEM_GAP))
	add_child(box)
	for i in range(ITEMS.size()):
		var card := UiStyle.card(ITEM_H, func(): _activate(i))
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
		var holder := UiStyle.wrap_card(card, ITEM_H)
		box.add_child(holder)
		_cards.append(card)
	_restyle()
	for i in range(_cards.size()):
		UiStyle.enter_card(_cards[i], 0.3 + 0.08 * i, -40.0)
	UiStyle.tween(_hl, "modulate:a", 0.0, 1.0, 0.4, 0.45)

	# 背景と曲は、最初の画面を出してから読み込む(読み込みで最初のフレームが遅れないように)
	_audio = AudioStreamPlayer.new()
	Volume.route_music(_audio)   # 音楽バスへ(ホイールなどの「音楽」の音量が効く)
	_audio.volume_db = -40.0
	_audio.finished.connect(_play_random)
	add_child(_audio)
	_play_random.call_deferred()
	if bool(update_info.get("newer", false)):
		show_update(update_info)
	if not bool(settings.get("ui_promo_hidden", false)):
		_build_ui_promo()


## 右下の「新しい UI で遊ぼう」のカード: 新しい UI(lazer 風)の小さなロゴと説明、ピンクの「試してみる」と、✕(二度と出さない)。
## 押すと、UI の見た目を lazer 風にして、タイトルがその見た目で作り直される(設定の「画面」で、いつでも戻せる)。
## 新しい UI の色(ピンク)で描き、クラシックの画面の中で「別の見た目がある」と分かるようにする。点滅などで目を引くことはしない。
func _build_ui_promo() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", LazerStyle.box(Color(0.07, 0.055, 0.1, 0.92), Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.55), 1, 14, 18, 14))
	card.position = Vector2(846, 528)
	card.custom_minimum_size = Vector2(400, 0)
	add_child(card)
	_promo = card
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	var logo := LazerLogo.new(96.0)   # 新しい UI のロゴ(小さく。回る弾も見える)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(logo)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	h.add_child(v)
	var head := HBoxContainer.new()
	var t := LazerStyle.label("新しい UI で遊ぼう", 19, LazerStyle.TEXT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x_btn := Button.new()
	x_btn.text = "✕"
	x_btn.flat = true
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.tooltip_text = "表示しない"
	x_btn.add_theme_color_override("font_color", LazerStyle.TEXT_MUTE)
	x_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	x_btn.set_meta("juice_sound", "back")
	x_btn.pressed.connect(_hide_ui_promo)
	head.add_child(x_btn)
	v.add_child(head)
	var d := LazerStyle.label("lazer 風の、新しい見た目のメニューと画面。設定の「画面」で、いつでも元に戻せます。", 13, LazerStyle.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(250, 0)
	v.add_child(d)
	var go := LazerButton.new("試してみる", LazerStyle.PINK, "play", Color(0.2, 0.04, 0.11))
	go.text = "試してみる"
	go.custom_minimum_size = Vector2(170, 38)
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.font_size = 15
	go.slant = 10.0
	go.pressed.connect(func():
		if _overlay != null or _leaving:
			return
		_leaving = true
		UiSfx.play("confirm")
		var at := go.get_global_rect().get_center()
		UiFx.ring(self, at, LazerStyle.PINK, 16.0, 140.0, 0.5, 2.5)
		ui_try_requested.emit("lazer"))
	v.add_child(go)
	UiStyle.pop_in(card, 0.7, Vector2(30, 0), 0.6)


## ✕: カードを消して、次からは出さない。
func _hide_ui_promo() -> void:
	if _promo == null:
		return
	var st := Settings.load_all()
	st.ui_promo_hidden = true
	Settings.save_all(st)
	settings.ui_promo_hidden = true
	var p := _promo
	_promo = null
	if not UiStyle.animate:
		p.queue_free()
		return
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "modulate:a", 0.0, 0.22)
	tw.tween_property(p, "position:x", p.position.x + 30.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(p.queue_free)


## 新しいバージョンの案内(版の表示の右隣。項目のカードには重ならない)。押すと、アップデートのパネルが開く。
func show_update(info: Dictionary) -> void:
	if _update_btn != null:
		return
	_update_btn = Button.new()
	_update_btn.text = "新しいバージョン v%s があります  ▶" % str(info.get("version", "?"))
	_update_btn.focus_mode = Control.FOCUS_NONE
	_update_btn.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.14), UiStyle.ACCENT, 1, 4, 14, 6))
	_update_btn.add_theme_stylebox_override("hover", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.26), UiStyle.ACCENT, 1, 4, 14, 6))
	_update_btn.add_theme_color_override("font_color", UiStyle.ACCENT)
	_update_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	_update_btn.position = Vector2(112 + _ver_chip.get_combined_minimum_size().x + 14.0, 260)
	_update_btn.pressed.connect(func():
		if _overlay == null and not _leaving:
			update_requested.emit())
	add_child(_update_btn)
	UiStyle.pop_in(_update_btn, 0.35, Vector2(-30, 0), 0.5)


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
	var pick := AttractBackdrop.new().pick(_last_path)   # 選び方は scripts/attract_backdrop.gd(lazer のタイトルと共通)
	if pick.is_empty():
		return
	_last_path = pick.path
	_set_background(pick.tex)
	_audio.stream = pick.stream
	_audio.volume_db = -40.0
	_audio.play(pick.start)
	UiStyle.tween(_audio, "volume_db", -40.0, MUSIC_DB, 1.6)   # 曲は、ふわっと入る


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
	UiSfx.play("select", PITCHES[i])
	_restyle()
	_move_highlight()


## 選択の枠の style(中は水色のうっすらした面、縁と左の太い線は水色)。
func _hl_style() -> StyleBoxFlat:
	var a := UiStyle.ACCENT
	var st := UiStyle.box(Color(a.r, a.g, a.b, 0.13), Color(a.r, a.g, a.b, 0.85), 1, 5, 14, 9)
	st.border_width_left = 3
	return st


func _hl_pos(i: int) -> Vector2:
	return Vector2(ITEM_X + 14.0, ITEM_Y + i * (ITEM_H + ITEM_GAP))


## 枠を、選んだ項目の位置へ動かす(行き過ぎてから戻る。動いている間、少し縦に伸びる)。
func _move_highlight() -> void:
	if _hl_tween != null and _hl_tween.is_valid():
		_hl_tween.kill()
	var to := _hl_pos(_sel)
	if not UiStyle.animate or not is_inside_tree():
		_hl.position = to
		return
	_hl_tween = create_tween().set_parallel(true)
	_hl_tween.tween_property(_hl, "position", to, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var stretch := _hl.create_tween()
	_hl.pivot_offset = _hl.size * 0.5
	stretch.tween_property(_hl, "scale", Vector2(1.0, 1.1), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	stretch.tween_property(_hl, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _restyle() -> void:
	for i in range(_cards.size()):
		var sel := (i == _sel)
		if sel:   # 選択中の面は、動く枠(_hl)が描く。カード自身は透明にして、文字だけ前に出す
			_cards[i].add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 5, 14, 9))
		else:
			UiStyle.style_card(_cards[i], false, true, UiStyle.ACCENT, false)
		UiStyle.shift_card(_cards[i], 14.0 if sel else 0.0)


func _activate(i: int) -> void:
	if _overlay != null or _leaving:
		return
	if i != _sel:
		_sel = i
		_restyle()
		_move_highlight()
	match i:
		0, 1:
			UiSfx.play("confirm")
			_leaving = true
			_fade_music(0.35)
			_burst_at_selected()
			_slide_out()
			if UiStyle.animate:
				await get_tree().create_timer(0.3).timeout
			(play_requested if i == 0 else multi_requested).emit()
		2:
			UiSfx.play("open")
			_open(HowToPanel.new())
		3:
			UiSfx.play("open")
			settings_requested.emit(0)   # 設定パネルは main が持つ(どの画面でも開ける)
		4:
			var q := QuitPanel.new()
			q.confirmed.connect(func(): get_tree().quit())
			_open(q)


## 決めた項目から、水色の輪と粒が広がる。
func _burst_at_selected() -> void:
	var at := _hl_pos(_sel) + Vector2(ITEM_W * 0.5, ITEM_H * 0.5)
	UiFx.ring(self, at, UiStyle.ACCENT, 20.0, 150.0, 0.5, 2.5)
	UiFx.burst(self, at, UiStyle.ACCENT, 14, 240.0, 0.55, 3.0)


## 画面を出るとき、項目が左へ順に流れ出る。
func _slide_out() -> void:
	if not UiStyle.animate:
		return
	for k in range(_cards.size()):
		var c: Control = _cards[k]
		var t := c.create_tween().set_parallel(true)
		t.tween_property(c, "modulate:a", 0.0, 0.2).set_delay(0.03 * k)
		t.tween_method(func(v: float): UiStyle._set_dx(c, v), c.offset_left, -50.0, 0.22).set_delay(0.03 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var th := _hl.create_tween()
	th.tween_property(_hl, "modulate:a", 0.0, 0.2)


## 自動更新のパネルを、いま開いてよいか(別のパネルが開いている・「プレイ」などで画面を離れ始めているときは、だめ)
func can_accept_auto_update() -> bool:
	return _overlay == null and not _leaving


## パネル(遊び方・更新・終了の確認など)を重ねて開く。閉じるのはパネルの closed(ui_set.gd の契約)
func open_panel(panel: Control) -> void:
	_open(panel)


func _open(panel: Control) -> void:
	_overlay = panel
	panel.closed.connect(_close_overlay)
	add_child(panel)
	if panel.has_method("show_section"):
		panel.show_section(0)


func _close_overlay() -> void:
	if _overlay == null:
		return
	_overlay.queue_free()
	_overlay = null


func _process(delta: float) -> void:
	if not UiStyle.animate:
		return
	_t += delta
	_par = UiStyle.parallax(_bg_holder, _ambient, _par, delta, get_viewport())
	# ロゴは、入場が終わったあと 1 文字ずつ位相をずらして、ゆっくり浮き沈みする
	var amp := clampf((_t - 1.0) / 0.8, 0.0, 1.0) * 3.5
	if amp > 0.0:
		for i in range(_letters.size()):
			var l: Label = _letters[i]
			l.position.y = float(l.get_meta("base_y")) + sin(_t * 1.5 + i * 0.8) * amp


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
		KEY_ESCAPE:
			if not event.echo:
				_activate(ITEMS.size() - 1)   # 終了の確認
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _audio != null:
		_audio.stop()
