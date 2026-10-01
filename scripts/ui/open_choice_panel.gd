extends Control
## .osz を開いたとき、「このアプリで開く / osu! で開く」を選ぶパネル(画面の上に重ねる)。
## 「今後もこの選択を使う」にチェックすると、設定(osz_open)に保存される(あとで、設定の「ゲーム」で戻せる)。Esc・「やめる」で何もしない。

signal chosen(kind: String, remember: bool)   # kind: "dda" | "osu" | "cancel"

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

var file_name := ""
var _remember: Button
var _panel: PanelContainer
var _dim: ColorRect
var _done := false


func setup(p_file_name: String) -> void:
	file_name = p_file_name


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
	_panel.position = Vector2(340, 214)
	_panel.size = Vector2(600, 292)
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 30, 26))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	v.add_child(UiStyle.label("曲ファイルを開く", 24, UiStyle.TEXT, true))
	v.add_child(UiStyle.hline())
	var name_l := UiStyle.label(file_name, 15, UiStyle.TEXT_DIM)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(540, 0)
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var dda := _primary("DDA で開く")
	dda.pressed.connect(func(): _choose("dda"))
	row.add_child(dda)
	var osu := Button.new()
	osu.text = "osu! で開く"
	osu.focus_mode = Control.FOCUS_NONE
	osu.custom_minimum_size = Vector2(0, 44)
	osu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	osu.pressed.connect(func(): _choose("osu"))
	row.add_child(osu)
	_remember = Button.new()   # 押すたびに入り切りするボタン(入っている間は、色がつく)
	_remember.text = "今後もこの選択を使う(設定で変えられます)"
	_remember.toggle_mode = true
	_remember.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_remember.focus_mode = Control.FOCUS_NONE
	var on := UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.16), UiStyle.ACCENT, 1, 4, 16, 8)
	for k in ["pressed", "hover_pressed"]:
		_remember.add_theme_stylebox_override(k, on)
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		_remember.add_theme_color_override(k, UiStyle.ACCENT)
	v.add_child(_remember)
	var cancel := Button.new()
	cancel.text = "やめる"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel.pressed.connect(func(): _choose("cancel"))
	v.add_child(cancel)
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.2)
	UiStyle.pop_scale(_panel, 0.93, 0.42)


func _primary(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9), Color(0, 0, 0, 0), 0, 4, 16, 8))
	b.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	b.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color(0.02, 0.06, 0.1))
	b.add_theme_font_override("font", UiStyle.bold())
	return b


func _choose(kind: String) -> void:
	if _done:
		return
	_done = true
	chosen.emit(kind, _remember.button_pressed and kind != "cancel")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		_choose("cancel")
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_choose("dda")
	get_viewport().set_input_as_handled()
