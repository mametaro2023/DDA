extends Node
## ScrollContainer のスクロールをなめらかにする(ホイールで目標の位置を動かし、そこへ少しずつ近づく。プログラムからの移動も同じ)。
## 使い方: SmoothScroll.attach(scroll)。scroll_to_control(card) で、そのカードが見える位置へなめらかに動く。
## 揺れ・点滅はなく、目標へ一方向に近づくだけ(UiStyle.animate が false のときは、すぐ動く)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const STEP := 88.0        # ホイール 1 目盛りの距離(px)
const RATE := 16.0        # 目標へ近づく速さ(大きいほど速い)

var sc: ScrollContainer
var _pos := 0.0           # 今の位置(小数)
var _target := 0.0
var _last := 0           # こちらが最後に設定した scroll_vertical(ちがえば、つまみのドラッグなど外からの移動)


static func attach(scroll: ScrollContainer) -> Node:
	var s: Node = load("res://scripts/ui/smooth_scroll.gd").new()
	s.sc = scroll
	scroll.add_child(s)
	return s


func _ready() -> void:
	set_process(true)
	set_process_input(true)


func _max_scroll() -> float:
	var bar := sc.get_v_scroll_bar()
	return maxf(bar.max_value - bar.page, 0.0)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not sc.is_visible_in_tree() or _max_scroll() <= 0.0:
		return
	if HudOverlay.meter_visible or Input.is_key_pressed(KEY_CTRL):   # 音量メーターが出ているとき・Ctrl は、音量に使う
		return
	if not sc.get_global_rect().has_point(sc.get_global_mouse_position()):
		return
	_sync()
	var d := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var before := _target
	_target = clampf(_target + d * STEP * maxf(event.factor, 1.0), 0.0, _max_scroll())
	if _target != before:
		UiSfx.play("tick", 1.0 + 0.04 * clampf(_target / maxf(_max_scroll(), 1.0), 0.0, 1.0) * 10.0, 0.6)   # 目盛りごとのコッという音。下へ行くほど少し高い
	sc.get_viewport().set_input_as_handled()


## 外からスクロール位置が変えられていたら(つまみのドラッグなど)、そこを今の位置にする。
func _sync() -> void:
	if sc.scroll_vertical != _last:
		_pos = float(sc.scroll_vertical)
		_target = _pos
		_last = sc.scroll_vertical


## control(スクロールの中のカード)が見える位置へ、なめらかに動く。
func scroll_to_control(control: Control, margin := 8.0) -> void:
	if control == null or not is_instance_valid(control) or sc.get_child_count() == 0:
		return
	_sync()
	var content: Control = null
	for c in sc.get_children():
		if c is Control and c != sc.get_v_scroll_bar() and c != sc.get_h_scroll_bar():
			content = c
			break
	if content == null:
		return
	var top := control.get_global_rect().position.y - content.get_global_rect().position.y
	var bottom := top + control.size.y
	var page := sc.size.y
	if top - margin < _target:
		_target = top - margin
	elif bottom + margin > _target + page:
		_target = bottom + margin - page
	_target = clampf(_target, 0.0, _max_scroll())
	if not UiStyle.animate:
		_pos = _target
		_apply()


func _process(delta: float) -> void:
	_sync()
	if absf(_target - _pos) < 0.3:
		if _pos != _target:
			_pos = _target
			_apply()
		return
	_pos = lerpf(_pos, _target, 1.0 - exp(-RATE * delta))
	_apply()


func _apply() -> void:
	sc.scroll_vertical = int(round(_pos))
	_last = sc.scroll_vertical
