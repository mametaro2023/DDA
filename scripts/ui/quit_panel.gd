extends Control
## 確認パネル(画面の上に重ねる)。既定は「ゲームを終了しますか？」(タイトル画面)。Enter で実行(confirmed)、Esc・「キャンセル」・パネルの外で閉じる(closed)。
## 全画面のときはウィンドウの ✕ が見えないので、タイトルの「終了」と Esc から出られるようにしてある。
## 文言は setup() で変えられる(部屋を出る確認などにも使う)。ゲームを終わらせる処理は、呼び出し側が confirmed につなぐ。

signal closed
signal confirmed

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

var title_text := "ゲームを終了しますか？"
var ok_text := "終了する"
var cancel_text := "キャンセル"

var _panel: PanelContainer
var _dim: ColorRect
var _done := false


func setup(p_title: String, p_ok: String, p_cancel := "キャンセル") -> void:
	title_text = p_title
	ok_text = p_ok
	cancel_text = p_cancel


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
	v.add_child(UiStyle.label(title_text, 24, UiStyle.TEXT, true))
	v.add_child(UiStyle.hline())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var ok := Button.new()
	ok.text = ok_text
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(0, 48)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStyle.style_primary(ok, true)
	ok.pressed.connect(_confirm)
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = cancel_text
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 48)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.set_meta("juice_sound", "back")
	cancel.pressed.connect(_cancel)
	row.add_child(cancel)
	UiStyle.close_on_outside_click(self, _panel, _cancel)
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.2)
	UiStyle.pop_scale(_panel, 0.93, 0.42)


func _confirm() -> void:
	if _done:
		return
	_done = true
	confirmed.emit()


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
		_confirm()
	get_viewport().set_input_as_handled()
