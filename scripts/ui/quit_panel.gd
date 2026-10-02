extends Control
## 終了の確認(タイトル画面の上に重ねる)。Enter で終了、Esc・「キャンセル」で閉じる。
## 全画面のときはウィンドウの ✕ が見えないので、タイトルの「終了」と Esc から出られるようにしてある。

signal closed

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

var _panel: PanelContainer
var _dim: ColorRect
var _done := false


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.position = Vector2(390, 276)
	_panel.size = Vector2(500, 168)
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 30, 26))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	v.add_child(UiStyle.label("ゲームを終了しますか？", 24, UiStyle.TEXT, true))
	v.add_child(UiStyle.hline())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var quit := Button.new()
	quit.text = "終了する"
	quit.focus_mode = Control.FOCUS_NONE
	quit.custom_minimum_size = Vector2(0, 48)
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := UiStyle.DANGER
	quit.add_theme_stylebox_override("normal", UiStyle.box(Color(d.r, d.g, d.b, 0.85), Color(0, 0, 0, 0), 0, 4, 16, 8))
	quit.add_theme_stylebox_override("hover", UiStyle.box(d, Color(0, 0, 0, 0), 0, 4, 16, 8))
	quit.add_theme_stylebox_override("pressed", UiStyle.box(d, Color(0, 0, 0, 0), 0, 4, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		quit.add_theme_color_override(k, Color(0.1, 0.02, 0.03))
	quit.add_theme_font_override("font", UiStyle.bold())
	quit.pressed.connect(_quit)
	row.add_child(quit)
	var cancel := Button.new()
	cancel.text = "キャンセル"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 48)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_cancel)
	row.add_child(cancel)
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.2)
	UiStyle.pop_scale(_panel, 0.93, 0.42)


func _quit() -> void:
	if _done:
		return
	_done = true
	get_tree().quit()


func _cancel() -> void:
	if _done:
		return
	_done = true
	UiSfx.play("close")
	closed.emit()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_cancel()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_quit()
	get_viewport().set_input_as_handled()
