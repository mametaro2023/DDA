extends CanvasLayer
## リプレイの操作パネル(画面の下に固定。プレイ画面は、そのぶん縮めて見せる)。
## 上: 体力の推移のグラフ(クリック・ドラッグで、その秒へ飛ぶ。Shift を押しながらドラッグで、繰り返し・書き出しの区間を選ぶ)/ 下: 再生・停止・被弾へ・速さ・区間・軌道・動画出力・閉じる。
## H で隠すと、プレイ画面が元の大きさに戻る(画面の下の端へマウスを寄せると、重ねて出る)。
## 状態は GameScreen が持つ(set_state で受け取って見せるだけ)。押されたことを、シグナルで知らせる。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

signal play_pressed
signal restart_pressed
signal seek_requested(t: float)     # 飛び先(ドラッグの間は、間隔を空けて何度も来る)
signal scrub_started                # 体力グラフのドラッグを始めた(再生は止めて、離したら続ける)
signal scrub_ended
signal skip_requested(dt: float)
signal hit_jump_requested(dir: int) # -1 = 前の被弾 / +1 = 次の被弾
signal speed_selected(s: float)
signal trail_mode_pressed
signal trail_len_pressed
signal mark_in_pressed
signal mark_out_pressed
signal range_clear_pressed
signal range_dragged(a: float, b: float)
signal export_requested(opts: Dictionary)   # 空の辞書 = 書き出し中の中止
signal close_pressed

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const DOCK_H := 104.0
const DOCK_SCALE := (720.0 - DOCK_H) / 720.0    # パネルを出しているときの、プレイ画面の縮み
const GRAPH_RECT := Rect2(24.0, 2.0, 1232.0, 66.0)
const PEEK_EDGE := 22.0      # 隠しているとき、画面の下からこれだけ以内にマウスがあれば、重ねて出す
const TRAIL_NAMES := ["軌道: 切", "軌道: 過去", "軌道: 過去+未来"]
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
	["[ ]", "速さを 下げる / 上げる"],
	["I / O / X", "区間の 始点 / 終点 / 解除(区間は繰り返され、動画もその区間だけ書き出す)"],
	["Shift+ドラッグ", "体力グラフで区間を選ぶ"],
	["T / Y", "軌道の 切り替え / 長さ"],
	["H", "操作パネルを 隠す / 出す"],
	["クリック", "プレイ画面のクリックで 再生 / 停止"],
	["Esc", "閉じる"],
]

var _total := 1.0            # 横軸の長さ(秒)
var _panel: Control
var _graph: Control
var _scrub: Control          # グラフの上に重ねる、いまの位置の線・区間・マウスの位置の案内
var _pts := PackedVector2Array()
var _t := 0.0
var _playing := true
var _speed := 1.0
var _drag := false
var _drag_t := 0.0
var _drag_sent_t := -1.0
var _drag_last := 0.0        # 最後に飛んだ時刻(実時間)
var _scrub_gap := 0.05       # ドラッグ中、飛ぶ間隔の下限(秒。飛ぶのに時間がかかる曲では、広げる)
var _range_drag := false
var _range_a := -1.0
var _range_b := -1.0
var _hover_t := -1.0
var pinned_hidden := false   # H キー: パネルを出さない(プレイ画面を、元の大きさで見るとき)
var stage_k := 1.0           # プレイ画面の縮み具合(1 = パネルのぶん縮めた / 0 = 元の大きさ。なめらかに動く)
var _slide := 1.0            # パネルの出ている割合(隠しているときの「重ねて出す」も含む)
var _peek := false
var _font: Font = UiStyle.bold()
var _play_btn: Button
var _time_l: Label
var _trail_btn: Button
var _len_btn: Button
var _speed_btns: Array = []
var _in_btn: Button
var _out_btn: Button
var _clear_btn: Button
var _status_l: Label
var _folder_btn: Button
var _export_btn: Button
var _exp_pop: PanelContainer
var _osd: Label
var _osd_tween: Tween
var _help: PanelContainer
var _warn_l: Label
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
		st.get("breaks", []), _hit_times, GameSim.GAUGE_LOW_THRESHOLD)
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

	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 70.0)
	row.size = Vector2(1232.0, 30.0)
	row.add_theme_constant_override("separation", 4)
	_panel.add_child(row)
	row.add_child(_button("最初へ", "最初へ戻る(Home)", func(): restart_pressed.emit(), 56))
	_play_btn = _button("停止", "再生 / 停止(Space)", func(): play_pressed.emit(), 52)
	row.add_child(_play_btn)
	row.add_child(_button("-5秒", "5 秒戻る(←)", func(): skip_requested.emit(-5.0), 46))
	row.add_child(_button("+5秒", "5 秒進む(→)", func(): skip_requested.emit(5.0), 46))
	row.add_child(_button("←被弾", "前の被弾の少し前へ(PgUp)", func(): hit_jump_requested.emit(-1), 60))
	row.add_child(_button("被弾→", "次の被弾の少し前へ(PgDn)", func(): hit_jump_requested.emit(1), 60))
	row.add_child(_gap(6))
	for s in SPEEDS:
		var b := _button("%sx" % str(s), "再生の速さ([ ] でも変えられます)", func(): speed_selected.emit(s), 42)
		row.add_child(b)
		_speed_btns.append(b)
	row.add_child(_gap(6))
	_in_btn = _button("始点", "ここを区間の始まりにする(I)。区間は繰り返され、動画もその区間だけ書き出せます", func(): mark_in_pressed.emit(), 42)
	row.add_child(_in_btn)
	_out_btn = _button("終点", "ここを区間の終わりにする(O)", func(): mark_out_pressed.emit(), 42)
	row.add_child(_out_btn)
	_clear_btn = _button("解除", "区間をやめる(X)", func(): range_clear_pressed.emit(), 42)
	_clear_btn.visible = false
	row.add_child(_clear_btn)
	row.add_child(_gap(6))
	_time_l = UiStyle.label("0:00.0 / 0:00", 14, UiStyle.TEXT, true)
	_time_l.custom_minimum_size = Vector2(112, 0)
	_time_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_time_l)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	_trail_btn = _button(TRAIL_NAMES[1], "自機の軌道の表示を切り替える(T)", func(): trail_mode_pressed.emit(), 120)
	row.add_child(_trail_btn)
	_len_btn = _button("3秒", "軌道の長さ(Y)", func(): trail_len_pressed.emit(), 44)
	row.add_child(_len_btn)
	row.add_child(_gap(4))
	_export_btn = _button("動画出力", "動画に書き出す(区間があれば、その区間だけ)", _on_export_pressed, 86)
	row.add_child(_export_btn)
	row.add_child(_button("?", "操作の一覧(?)", toggle_help, 30))
	row.add_child(_button("閉じる", "閉じる(Esc)", func(): close_pressed.emit(), 54))

	# 書き出しの状態(パネルの上に、右寄せ)と、出力先を開くボタン
	_status_l = UiStyle.label("", 14, UiStyle.ACCENT, true)
	_status_l.position = Vector2(300.0, -30.0)
	_status_l.size = Vector2(956.0, 24.0)
	_status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status_l.add_theme_constant_override("outline_size", 5)
	_panel.add_child(_status_l)
	_folder_btn = _button("出力先を開く", "書き出した動画のフォルダを開く", _open_export_dir, 100)
	_folder_btn.position = Vector2(1256.0 - 100.0, -64.0)
	_folder_btn.visible = false
	_panel.add_child(_folder_btn)

	_build_export_popup()
	_build_overlays()
	set_state(true, 1.0, 0.0, 1, 3.0, -1.0, -1.0)
	_apply_slide()


func _make_theme() -> Theme:
	var t := UiStyle.make_theme()
	var accent := UiStyle.ACCENT
	t.set_stylebox("normal", "Button", UiStyle.box(Color(1, 1, 1, 0.07), UiStyle.LINE, 1, 4, 7, 3))
	t.set_stylebox("hover", "Button", UiStyle.box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.3), 1, 4, 7, 3))
	t.set_stylebox("pressed", "Button", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.2), accent, 1, 4, 7, 3))
	t.set_stylebox("hover_pressed", "Button", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.26), accent, 1, 4, 7, 3))
	t.set_stylebox("disabled", "Button", UiStyle.box(Color(1, 1, 1, 0.03), UiStyle.LINE, 1, 4, 7, 3))
	return t


func _button(text: String, tip: String, on_press: Callable, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(on_press)
	return b


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## 画面の上に重ねる表示: 操作の反応(OSD)・操作の一覧。
func _build_overlays() -> void:
	_osd = UiStyle.label("", 34, Color.WHITE, true)
	_osd.position = Vector2(240.0, 250.0)
	_osd.size = Vector2(800.0, 56.0)
	_osd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_osd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_osd.add_theme_constant_override("outline_size", 8)
	_osd.modulate.a = 0.0
	add_child(_osd)

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
	_help.position = Vector2(300.0, 70.0)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	_help.visible = false
	add_child(_help)


func _build_export_popup() -> void:
	_exp_pop = PanelContainer.new()
	_exp_pop.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.03, 0.07, 0.97), Color(1, 1, 1, 0.28), 1, 6, 8, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_exp_pop.add_child(v)
	v.add_child(UiStyle.label("動画の大きさ", 12, UiStyle.TEXT_FAINT))
	for c in EXPORT_CHOICES:
		var b := Button.new()
		b.text = c.label
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(210, 28)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_exp_pop.visible = false
			export_requested.emit({"w": c.w, "h": c.h, "fps": c.fps}))
		v.add_child(b)
	_exp_pop.visible = false
	_exp_pop.position = Vector2(1256.0 - 240.0, -150.0)
	_panel.add_child(_exp_pop)


func _on_export_pressed() -> void:
	if _export_btn.text == "書き出し中止":
		export_requested.emit({})
		return
	_exp_pop.visible = not _exp_pop.visible
	_folder_btn.visible = false


## 操作の一覧を、出す・消す。
func toggle_help() -> void:
	_help.visible = not _help.visible


func help_visible() -> bool:
	return _help.visible


## 再生の状態を表示に反映する(毎フレーム呼ばれる。変わったときだけ作り直す)。range_a / range_b: 区間(なければ -1)。
func set_state(playing: bool, speed: float, t: float, trail_mode: int, trail_sec: float, range_a: float, range_b: float) -> void:
	_playing = playing
	_speed = speed
	_t = t
	_range_a = range_a
	_range_b = range_b
	var has_range := range_a >= 0.0 and range_b > range_a
	var exporting := _export_btn.text == "書き出し中止"
	var key := "%s|%s|%d|%s|%s|%s|%s" % [playing, speed, trail_mode, trail_sec, has_range, range_a >= 0.0, exporting]
	if key != _key:   # ボタンの見た目は、変わったときだけ作り直す(毎フレームだと、テーマの変更が続いて重い)
		_key = key
		_play_btn.text = "停止" if playing else "再生"
		for i in range(_speed_btns.size()):
			var on: bool = is_equal_approx(float(SPEEDS[i]), speed)
			_speed_btns[i].add_theme_color_override("font_color", UiStyle.ACCENT if on else UiStyle.TEXT)
			_speed_btns[i].add_theme_color_override("font_hover_color", UiStyle.ACCENT if on else UiStyle.TEXT)
		_trail_btn.text = TRAIL_NAMES[clampi(trail_mode, 0, 2)]
		_len_btn.text = "%d秒" % int(trail_sec)
		_len_btn.disabled = trail_mode == 0
		_clear_btn.visible = range_a >= 0.0
		_in_btn.add_theme_color_override("font_color", UiStyle.ACCENT if range_a >= 0.0 else UiStyle.TEXT)
		_out_btn.add_theme_color_override("font_color", UiStyle.ACCENT if has_range else UiStyle.TEXT)
		if not exporting:
			_export_btn.text = "区間を動画出力" if has_range else "動画出力"
			_export_btn.custom_minimum_size.x = 112.0 if has_range else 86.0
	var tl := "%s / %s" % [_fmt(maxf(t, 0.0), true), _fmt(_total, false)]
	if tl != _time_l.text:
		_time_l.text = tl
	_scrub.queue_redraw()


## 画面の中ほどに、操作の反応を一瞬出す(「2.0x」「+5秒」など)。
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
		_export_btn.custom_minimum_size.x = 100.0
		_folder_btn.visible = false
		_exp_pop.visible = false
	else:
		_export_btn.text = "動画出力"
		_export_btn.custom_minimum_size.x = 86.0
	_key = ""   # 「区間を動画出力」の表示を、次の set_state で整え直す


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
			if event.shift_pressed:   # 区間を選ぶ
				_range_drag = true
				_range_a = t
				_range_b = t
				range_dragged.emit(t, t)
			else:
				_drag = true
				_drag_t = t
				_drag_sent_t = -1.0
				scrub_started.emit()
				_send_scrub()   # 押したところへ、すぐ飛ぶ
		elif _range_drag:
			_range_drag = false
			range_dragged.emit(minf(_range_a, t), maxf(_range_a, t))
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
		elif _range_drag:
			range_dragged.emit(minf(_range_a, _hover_t), maxf(_range_a, _hover_t))
		_scrub.queue_redraw()


func _send_scrub() -> void:
	_drag_sent_t = _drag_t
	_drag_last = Time.get_ticks_msec() / 1000.0
	seek_requested.emit(_drag_t)


func _draw_scrub() -> void:
	var p := _plot()
	# 区間(繰り返し・書き出し)
	if _range_a >= 0.0:
		var xa := _x_at(_range_a)
		if _range_b > _range_a:
			var xb := _x_at(_range_b)
			_scrub.draw_rect(Rect2(xa, p.position.y, xb - xa, p.size.y), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.2))
			_scrub.draw_line(Vector2(xb, p.position.y - 2.0), Vector2(xb, p.end.y), UiStyle.ACCENT, 2.0)
			_scrub.draw_string(_font, Vector2(xb - 12.0, p.end.y + 12.0), "終", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.ACCENT)
		_scrub.draw_line(Vector2(xa, p.position.y - 2.0), Vector2(xa, p.end.y), UiStyle.ACCENT, 2.0)
		_scrub.draw_string(_font, Vector2(xa + 3.0, p.end.y + 12.0), "始", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.ACCENT)
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
		_peek = mp.y >= 720.0 - (DOCK_H if _peek else PEEK_EDGE) or _drag or _range_drag
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


## プレイ画面の縮み(0..1 をなめらかにしたもの)。1 = パネルのぶん縮める。
func stage_ease() -> float:
	return stage_k * stage_k * (3.0 - 2.0 * stage_k)


## 操作の一覧・書き出しの選択が開いていたら閉じる。閉じたものがあれば true(Esc・画面のクリックが、それで済んだか)。
func dismiss_popups() -> bool:
	var any := _help.visible or _exp_pop.visible
	_help.visible = false
	_exp_pop.visible = false
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
