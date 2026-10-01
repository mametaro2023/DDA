extends CanvasLayer
## 全画面の上に重なる、小さな表示(どの画面でも同じ)。
##   ・音量メーター … マウスホイールで音量を変える。回すと、画面上部に「全体 / 音楽 / 効果音」のメーターが一定時間出て、全体音量が変わる。
##     メーターをクリックして選んでからホイールを回すと、その音量(音楽 / 効果音)が変わる。表示が消えると選択は戻り、
##     次に回したときは、また全体音量が変わる。バーはマウスでも動かせる(クリックでその位置へ、押したまま左右へ)。
##     マウスがメーターの上にある間・ドラッグ中は、消えない。
##     スクロールできる一覧(選曲の曲リストなど)やスライダーの上では、ホイールは本来の動き(スクロール・値の変更)に使う
##     (メーターが出ている間と、Ctrl を押しながらのときは、どこでも音量)。
##   ・トースト … 「曲を取り込みました」などの短い通知。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Settings = preload("res://scripts/settings.gd")
const Volume = preload("res://scripts/volume.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const NAMES := ["全体", "音楽", "効果音"]
const STEP := 5
const SHOW_TIME := 1.7      # 最後に操作してから、メーターが消えるまで(秒)
const FADE_TIME := 0.25
const TOAST_TIME := 3.2

var _panel: PanelContainer
var _rows: Array = []
## 音量メーターが出ているか(出ている間は、ホイールは、どこでも音量に使う)
static var meter_visible := false

var _sel := 0
var _drag := -1            # バーをドラッグ中の行(なければ -1)
var _t := 0.0
var _shown := false
var _tween: Tween
var _toast: PanelContainer
var _toast_l: Label
var _toast_t := 0.0
var _toast_tween: Tween


func _ready() -> void:
	layer = 90
	# 音量メーター
	_panel = PanelContainer.new()
	_panel.position = Vector2(490, 14)
	_panel.custom_minimum_size = Vector2(300, 0)
	_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.035, 0.06, 0.88), UiStyle.LINE, 1, 8, 10, 8))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	for i in range(NAMES.size()):
		var row := Control.new()
		row.custom_minimum_size = Vector2(280, 30)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.draw.connect(_draw_row.bind(row, i))
		row.gui_input.connect(_on_row_input.bind(row, i))
		v.add_child(row)
		_rows.append(row)
	# トースト
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.035, 0.06, 0.92), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.6), 1, 18, 18, 8))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)
	_toast_l = UiStyle.label("", 15, UiStyle.TEXT)
	_toast.add_child(_toast_l)


## バーの左端・幅(行の中の座標)。
func _bar_x() -> float:
	return 78.0


func _bar_w(row: Control) -> float:
	return row.size.x - _bar_x() - 56.0


## 行への操作: 左クリックでその音量を選び、バーの上なら、そこへ合わせる。押したまま左右に動かして調整できる。
func _on_row_input(ev: InputEvent, row: Control, i: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_select(i)
			if ev.position.x >= _bar_x() - 8.0 and ev.position.x <= _bar_x() + _bar_w(row) + 8.0:
				_drag = i
				_set_from_x(row, i, ev.position.x)
		elif _drag == i:
			_drag = -1
	elif ev is InputEventMouseMotion and _drag == i:
		_set_from_x(row, i, ev.position.x)


func _set_from_x(row: Control, i: int, x: float) -> void:
	var before := Volume.get_value(i)
	Volume.set_value(i, int(round(clampf((x - _bar_x()) / _bar_w(row), 0.0, 1.0) * 100.0)))
	if Volume.get_value(i) != before:
		_volume_tick()
	_t = SHOW_TIME
	_redraw()


func _draw_row(row: Control, i: int) -> void:
	var sel := i == _sel
	var v := Volume.get_value(i)
	var font := ThemeDB.fallback_font
	var w := row.size.x
	if sel:
		row.draw_rect(Rect2(0, 0, w, row.size.y), Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.12))
		row.draw_rect(Rect2(0, 0, 2, row.size.y), UiStyle.ACCENT)
	var c := UiStyle.ACCENT if sel else UiStyle.TEXT_DIM
	row.draw_string(font, Vector2(10, 20), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, 60.0, 14, c)
	var bx := _bar_x()
	var bw := _bar_w(row)
	row.draw_rect(Rect2(bx, 12, bw, 6), Color(1, 1, 1, 0.14))
	row.draw_rect(Rect2(bx, 12, bw * v / 100.0, 6), c)
	row.draw_circle(Vector2(bx + bw * v / 100.0, 15), 5.0 if sel else 4.0, Color.WHITE if sel else Color(1, 1, 1, 0.7))
	row.draw_string(font, Vector2(w - 50.0, 20), "%d%%" % v, HORIZONTAL_ALIGNMENT_RIGHT, 44.0, 14, c)


## 音量を変えたときの、その音量での小さな音(音量の目安になり、音階のように上がる)。
func _volume_tick() -> void:
	UiSfx.play("tick", UiSfx.scale_pitch(Volume.get_value(_sel) / 100.0, 1.6) * 0.9, 1.0)


func _select(i: int) -> void:
	_sel = i
	_t = SHOW_TIME
	_redraw()


func _redraw() -> void:
	for r in _rows:
		r.queue_redraw()


func _show_panel() -> void:
	_t = SHOW_TIME
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var was_shown := _shown
	_panel.visible = true
	_panel.modulate.a = 1.0
	_shown = true
	if not was_shown:   # 出るときは、上から弾んで降りてくる
		UiStyle.spring(_panel, "position:y", -80.0, 14.0, 0.4)
	else:
		_panel.position.y = 14.0
	meter_visible = true
	_redraw()


func _hide_panel() -> void:
	_shown = false
	meter_visible = false
	_drag = -1
	_sel = 0   # 消えたら選択は戻る(次に回したときは、全体音量)
	Settings.save_all(Settings.load_all())   # 音量を保存
	if not UiStyle.animate:
		_panel.visible = false
		return
	_tween = create_tween().set_parallel(true)   # 消えるときは、上へ戻りながら薄れる
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_property(_panel, "position:y", -10.0, FADE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func(): _panel.visible = false)


func _process(delta: float) -> void:
	if _shown:
		if _drag >= 0 or _panel.get_global_rect().has_point(_panel.get_global_mouse_position()):
			_t = SHOW_TIME   # バーを動かしているとき・マウスがメーターの上にあるときは、消えない
		_t -= delta
		if _t <= 0.0:
			_hide_panel()
	if _toast.visible:
		_toast_t -= delta
		if _toast_t < 0.3 and _toast_t > 0.0:
			_toast.modulate.a = _toast_t / 0.3   # 消えるときはなめらかに
		if _toast_t <= 0.0:
			_toast.visible = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if not _takes_wheel():
		return
	var d := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	Volume.set_value(_sel, Volume.get_value(_sel) + d * STEP)
	_show_panel()
	_volume_tick()
	get_viewport().set_input_as_handled()


## このホイール操作を、音量に使うか。スクロールできる一覧・スライダー・文字入力の上では、本来の動きに譲る
## (メーターが出ている間と、Ctrl を押しているときは、どこでも音量)。
func _takes_wheel() -> bool:
	if _shown or Input.is_key_pressed(KEY_CTRL):
		return true
	var n: Node = get_viewport().gui_get_hovered_control()
	while n != null:
		if n is Slider or n is TextEdit or n is ItemList:
			return false
		if n is ScrollContainer:
			var bar: VScrollBar = n.get_v_scroll_bar()
			if bar.max_value > bar.page + 1.0:
				return false
		n = n.get_parent()
	return true


## 短い通知を、画面の下に出す。
func toast(msg: String) -> void:
	_toast_l.text = msg
	_toast.reset_size()
	_toast.position = Vector2((1280.0 - _toast.size.x) * 0.5, 640.0)
	_toast.visible = true
	_toast_t = TOAST_TIME
	UiSfx.play("toast")
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	if UiStyle.animate:   # 下から弾んで上がり、ふわっと現れる
		_toast.modulate.a = 0.0
		_toast_tween = create_tween().set_parallel(true)
		_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
		UiStyle.spring(_toast, "position:y", 676.0, 640.0, 0.45)
		_toast.pivot_offset = _toast.size * 0.5
		UiStyle.spring(_toast, "scale", Vector2(0.9, 0.9), Vector2.ONE, 0.45)
	else:
		_toast.modulate.a = 1.0
