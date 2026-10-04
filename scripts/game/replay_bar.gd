extends Control
## リプレイの操作パネル(画面の下に重ねる)。上: 体力の推移のグラフ(クリック・ドラッグで、その秒へ飛ぶ。いまの位置の線つき)/ 下: 再生・停止・速さ・軌道・動画出力・閉じる。
## 再生中にマウスを動かさないと、なめらかに消える(止めているとき・マウスが上にあるときは出たまま)。
## 状態は GameScreen が持つ(set_state で受け取って見せるだけ)。押されたことを、シグナルで知らせる。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

signal play_pressed
signal restart_pressed
signal seek_requested(t: float)
signal skip_requested(dt: float)
signal speed_selected(s: float)
signal trail_mode_pressed
signal trail_len_pressed
signal export_pressed
signal close_pressed

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const BAR_H := 140.0
const GRAPH_RECT := Rect2(24.0, 6.0, 1232.0, 94.0)
const HIDE_AFTER := 2.5      # 再生中、マウスを動かさないで、これだけたつと消える(秒)
const TRAIL_NAMES := ["軌道: 切", "軌道: 過去", "軌道: 過去+未来"]

var _total := 1.0            # 横軸の長さ(秒)
var _graph: Control
var _scrub: Control          # グラフの上に重ねる、いまの位置の線と、マウスの位置の案内
var _pts := PackedVector2Array()
var _t := 0.0
var _playing := true
var _speed := 1.0
var _drag := false
var _drag_t := 0.0
var _hover_t := -1.0
var _idle := 0.0
var pinned_hidden := false   # H キー: 出さない(自機の周りを、じっくり見るとき)
var _font: Font = UiStyle.bold()
var _play_btn: Button
var _time_l: Label
var _trail_btn: Button
var _len_btn: Button
var _speed_btns: Array = []
var _status_l: Label
var _export_btn: Button
var _key := ""


## data: リプレイの中身(stats の体力の記録を使う)。end_time: 再生の終わりの時刻。
func setup(data: Dictionary, end_time: float) -> void:
	var st: Dictionary = data.stats
	var failed := bool(st.get("failed", false))
	_pts = HpGraph.points_from_log(st.get("hp_log", PackedFloat32Array()), float(st.get("hp_step", GameSim.GAUGE_LOG_STEP)),
		float(st.get("hp_t_end", 0.0)), float(st.get("hp_end", 0.0)))
	_total = maxf(end_time, float(st.get("hp_t_end", 0.0)))
	_total = maxf(_total, 1.0)
	position = Vector2(0.0, 720.0 - BAR_H)
	size = Vector2(1280.0, BAR_H)
	theme = UiStyle.make_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()   # 下へ向かって濃くなる地(アリーナの弾を、グラフが読めるくらいに覆う)
	bg.size = size
	bg.color = Color(0.02, 0.02, 0.05, 0.62)   # 下の自機・弾が、うっすら見えるくらい
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var top := ColorRect.new()
	top.size = Vector2(size.x, 1.0)
	top.color = Color(1, 1, 1, 0.12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_graph = HpGraph.new()
	_graph.position = GRAPH_RECT.position
	_graph.size = GRAPH_RECT.size
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_graph)
	_graph.set_data([{"pts": _pts, "color": UiStyle.ACCENT, "thick": 2.5, "by_hp": true, "end_mark": failed}], 0.0, _total,
		st.get("breaks", []), st.get("hit_log", PackedFloat32Array()), GameSim.GAUGE_LOW_THRESHOLD)
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
	add_child(_scrub)

	var row := HBoxContainer.new()
	row.position = Vector2(24.0, 102.0)
	row.size = Vector2(1232.0, 32.0)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	row.add_child(_button("最初へ", func(): restart_pressed.emit()))
	_play_btn = _button("停止", func(): play_pressed.emit())
	_play_btn.custom_minimum_size = Vector2(64, 30)
	row.add_child(_play_btn)
	row.add_child(_button("-5秒", func(): skip_requested.emit(-5.0)))
	row.add_child(_button("+5秒", func(): skip_requested.emit(5.0)))
	row.add_child(_gap(10))
	for s in SPEEDS:
		var b := _button("%sx" % str(s), func(): speed_selected.emit(s))
		b.custom_minimum_size = Vector2(48, 30)
		row.add_child(b)
		_speed_btns.append(b)
	row.add_child(_gap(12))
	_time_l = UiStyle.label("0:00.0 / 0:00", 15, UiStyle.TEXT, true)
	_time_l.custom_minimum_size = Vector2(130, 0)
	_time_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_time_l)
	_status_l = UiStyle.label("", 14, UiStyle.ACCENT)   # 動画の書き出しの進み具合など
	_status_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_l.clip_text = true
	row.add_child(_status_l)
	_trail_btn = _button(TRAIL_NAMES[1], func(): trail_mode_pressed.emit())
	_trail_btn.custom_minimum_size = Vector2(124, 30)
	row.add_child(_trail_btn)
	_len_btn = _button("3秒", func(): trail_len_pressed.emit())
	_len_btn.custom_minimum_size = Vector2(52, 30)
	row.add_child(_len_btn)
	row.add_child(_gap(8))
	_export_btn = _button("動画出力", func(): export_pressed.emit())
	_export_btn.custom_minimum_size = Vector2(92, 30)
	row.add_child(_export_btn)
	row.add_child(_button("閉じる", func(): close_pressed.emit()))
	set_state(true, 1.0, 0.0, 1, 3.0)


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(on_press)
	return b


func _gap(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## 再生の状態を表示に反映する(毎フレーム呼ばれる。変わったときだけ作り直す)。
func set_state(playing: bool, speed: float, t: float, trail_mode: int, trail_sec: float) -> void:
	_playing = playing
	_speed = speed
	_t = t
	if _drag:
		return
	var key := "%s|%s|%d|%s" % [playing, speed, trail_mode, trail_sec]
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
	var tl := "%s / %s" % [_fmt(maxf(t, 0.0), true), _fmt(_total, false)]
	if tl != _time_l.text:
		_time_l.text = tl
	_scrub.queue_redraw()


## 動画の書き出しの状態(空なら、していない)。している間は、ボタンが「中止」になる。
func set_export_status(text: String) -> void:
	_status_l.text = text
	_export_btn.text = "書き出し中止" if text != "" else "動画出力"


static func _fmt(t: float, tenth: bool) -> String:
	var m := int(t) / 60
	if tenth:
		return "%d:%04.1f" % [m, t - float(m * 60)]
	var whole := ceili(t)   # 全体の長さは、切り上げる(いまの位置より短く見えないように)
	return "%d:%02d" % [whole / 60, whole % 60]


func _plot() -> Rect2:
	return Rect2(HpGraph.LEFT, HpGraph.TOP, maxf(GRAPH_RECT.size.x - HpGraph.LEFT - HpGraph.RIGHT, 1.0), maxf(GRAPH_RECT.size.y - HpGraph.TOP - HpGraph.BOTTOM, 1.0))


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
		if event.pressed:
			_drag = true
			_drag_t = _time_at(event.position.x)
			seek_requested.emit(_drag_t)   # 押したところへ、すぐ飛ぶ(ドラッグの間は、線だけ動かして、離したときに飛ぶ。飛ぶのは少し重いため)
		elif _drag:
			_drag = false
			var t := _time_at(event.position.x)
			if absf(t - _drag_t) > 0.05:
				seek_requested.emit(t)
		_scrub.queue_redraw()
	elif event is InputEventMouseMotion:
		_hover_t = _time_at(event.position.x)
		if _drag:
			_drag_t = _hover_t
		_scrub.queue_redraw()


func _draw_scrub() -> void:
	var p := _plot()
	var t := _drag_t if _drag else _t
	var x := _x_at(maxf(t, 0.0))
	_scrub.draw_line(Vector2(x, p.position.y - 2.0), Vector2(x, p.end.y), Color(1, 1, 1, 0.9), 2.0)
	_scrub.draw_colored_polygon(PackedVector2Array([Vector2(x - 5.0, p.position.y - 4.0), Vector2(x + 5.0, p.position.y - 4.0), Vector2(x, p.position.y + 3.0)]), Color(1, 1, 1, 0.95))
	if _hover_t >= 0.0 and not _drag:   # マウスの位置の案内(時刻と、そのときの体力)
		var hx := _x_at(_hover_t)
		_scrub.draw_line(Vector2(hx, p.position.y), Vector2(hx, p.end.y), Color(1, 1, 1, 0.35), 1.0)
		var hp := _hp_at(_hover_t)
		var txt := "%s   HP %d%%" % [_fmt(_hover_t, true), int(round(hp * 100.0))] if hp >= 0.0 else _fmt(_hover_t, true)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
		var bx := clampf(hx - w * 0.5, p.position.x, p.end.x - w)
		_scrub.draw_rect(Rect2(bx, p.position.y + 2.0, w, 20.0), Color(0.02, 0.02, 0.05, 0.85))
		_scrub.draw_string(_font, Vector2(bx + 6.0, p.position.y + 17.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiStyle.TEXT)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_idle = 0.0
		if not visible and not pinned_hidden:
			visible = true


func _process(delta: float) -> void:
	_idle += delta
	var over := get_global_rect().has_point(get_viewport().get_mouse_position())
	var show := (_drag or over or not _playing or _idle < HIDE_AFTER) and not pinned_hidden
	var target := 1.0 if show else 0.0
	if show and not visible:
		visible = true
	modulate.a = move_toward(modulate.a, target, delta * (6.0 if show else 2.5))   # 出るのは速く、消えるのはゆっくり
	if not show and modulate.a <= 0.01:
		visible = false
