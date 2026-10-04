extends Node
## ScrollContainer のスクロールをなめらかにする(ホイールで目標の位置を動かし、そこへ少しずつ近づく。プログラムからの移動も同じ)。
## 使い方: SmoothScroll.attach(scroll)。scroll_to_control(card) で、そのカードが見える位置へなめらかに動く。
## attach(scroll, true) なら、一覧をドラッグしてもスクロールできる: 左ドラッグ = つかんだ分だけ動く(離すと少し滑る)、
## 右ドラッグ = 同じ向きに速く動く(一覧の高さぶんドラッグすると、だいたい全体を移動できる)。
## 揺れ・点滅はなく、目標へ一方向に近づくだけ(UiStyle.animate が false のときは、すぐ動く)。ホイール・ドラッグはすぐ反応し、
## プログラムからの移動(scroll_to / scroll_to_control)は、止まった状態から加速して止まる(急に跳ばない)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HudOverlay = preload("res://scripts/ui/hud_overlay.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const STEP := 88.0        # ホイール 1 目盛りの距離(px)
const RATE := 16.0        # 目標へ近づく速さ(大きいほど速い)
const DRAG_START := 6.0   # これだけ動かしたら、クリックではなくドラッグ(px)
const FAST_MIN := 4.0     # 右ドラッグの倍率の下限
const FLING := 0.16       # 左ドラッグを離したとき、離す直前の速さ × この秒数だけ滑る
const SPRING_W := 13.0    # プログラムからの移動(選んだ行へ寄せる など)の、ばねの強さ。止まった状態から加速して、行き過ぎずに止まる(約 0.35 秒)
const MAX_DT := 1.0 / 30.0   # 1 フレームで進める時間の上限(重いフレームのあとでも、一度に大きく跳ばない)

var sc: ScrollContainer
## false を返すとき、ホイールを受け付けない(上にパネルが重なっているときなど)。未設定なら常に受け付ける
var active: Callable = Callable()
var _pos := 0.0           # 今の位置(小数)
var _target := 0.0
var _last := 0           # こちらが最後に設定した scroll_vertical(ちがえば、つまみのドラッグなど外からの移動)
var _drag := false        # ドラッグでスクロールできる一覧か
var _drag_btn := 0        # 押しているボタン(0 = ドラッグしていない)
var _drag_y0 := 0.0       # 押したときのマウスの y
var _drag_from := 0.0     # 押したときのスクロール位置
var _drag_moved := false
var _drag_hist: Array = []   # 左ドラッグの最近の位置 [ミリ秒, スクロール位置](離したときの勢いを、直前 0.1 秒の動きから求める)
var _tick_i := 0          # 目盛りの音を鳴らした位置(STEP ごと)
var _vel := 0.0           # ばねで動いているときの速さ(px/秒)
var _spring := false      # true: プログラムからの移動(ばね)。false: ホイール・ドラッグ(すぐ反応して、減速しながら近づく)


static func attach(scroll: ScrollContainer, drag := false) -> Node:
	var s: Node = load("res://scripts/ui/smooth_scroll.gd").new()
	s.sc = scroll
	s._drag = drag
	if drag:
		scroll.set_meta("drag_scroll", true)   # 中のカードは、離したときに選ぶ(ui_style.gd の card)
	scroll.add_child(s)
	return s


func _ready() -> void:
	set_process(true)
	set_process_input(true)


func _max_scroll() -> float:
	var bar := sc.get_v_scroll_bar()
	return maxf(bar.max_value - bar.page, 0.0)


func _input(event: InputEvent) -> void:
	if _drag and _drag_input(event):
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not sc.is_visible_in_tree() or _max_scroll() <= 0.0:
		return
	if active.is_valid() and not active.call():
		return
	if HudOverlay.meter_visible or Input.is_key_pressed(KEY_CTRL):   # 音量メーターが出ているとき・Ctrl は、音量に使う
		return
	if not sc.get_global_rect().has_point(sc.get_global_mouse_position()):
		return
	_sync()
	_spring = false
	_vel = 0.0
	var d := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	var before := _target
	_target = clampf(_target + d * STEP * maxf(event.factor, 1.0), 0.0, _max_scroll())
	if _target != before:
		UiSfx.play("tick", 1.0 + 0.04 * clampf(_target / maxf(_max_scroll(), 1.0), 0.0, 1.0) * 10.0, 0.6)   # 目盛りごとのコッという音。下へ行くほど少し高い
	sc.get_viewport().set_input_as_handled()


## ドラッグでのスクロール。扱ったら true(左ボタンの押し下げ・離しは、カードにも届くように true を返さない)。
func _drag_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			if _drag_btn == 0:
				UiStyle.drag_moved = false   # 押すたびに戻す(スクロールできない一覧でも、前のドラッグの印が残らない)
			if _drag_btn != 0 or not _can_drag(event.position):
				return false
			_sync()
			_spring = false
			_vel = 0.0
			_drag_btn = event.button_index
			_drag_y0 = event.position.y
			_drag_from = _target
			_drag_moved = false
			_drag_hist.clear()
			_tick_i = int(floor(_target / STEP))
			return event.button_index == MOUSE_BUTTON_RIGHT
		if event.button_index != _drag_btn:
			return false
		var was_right := _drag_btn == MOUSE_BUTTON_RIGHT
		if _drag_moved and not was_right and UiStyle.animate:   # 左: 離す直前の勢いで、少し滑って止まる(止めてから離したら滑らない)
			_target = clampf(_target + _fling_vel() * FLING, 0.0, _max_scroll())
		_drag_btn = 0
		return was_right
	if event is InputEventMouseMotion and _drag_btn != 0:
		var dy: float = event.position.y - _drag_y0
		if not _drag_moved:
			if absf(dy) < DRAG_START:
				return false
			_drag_moved = true
			UiStyle.drag_moved = true   # このクリックでは、カードを選ばない
			_drag_y0 = event.position.y   # ここから動かし始める(しきい値の分、跳ばない)
			dy = 0.0
		var mul := 1.0 if _drag_btn == MOUSE_BUTTON_LEFT else maxf(FAST_MIN, _max_scroll() / maxf(sc.size.y * 0.8, 1.0))
		_target = clampf(_drag_from - dy * mul, 0.0, _max_scroll())
		if _drag_btn == MOUSE_BUTTON_LEFT:   # つかんだ分だけ、遅れずに動く
			_drag_hist.append([Time.get_ticks_msec(), _target])
			while _drag_hist.size() > 1 and Time.get_ticks_msec() - int(_drag_hist[0][0]) > 100:
				_drag_hist.pop_front()
			_pos = _target
			_apply()
		var ti := int(floor(_target / STEP))
		if ti != _tick_i:   # 目盛り(ホイール 1 回分)を越えるごとに、コッという音
			_tick_i = ti
			UiSfx.play("tick", 1.0 + 0.04 * clampf(_target / maxf(_max_scroll(), 1.0), 0.0, 1.0) * 10.0, 0.6)
		sc.get_viewport().set_input_as_handled()   # ドラッグ中は、カードのホバー(音・見た目)を動かさない
		return true
	return false


## 左ドラッグを離したときの勢い(スクロール量 / 秒)。直前 0.1 秒の動きから求める(止めてから離したら 0)。
func _fling_vel() -> float:
	var now_ms := Time.get_ticks_msec()
	var old: Array = []
	for h in _drag_hist:
		if now_ms - int(h[0]) <= 100:
			old = h
			break
	if old.is_empty():
		return 0.0
	var secs := maxf(float(now_ms - int(old[0])) / 1000.0, 0.05)   # 短すぎる間隔で割って、跳ねないように
	return clampf((_target - float(old[1])) / secs, -4000.0, 4000.0)


## ここを押したら、ドラッグでスクロールを始めてよいか(一覧の上で、つまみの上ではない・上にパネルがない)。
func _can_drag(at: Vector2) -> bool:
	if not sc.is_visible_in_tree() or _max_scroll() <= 0.0:
		return false
	if active.is_valid() and not active.call():
		return false
	if not sc.get_global_rect().has_point(at):
		return false
	var bar := sc.get_v_scroll_bar()
	return not (bar.is_visible_in_tree() and bar.get_global_rect().has_point(at))


## 外からスクロール位置が変えられていたら(つまみのドラッグなど)、そこを今の位置にする。
func _sync() -> void:
	if sc.scroll_vertical != _last:
		_pos = float(sc.scroll_vertical)
		_target = _pos
		_vel = 0.0
		_last = sc.scroll_vertical
	var mx := _max_scroll()
	if _pos > mx + 0.5:   # 位置は、今スクロールできる範囲の中に置く(範囲の外に残っていると、中身が伸びたときに一度に跳ぶ)
		_pos = mx
		_vel = minf(_vel, 0.0)


## 今の位置と目標を、同じだけずらす(中身の並びが変わったとき、見えている行を画面の同じ場所に保つ)。実際にずれた量(px)を返す。
func shift(dy: float) -> int:
	_sync()
	var s0 := sc.scroll_vertical
	_pos = maxf(_pos + dy, 0.0)
	_target = maxf(_target + dy, 0.0)
	_apply()
	return sc.scroll_vertical - s0


## 目標の位置(中身の上端からの px)へ、なめらかに動く。中身がまだ伸びている途中でも、その位置を目指す(届くまでは、端で待つ)。
func scroll_to(y: float) -> void:
	_sync()
	_spring = true
	_target = maxf(y, 0.0)
	if not UiStyle.animate:
		_pos = _target
		_apply()


func target() -> float:
	_sync()
	return _target


## control(スクロールの中のカード)が、スクロールの真ん中に来る位置へ動く(端まで届かないときは、端で止まる)。instant = true なら、動かさずにその位置へ置く。
func center_on_control(control: Control, instant := false) -> void:
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
	_spring = true
	_target = clampf(top + control.size.y * 0.5 - sc.size.y * 0.5, 0.0, _max_scroll())
	if instant or not UiStyle.animate:
		_pos = _target
		_vel = 0.0
		_apply()


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
	_spring = true
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
	if absf(_target - _pos) < 0.3 and absf(_vel) < 4.0:
		_vel = 0.0
		if _pos != _target:
			_pos = _target
			_apply()
		return
	var dt := minf(delta, MAX_DT)
	if _spring:   # 臨界減衰のばね: 止まった状態からなめらかに動き出し、行き過ぎずに止まる。目標が途中で変わっても、速さを保ってつながる
		var steps := maxi(1, int(ceil(dt * 240.0)))
		var h := dt / float(steps)
		for i in range(steps):
			_vel += (SPRING_W * SPRING_W * (_target - _pos) - 2.0 * SPRING_W * _vel) * h
			_pos += _vel * h
	else:
		_vel = 0.0
		_pos = lerpf(_pos, _target, 1.0 - exp(-RATE * dt))
	var mx := _max_scroll()
	if _pos > mx:   # 中身がまだ伸びている途中: 今の端で待つ(位置だけを端に留め、伸びたら、そこから続きを動く。一度に跳ばない)
		_pos = mx
		_vel = minf(_vel, 0.0)
	if _target > mx and absf(_pos - mx) < 0.3 and absf(_vel) < 4.0 and not _growing():
		_target = mx   # 中身が伸びきっても届かない目標は、端にする(端で止まったまま、待ち続けない)
	_apply()


## 中身の高さが、このフレームで変わったか(伸びている途中か)。
var _last_h := -1.0
func _growing() -> bool:
	var bar := sc.get_v_scroll_bar()
	var h := bar.max_value
	var g := not is_equal_approx(h, _last_h)
	_last_h = h
	return g


func _apply() -> void:
	sc.scroll_vertical = int(round(_pos))
	_last = sc.scroll_vertical
