extends CanvasLayer
## アプリ独自のマウスカーソル。OS のカーソルはウィンドウの中では隠し(MOUSE_MODE_HIDDEN)、代わりに小さな輪と点を描く。
## ボタンなど押せるものの上では輪がなめらかに大きくなり、押している間は小さくなる(点滅・揺れはない)。
## プレイ中のマウス操作(MOUSE_MODE_CAPTURED)のときは何も描かない。ウィンドウの外・別のアプリを触っているときも描かない。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")

const R_IDLE := 8.0
const R_HOVER := 13.0
const R_PRESS := 6.0
const TRAIL_LIFE := 0.22

## 開発用: 位置を決め打ちにする(スクリーンショット用)。負なら、本物のマウスの位置
var debug_pos := Vector2(-1, -1)

var _draw: Control
var _pos := Vector2.ZERO
var _r := R_IDLE
var _fill := 0.0
var _inside := false
var _focused := true
var _pressed := false
var _trail: Array = []   # 動いた跡 [位置, 経過秒]。短く薄れる尾になる


func _ready() -> void:
	layer = 127
	_draw = Control.new()
	_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	var w := get_window()
	w.mouse_exited.connect(func(): _inside = false)
	w.mouse_entered.connect(func(): _inside = true)
	get_tree().root.focus_entered.connect(func(): _focused = true)
	get_tree().root.focus_exited.connect(func(): _focused = false)
	_inside = Rect2i(w.position, w.size).has_point(DisplayServer.mouse_get_position())   # 起動したとき、すでにウィンドウの上にあるか
	_hide_os_cursor()


func _hide_os_cursor() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pos = event.position
		_inside = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		if event.pressed and _draw.visible:   # 押したところから、輪と数粒が広がる
			var a := UiStyle.ACCENT
			UiFx.ring(_draw, event.position, Color(a.r, a.g, a.b, 0.9), 6.0, 38.0, 0.42, 2.0)
			UiFx.burst(_draw, event.position, Color(a.r, a.g, a.b, 0.9), 6, 90.0, 0.4, 2.4)


func _process(delta: float) -> void:
	_hide_os_cursor()   # ポーズ・画面の切り替えなどで、OS のカーソルが戻ってきたら、また隠す
	var show := _inside and _focused and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN
	if _draw.visible != show:
		_draw.visible = show
	if not show:
		_trail.clear()
		return
	_pos = get_viewport().get_mouse_position() if debug_pos.x < 0.0 else debug_pos
	_update_trail(delta)
	var target := R_IDLE
	var target_fill := 0.0
	if _pressed:
		target = R_PRESS
		target_fill = 0.35
	elif _over_clickable():
		target = R_HOVER
		target_fill = 0.14
	var k := 1.0 - exp(-18.0 * delta)
	_r = lerpf(_r, target, k)
	_fill = lerpf(_fill, target_fill, k)
	_draw.queue_redraw()


## 尾: 動くたびに位置を足し、古いものから消す(時間で薄れるので、速く動かすほど長く伸びる)。
func _update_trail(delta: float) -> void:
	for p in _trail:
		p[1] += delta
	while not _trail.is_empty() and _trail[0][1] > TRAIL_LIFE:
		_trail.pop_front()
	if not UiStyle.animate:
		return
	if _trail.is_empty() or (_trail[_trail.size() - 1][0] as Vector2).distance_to(_pos) > 1.5:
		_trail.append([_pos, 0.0])


## いま指している場所が、押せるもの(ボタン・スライダー・クリックを受け取るカード)か。
func _over_clickable() -> bool:
	var c: Control = get_viewport().gui_get_hovered_control()
	while c != null:
		if c is BaseButton:
			return not (c as BaseButton).disabled
		if c is Slider or c is LinkButton:
			return true
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and c.gui_input.get_connections().size() > 0:
			return true
		c = c.get_parent() as Control
	return false


func _on_draw() -> void:
	var a := UiStyle.ACCENT
	# 尾(新しいほど太く濃い。先端は輪の中心へつながる)
	for i in range(_trail.size() - 1):
		var k := 1.0 - clampf(_trail[i][1] / TRAIL_LIFE, 0.0, 1.0)
		_draw.draw_line(_trail[i][0], _trail[i + 1][0], Color(a.r, a.g, a.b, 0.5 * k * k), 1.0 + 4.0 * k, true)
	# 輪(暗い縁をつけて、明るい背景でも見えるようにする)
	_draw.draw_arc(_pos, _r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 3.5, true)
	_draw.draw_arc(_pos, _r, 0.0, TAU, 40, Color(a.r, a.g, a.b, 0.95), 1.8, true)
	if _fill > 0.01:
		_draw.draw_circle(_pos, _r - 1.0, Color(a.r, a.g, a.b, _fill))
	# 中心の点(クリックする場所)
	_draw.draw_circle(_pos, 3.4, Color(0, 0, 0, 0.55))
	_draw.draw_circle(_pos, 2.4, Color.WHITE)
