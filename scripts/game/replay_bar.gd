extends CanvasLayer
## リプレイの操作パネル(画面の下に固定。プレイ画面は、そのぶん縮めて見せる)。
## 上: 体力の推移のグラフ(クリック・ドラッグで、その秒へ飛ぶ)。
## 下: 左に「再生 / 停止」・±5 秒・ジャンプ・時刻、右に速さのスライダー(0.25〜8 倍の好きな値)・軌道の表示・動画出力・操作の一覧・閉じる。
## 数の多い選択肢(ジャンプ先・動画の大きさ)は、押すと上に開く小さなメニューにまとめて、ボタンを増やさない。
## H で隠すと、プレイ画面が元の大きさに戻る(画面の下の端へマウスを寄せると、重ねて出る)。
## 状態は GameScreen が持つ(set_state で受け取って見せるだけ)。押されたことを、シグナルで知らせる。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

signal play_pressed
signal restart_pressed
signal end_pressed
signal seek_requested(t: float)     # 飛び先(ドラッグの間は、間隔を空けて何度も来る)
signal scrub_started                # 体力グラフのドラッグを始めた(再生は止めて、離したら続ける)
signal scrub_ended
signal skip_requested(dt: float)
signal hit_jump_requested(dir: int) # -1 = 前の被弾 / +1 = 次の被弾
signal speed_selected(s: float)     # スライダー(動かしているあいだ、何度も来る)
signal trail_toggled                # 軌道の 表示 / 非表示
signal export_requested(opts: Dictionary)   # 空の辞書 = 書き出し中の中止
signal close_pressed

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]   # [ ] キーで移る、区切りのよい速さ(スライダーは、この間の好きな値)
const SPEED_MIN := 0.25
const SPEED_MAX := 8.0
const DOCK_H := 104.0
const DOCK_SCALE := (720.0 - DOCK_H) / 720.0    # パネルを出しているときの、プレイ画面の縮み
const GRAPH_RECT := Rect2(24.0, 2.0, 1232.0, 66.0)
const PEEK_EDGE := 22.0      # 隠しているとき、画面の下からこれだけ以内にマウスがあれば、重ねて出す
const EXPORT_CHOICES := [
	{"label": "1280×720  60fps", "w": 1280, "h": 720, "fps": 60},
	{"label": "1920×1080  60fps(大きい)", "w": 1920, "h": 1080, "fps": 60},
	{"label": "1280×720  30fps(軽い)", "w": 1280, "h": 720, "fps": 30},
]
const HELP_LINES := [
	["Space", "再生 / 停止"],
	["← →", "5 秒 戻る / 進む(Shift: 1 秒 / Ctrl: 15 秒)"],
	["Home / End", "最初 / 最後へ"],
	[", .", "1 コマ戻る / 進む"],
	["PgUp / PgDn", "前の被弾 / 次の被弾の少し前へ"],
	["[ ]", "速さを 下げる / 上げる(0.25・0.5・1・2・4・8 倍)"],
	["T", "軌道(過去 3 秒)の 表示 / 非表示"],
	["H", "操作パネルを 隠す / 出す"],
	["クリック", "プレイ画面のクリックで 再生 / 停止"],
	["Esc", "閉じる"],
]

var _total := 1.0            # 横軸の長さ(秒)
var _panel: Control
var _graph: Control
var _scrub: Control          # グラフの上に重ねる、いまの位置の線とマウスの位置の案内
var _pts := PackedVector2Array()
var _t := 0.0
var _playing := true
var _speed := 1.0
var _drag := false
var _drag_t := 0.0
var _drag_sent_t := -1.0
var _drag_last := 0.0        # 最後に飛んだ時刻(実時間)
var _scrub_gap := 0.05       # ドラッグ中、飛ぶ間隔の下限(秒)
var _hover_t := -1.0
var pinned_hidden := false   # H キー: パネルを出さない(プレイ画面を、元の大きさで見るとき)
var stage_k := 1.0           # プレイ画面の縮み具合(1 = パネルのぶん縮めた / 0 = 元の大きさ。なめらかに動く)
var _slide := 1.0            # パネルの出ている割合(隠しているときの「重ねて出す」も含む)
var _peek := false
var _font: Font = UiStyle.bold()
var _play_btn: Button
var _time_l: Label
var _speed_slider: HSlider
var _speed_btn: Button       # 速さの数字(押すと 1 倍へ戻る)
var _trail_btn: Button
var _jump_btn: Button
var _status_l: Label
var _folder_btn: Button
var _export_btn: Button
var _menu: PanelContainer    # 選択肢のメニュー(1 つを使い回す)
var _menu_box: VBoxContainer
var _menu_owner: Button
var _osd: Label
var _osd_tween: Tween
var _help: PanelContainer
var _warn_l: Label
var _load_box: PanelContainer   # 「読み込み中」(飛ぶのに時間がかかるとき)
var _load_l: Label
var _load_fill: ColorRect
var _key := ""
var _export_dir := ""        # 書き出した動画の入っているフォルダ(あれば「出力先を開く」)
var _hit_times := PackedFloat32Array()


## data: リプレイの中身(stats の体力の記録を使う)。end_time: 再生の終わりの時刻。
func setup(data: Dictionary, end_time: float) -> void:
	layer = 50   # 画面(0)より上、設定・選択のパネル(80)より下
	var st: Dictionary = data.stats
	var failed := bool(st.get("failed", false))
	_hit_times = st.get("hit_log", PackedFloat32Array())
	_pts = HpGraph.points_from_log(st.get("hp_log", PackedFloat32Array()), float(st.get("hp_step", GameSim.GAUGE_LOG_STEP)),
		float(st.get("hp_t_end", 0.0)), float(st.get("hp_end", 0.0)))
	_total = maxf(maxf(end_time, float(st.get("hp_t_end", 0.0))), 1.0)

	_panel = Control.new()
	_panel.position = Vector2(0.0, 720.0)
	_panel.size = Vector2(1280.0, DOCK_H)
	_panel.theme = _make_theme()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var bg := ColorRect.new()
	bg.size = _panel.size
	bg.color = Color(0.02, 0.02, 0.05, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)
	var top := ColorRect.new()
	top.size = Vector2(1280.0, 1.0)
	top.color = Color(1, 1, 1, 0.14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(top)

	_graph = HpGraph.new()
	_graph.position = GRAPH_RECT.position
	_graph.size = GRAPH_RECT.size
	_graph.left = 40.0
	_graph.right = 10.0
	_graph.top = 6.0
	_graph.bottom = 16.0
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_graph)
	_graph.set_data([{"pts": _pts, "color": UiStyle.ACCENT, "thick": 2.0, "by_hp": true, "end_mark": failed}], 0.0, _total,
		st.get("breaks", []), _hit_times, float(st.get("low_line", GameSim.GAUGE_LOW_THRESHOLD)))
	_graph.reveal = 1.0

	_scrub = Control.new()
	_scrub.position = GRAPH_RECT.position
	_scrub.size = GRAPH_RECT.size
	_scrub.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrub.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_scrub.draw.connect(_draw_scrub)
	_scrub.gui_input.connect(_scrub_input)
	_scrub.mouse_exited.connect(func():
		_hover_t = -1.0
		_scrub.queue_redraw())
	_panel.add_child(_scrub)

	# 下の段: 左 = 動かす(再生・±5 秒・ジャンプ・時刻)/ 右 = 見せ方(速さ・軌道)と、書き出し・一覧・閉じる
	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 70.0)
	row.size = Vector2(1232.0, 32.0)
	row.add_theme_constant_override("separation", 6)
	_panel.add_child(row)
	_play_btn = _button("停止", "再生 / 停止(Space)", func(): play_pressed.emit(), 84)
	UiStyle.style_primary(_play_btn, false, 12, 3)
	_play_btn.add_theme_font_size_override("font_size", 15)
	row.add_child(_play_btn)
	row.add_child(_button("-5秒", "5 秒戻る(←)", func(): skip_requested.emit(-5.0), 56))
	row.add_child(_button("+5秒", "5 秒進む(→)", func(): skip_requested.emit(5.0), 56))
	_jump_btn = _button("ジャンプ", "最初・最後・被弾の前後へ飛ぶ", func(): _open_menu(_jump_btn, _jump_items()), 88)
	row.add_child(_jump_btn)
	row.add_child(_gap(8))
	_time_l = UiStyle.label("0:00.0 / 0:00", 15, UiStyle.TEXT, true)
	_time_l.custom_minimum_size = Vector2(120, 0)
	_time_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_time_l)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	# 速さ: スライダー(左右の端が 0.25 倍・8 倍。目盛りは対数なので、1 倍が真ん中より少し左)と、いまの値(押すと 1 倍へ)
	var sl := UiStyle.label("速さ", 13, UiStyle.TEXT_DIM)
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sl)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = log(SPEED_MIN) / log(2.0)
	_speed_slider.max_value = log(SPEED_MAX) / log(2.0)
	_speed_slider.step = 0.01
	_speed_slider.value = 0.0
	_speed_slider.custom_minimum_size = Vector2(170, 32)
	_speed_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_speed_slider.focus_mode = Control.FOCUS_NONE
	_speed_slider.tooltip_text = "再生の速さ(0.25〜8 倍)。[ ] キーで、区切りのよい速さへ"
	_speed_slider.value_changed.connect(_on_speed_slider)
	row.add_child(_speed_slider)
	_speed_btn = _button("1.00x", "押すと、ふつうの速さ(1 倍)に戻す", func(): speed_selected.emit(1.0), 64)
	row.add_child(_speed_btn)
	row.add_child(_gap(6))
	_trail_btn = _button("軌道: 表示", "自機の軌道(過去 3 秒)の 表示 / 非表示(T)", func(): trail_toggled.emit(), 104)
	row.add_child(_trail_btn)
	row.add_child(_gap(6))
	_export_btn = _button("動画出力", "動画に書き出す(最後にリザルト画面つき)", _on_export_pressed, 92)
	row.add_child(_export_btn)
	row.add_child(_button("?", "操作の一覧(?)", toggle_help, 32))
	row.add_child(_button("閉じる", "閉じる(Esc)", func(): close_pressed.emit(), 64))

	# 書き出しの状態(パネルの上に、右寄せ)と、出力先を開くボタン
	_status_l = UiStyle.label("", 14, UiStyle.ACCENT, true)
	_status_l.position = Vector2(300.0, -30.0)
	_status_l.size = Vector2(956.0, 24.0)
	_status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status_l.add_theme_constant_override("outline_size", 5)
	_panel.add_child(_status_l)
	_folder_btn = _button("出力先を開く", "書き出した動画のフォルダを開く", _open_export_dir, 110)
	_folder_btn.position = Vector2(1256.0 - 110.0, -64.0)
	_folder_btn.visible = false
	_panel.add_child(_folder_btn)

	_build_menu()
	_build_overlays()
	set_state(true, 1.0, 0.0, true)
	_apply_slide()


func _make_theme() -> Theme:
	var t := UiStyle.make_theme()
	var accent := UiStyle.ACCENT
	t.set_stylebox("normal", "Button", UiStyle.box(Color(1, 1, 1, 0.07), UiStyle.LINE, 1, 4, 8, 3))
	t.set_stylebox("hover", "Button", UiStyle.box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.3), 1, 4, 8, 3))
	t.set_stylebox("pressed", "Button", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.2), accent, 1, 4, 8, 3))
	t.set_stylebox("hover_pressed", "Button", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.26), accent, 1, 4, 8, 3))
	t.set_stylebox("disabled", "Button", UiStyle.box(Color(1, 1, 1, 0.03), UiStyle.LINE, 1, 4, 8, 3))
	return t


func _button(text: String, tip: String, on_press: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 32)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(on_press)
	return b


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## スライダーの位置(2 を底とする対数)から速さへ。区切りのよい速さの近くでは、そこに吸い付く(1 倍に戻しやすいように)。
func _on_speed_slider(v: float) -> void:
	var s := pow(2.0, v)
	for p in SPEEDS:
		if absf(v - log(float(p)) / log(2.0)) < 0.06:
			s = float(p)
	speed_selected.emit(s)


## 画面の上に重ねる表示: 操作の反応(OSD)・読み込み中・操作の一覧。
func _build_overlays() -> void:
	_osd = UiStyle.label("", 34, Color.WHITE, true)
	_osd.position = Vector2(240.0, 250.0)
	_osd.size = Vector2(800.0, 56.0)
	_osd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_osd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_osd.add_theme_constant_override("outline_size", 8)
	_osd.modulate.a = 0.0
	add_child(_osd)

	_load_box = PanelContainer.new()
	_load_box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.02, 0.02, 0.06, 0.82), Color(1, 1, 1, 0.22), 1, 10, 22, 12))
	_load_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	_load_box.add_child(lv)
	_load_l = UiStyle.label("読み込み中…", 20, Color.WHITE, true)
	_load_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_l.custom_minimum_size = Vector2(220, 0)
	lv.add_child(_load_l)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.16)
	track.custom_minimum_size = Vector2(220, 4)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(track)
	_load_fill = ColorRect.new()
	_load_fill.color = UiStyle.ACCENT
	_load_fill.size = Vector2(0, 4)
	_load_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_load_fill)
	_load_box.position = Vector2(640.0 - 132.0, 300.0)
	_load_box.visible = false
	add_child(_load_box)

	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", UiStyle.box(Color(0.02, 0.02, 0.06, 0.94), Color(1, 1, 1, 0.25), 1, 8, 22, 16))
	_help.theme = _panel.theme
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_help.add_child(v)
	v.add_child(UiStyle.label("リプレイの操作", 16, UiStyle.ACCENT, true))
	for h in HELP_LINES:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		var k := UiStyle.label(h[0], 13, Color.WHITE, true)
		k.custom_minimum_size = Vector2(112, 0)
		r.add_child(k)
		r.add_child(UiStyle.label(h[1], 13, UiStyle.TEXT_DIM))
		v.add_child(r)
	_help.position = Vector2(300.0, 90.0)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	_help.visible = false
	add_child(_help)


## 「読み込み中」を出す・消す(飛ぶのに時間がかかっているあいだ)。frac: 進み具合 0..1。
func set_loading(on: bool, frac: float) -> void:
	if _load_box == null:
		return
	_load_box.visible = on
	if on:
		_load_l.text = "読み込み中…  %d%%" % int(round(frac * 100.0))
		_load_fill.size.x = 220.0 * clampf(frac, 0.0, 1.0)


# --- 選択肢のメニュー ---

func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.03, 0.07, 0.98), Color(1, 1, 1, 0.28), 1, 6, 6, 6))
	_menu.theme = _panel.theme
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 2)
	_menu.add_child(_menu_box)
	_menu.visible = false
	add_child(_menu)


## 項目の作り方: {label, cb(押したときの処理), on(いま選んでいる)、off(押せない)} / {head: "見出し"} / {sep: true}
func _open_menu(owner_btn: Button, items: Array) -> void:
	if _menu.visible and _menu_owner == owner_btn:   # 開いているボタンをもう一度押したら、閉じる
		_close_menu()
		return
	_close_menu()
	_help.visible = false
	for c in _menu_box.get_children():
		_menu_box.remove_child(c)
		c.queue_free()
	for it in items:
		if it.has("sep"):
			var line := ColorRect.new()
			line.color = Color(1, 1, 1, 0.14)
			line.custom_minimum_size = Vector2(0, 1)
			_menu_box.add_child(line)
		elif it.has("head"):
			var h := UiStyle.label(str(it.head), 12, UiStyle.TEXT_FAINT)
			h.custom_minimum_size = Vector2(210, 0)
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_menu_box.add_child(h)
		else:
			var b := Button.new()
			b.text = str(it.label)
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(210, 30)
			b.add_theme_font_size_override("font_size", 14)
			b.disabled = bool(it.get("off", false))
			if bool(it.get("on", false)):
				b.add_theme_color_override("font_color", UiStyle.ACCENT)
				b.add_theme_color_override("font_hover_color", UiStyle.ACCENT)
				b.add_theme_font_override("font", UiStyle.bold())
			var cb: Callable = it.cb
			b.pressed.connect(func():
				_close_menu()
				cb.call())
			_menu_box.add_child(b)
	_menu.reset_size()
	_menu_owner = owner_btn
	_menu.visible = true
	await get_tree().process_frame   # 大きさが決まってから、ボタンの真上へ置く
	if _menu.visible and _menu_owner == owner_btn:
		var at := owner_btn.get_global_rect()
		var x := at.position.x if at.position.x + _menu.size.x <= 1272.0 else at.end.x - _menu.size.x   # はみ出すときは、右端をそろえる
		_menu.position = Vector2(maxf(x, 8.0), at.position.y - _menu.size.y - 6.0)


func _close_menu() -> void:
	_menu.visible = false
	_menu_owner = null


func _jump_items() -> Array:
	return [
		{"label": "最初へ  (Home)", "cb": func(): restart_pressed.emit()},
		{"label": "前の被弾  (PgUp)", "cb": func(): hit_jump_requested.emit(-1)},
		{"label": "次の被弾  (PgDn)", "cb": func(): hit_jump_requested.emit(1)},
		{"label": "最後へ  (End)", "cb": func(): end_pressed.emit()},
		{"sep": true},
		{"head": "被弾の 1.5 秒前へ飛びます。グラフの赤い線が被弾した時刻です"},
	]


func _on_export_pressed() -> void:
	if _export_btn.text == "書き出し中止":
		export_requested.emit({})
		return
	_folder_btn.visible = false
	var items: Array = [{"head": "動画に書き出す大きさ(最後にリザルト画面がつきます)"}]
	for c in EXPORT_CHOICES:
		var cc: Dictionary = c
		items.append({"label": cc.label, "cb": func(): export_requested.emit({"w": cc.w, "h": cc.h, "fps": cc.fps})})
	_open_menu(_export_btn, items)


## 操作の一覧を、出す・消す。
func toggle_help() -> void:
	_close_menu()
	_help.visible = not _help.visible


func help_visible() -> bool:
	return _help.visible


## 再生の状態を表示に反映する(毎フレーム呼ばれる。変わったときだけ作り直す)。trail_on: 軌道を出しているか。
func set_state(playing: bool, speed: float, t: float, trail_on: bool) -> void:
	_playing = playing
	_speed = speed
	_t = t
	var key := "%s|%s|%s" % [playing, speed, trail_on]
	if key != _key:   # ボタンの見た目は、変わったときだけ作り直す(毎フレームだと、テーマの変更が続いて重い)
		_key = key
		_play_btn.text = "停止" if playing else "再生"
		_speed_btn.text = "%.2fx" % speed
		_speed_btn.add_theme_color_override("font_color", UiStyle.ACCENT if not is_equal_approx(speed, 1.0) else UiStyle.TEXT)
		_speed_slider.set_value_no_signal(log(speed) / log(2.0))
		_trail_btn.text = "軌道: 表示" if trail_on else "軌道: 非表示"
		_trail_btn.add_theme_color_override("font_color", UiStyle.TEXT if trail_on else UiStyle.TEXT_FAINT)
	var tl := "%s / %s" % [_fmt(maxf(t, 0.0), true), _fmt(_total, false)]
	if tl != _time_l.text:
		_time_l.text = tl
	_scrub.queue_redraw()


## 画面の中ほどに、操作の反応を一瞬出す(「2.00x」「+5秒」など)。
func osd(text: String) -> void:
	if _osd == null:
		return
	_osd.text = text
	if _osd_tween != null:
		_osd_tween.kill()
	_osd.modulate.a = 1.0
	_osd_tween = create_tween()
	_osd_tween.tween_interval(0.35)
	_osd_tween.tween_property(_osd, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_QUAD)


## 動画の書き出しの状態(空なら、していない)。している間は、ボタンが「中止」になる。
func set_export_status(text: String) -> void:
	_status_l.text = text
	if text != "":
		_export_btn.text = "書き出し中止"
		_export_btn.custom_minimum_size.x = 112.0
		_folder_btn.visible = false
		_close_menu()
	else:
		_export_btn.text = "動画出力"
		_export_btn.custom_minimum_size.x = 92.0


## 書き出しが終わった(path: できたファイル)。結果の文を出しておき、「出力先を開く」を出す。
func set_export_done(path: String, text: String) -> void:
	set_export_status("")
	_export_dir = path.get_base_dir()
	_status_l.text = text
	_folder_btn.visible = _export_dir != ""


func _open_export_dir() -> void:
	if _export_dir != "":
		OS.shell_show_in_file_manager(_export_dir)


## 飛ぶのにかかった時間(ミリ秒)。ドラッグ中に飛ぶ間隔を、これに合わせる(重い曲で、操作が詰まらないように)。
func set_seek_cost(ms: float) -> void:
	_scrub_gap = clampf(ms * 0.0035, 0.03, 0.6)


static func _fmt(t: float, tenth: bool) -> String:
	var m := int(t) / 60
	if tenth:
		return "%d:%04.1f" % [m, t - float(m * 60)]
	var whole := ceili(t)   # 全体の長さは、切り上げる(いまの位置より短く見えないように)
	return "%d:%02d" % [whole / 60, whole % 60]


func _plot() -> Rect2:
	var g: HpGraph = _graph
	return Rect2(g.left, g.top, maxf(GRAPH_RECT.size.x - g.left - g.right, 1.0), maxf(GRAPH_RECT.size.y - g.top - g.bottom, 1.0))


func _time_at(x: float) -> float:
	var p := _plot()
	return clampf((x - p.position.x) / p.size.x, 0.0, 1.0) * _total


func _x_at(t: float) -> float:
	var p := _plot()
	return p.position.x + p.size.x * clampf(t / _total, 0.0, 1.0)


## その時刻の体力(0..1。記録の点列から補間)。記録がないところ(ゲームオーバーのあと)は -1。
func _hp_at(t: float) -> float:
	if _pts.size() < 2 or t > _pts[_pts.size() - 1].x + 0.01:
		return -1.0
	for i in range(1, _pts.size()):
		if _pts[i].x >= t:
			var a := _pts[i - 1]
			var b := _pts[i]
			return lerpf(a.y, b.y, clampf((t - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0))
	return _pts[_pts.size() - 1].y


func _scrub_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var t := _time_at(event.position.x)
		if event.pressed:
			_close_menu()
			_drag = true
			_drag_t = t
			_drag_sent_t = -1.0
			scrub_started.emit()
			_send_scrub()   # 押したところへ、すぐ飛ぶ
		elif _drag:
			_drag = false
			_drag_t = t
			if absf(t - _drag_sent_t) > 0.01:
				_send_scrub()
			scrub_ended.emit()
		_scrub.queue_redraw()
	elif event is InputEventMouseMotion:
		_hover_t = _time_at(event.position.x)
		if _drag:
			_drag_t = _hover_t
		_scrub.queue_redraw()


func _send_scrub() -> void:
	_drag_sent_t = _drag_t
	_drag_last = Time.get_ticks_msec() / 1000.0
	seek_requested.emit(_drag_t)


func _draw_scrub() -> void:
	var p := _plot()
	var t := _drag_t if _drag else _t
	var x := _x_at(maxf(t, 0.0))
	_scrub.draw_line(Vector2(x, p.position.y - 2.0), Vector2(x, p.end.y), Color(1, 1, 1, 0.9), 2.0)
	_scrub.draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, p.position.y - 5.0), Vector2(x + 5.0, p.position.y - 5.0), Vector2(x, p.position.y + 2.0)]), Color(1, 1, 1, 0.95))
	if _hover_t >= 0.0 and not _drag:   # マウスの位置の案内(時刻と、そのときの体力)
		var hx := _x_at(_hover_t)
		_scrub.draw_line(Vector2(hx, p.position.y), Vector2(hx, p.end.y), Color(1, 1, 1, 0.35), 1.0)
		var hp := _hp_at(_hover_t)
		var txt := "%s   HP %d%%" % [_fmt(_hover_t, true), int(round(hp * 100.0))] if hp >= 0.0 else _fmt(_hover_t, true)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
		var bx := clampf(hx - w * 0.5, p.position.x, p.end.x - w)
		_scrub.draw_rect(Rect2(bx, p.position.y + 2.0, w, 20.0), Color(0.02, 0.02, 0.05, 0.88))
		_scrub.draw_string(_font, Vector2(bx + 6.0, p.position.y + 17.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.TEXT)


func _process(delta: float) -> void:
	if _panel == null:
		return
	if _drag and _drag_sent_t != _drag_t and Time.get_ticks_msec() / 1000.0 - _drag_last >= _scrub_gap:
		_send_scrub()
	var mp := get_viewport().get_mouse_position()
	if pinned_hidden:   # 隠しているとき: 画面の下の端へ寄せたら重ねて出す。パネルの上にいるあいだは出したまま
		_peek = mp.y >= 720.0 - (DOCK_H if _peek else PEEK_EDGE) or _drag or _menu.visible
	else:
		_peek = false
	stage_k = move_toward(stage_k, 0.0 if pinned_hidden else 1.0, delta * 4.5)
	var slide_target := 1.0 if (not pinned_hidden or _peek) else 0.0
	_slide = move_toward(_slide, slide_target, delta * (7.0 if slide_target > _slide else 5.0))
	_apply_slide()


func _apply_slide() -> void:
	var e := _slide * _slide * (3.0 - 2.0 * _slide)
	_panel.position.y = 720.0 - DOCK_H * e
	_panel.visible = _slide > 0.001
	if not _panel.visible and _menu.visible:
		_close_menu()


## プレイ画面の縮み(0..1 をなめらかにしたもの)。1 = パネルのぶん縮める。
func stage_ease() -> float:
	return stage_k * stage_k * (3.0 - 2.0 * stage_k)


## 操作の一覧・選択肢のメニューが開いていたら閉じる。閉じたものがあれば true(Esc・画面のクリックが、それで済んだか)。
func dismiss_popups() -> bool:
	var any := _help.visible or _menu.visible
	_help.visible = false
	_close_menu()
	return any


## 注意を出す(再現がずれたときなど。空なら消す)。
func set_warning(text: String) -> void:
	if _warn_l == null:
		_warn_l = UiStyle.label("", 13, Color(1.0, 0.72, 0.4), true)
		_warn_l.position = Vector2(180.0, 52.0)
		_warn_l.size = Vector2(920.0, 40.0)
		_warn_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_warn_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_warn_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_warn_l.add_theme_constant_override("outline_size", 5)
		add_child(_warn_l)
	_warn_l.text = text
