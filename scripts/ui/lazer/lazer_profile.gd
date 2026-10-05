extends Control
## プレイヤーの名前とアイコンを変えるパネル(上のツールバーの右端の名前を押すと、main が開く)。
## 名前(最大 16 文字)・アイコンの色(8 色)・図柄(頭文字・自機・輪・星・ハート・稲妻・音符)・好きな画像(正方形に切り抜く)。
## 「保存」で settings に入れて保存する(マルチプレイの表示名にもなる)。Esc・「キャンセル」・パネルの外で、変えずに閉じる。
## 契約は確認パネル(lazer_quit.gd)と同じ: signal closed。setup(settings) で、いまの設定の辞書を渡す。

signal closed

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const LazerDialog = preload("res://scripts/ui/lazer/lazer_dialog.gd")
const Profile = preload("res://scripts/profile.gd")
const Settings = preload("res://scripts/settings.gd")

const SWATCH := 34.0

var _settings: Dictionary
var _name := ""
var _color := 0
var _glyph := "letter"
var _f: Dictionary
var _edit: LineEdit
var _preview: Control
var _color_row: HBoxContainer
var _glyph_row: HBoxContainer
var _remove_btn: Control
var _dialog: FileDialog
var _done := false


## 押せる丸い札。paint(札, 指が乗っているか) で中身を描く。
class Pick extends Control:
	signal chosen
	var paint := Callable()
	var _hov := false

	func _init(px: float) -> void:
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _ready() -> void:
		mouse_entered.connect(func():
			_hov = true
			queue_redraw())
		mouse_exited.connect(func():
			_hov = false
			queue_redraw())

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit()
			accept_event()

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self, _hov)


func setup(settings: Dictionary) -> void:
	_settings = settings
	_name = str(settings.get("player_name", "")).strip_edges().left(Profile.MAX_NAME)
	var p := Profile.parse(str(settings.get("player_icon", "")))
	_color = int(p.color)
	_glyph = str(p.glyph)


func _ready() -> void:
	_f = LazerDialog.build(self, "user", LazerStyle.PINK, "プロフィール", "", 500.0)
	var body: VBoxContainer = _f.body
	body.add_theme_constant_override("separation", 12)
	# 名前 + プレビュー
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	body.add_child(top)
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(76, 76)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.draw.connect(func():
		Profile.draw_avatar(_preview, Vector2(38, 38), 36.0, Profile.spec_of(_color, _glyph), _shown_name()))
	top.add_child(_preview)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.add_theme_constant_override("separation", 6)
	top.add_child(nv)
	nv.add_child(LazerStyle.label("名前", 14, LazerStyle.TEXT_MUTE))
	_edit = LineEdit.new()
	_edit.text = _name
	_edit.max_length = Profile.MAX_NAME
	_edit.placeholder_text = Profile.DEFAULT_NAME
	_edit.custom_minimum_size = Vector2(0, 38)
	_edit.add_theme_font_size_override("font_size", 17)
	_edit.text_changed.connect(func(t: String):
		_name = t
		_preview.queue_redraw()
		_redraw_glyphs())
	_edit.text_submitted.connect(func(_t: String): _save())
	nv.add_child(_edit)
	# 色
	body.add_child(LazerStyle.label("色", 14, LazerStyle.TEXT_MUTE))
	_color_row = HBoxContainer.new()
	_color_row.add_theme_constant_override("separation", 8)
	body.add_child(_color_row)
	for i in range(Profile.COLORS.size()):
		var pk := Pick.new(SWATCH)
		pk.paint = func(c: Control, hov: bool):
			var col: Color = Profile.COLORS[i]
			c.draw_circle(c.size * 0.5, SWATCH * 0.5 - 4.0 + (1.5 if hov else 0.0), col)
			if _color == i:
				c.draw_arc(c.size * 0.5, SWATCH * 0.5 - 1.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		pk.chosen.connect(func():
			UiSfx.play("select", 1.0 + 0.04 * i)
			_color = i
			if _glyph == "image":
				_glyph = "letter"
			_refresh())
		_color_row.add_child(pk)
	# 図柄
	body.add_child(LazerStyle.label("図柄", 14, LazerStyle.TEXT_MUTE))
	_glyph_row = HBoxContainer.new()
	_glyph_row.add_theme_constant_override("separation", 8)
	body.add_child(_glyph_row)
	for g in Profile.GLYPHS:
		var pk := Pick.new(SWATCH + 6.0)
		pk.tooltip_text = str(Profile.GLYPH_NAMES[g])
		pk.paint = func(c: Control, hov: bool):
			Profile.draw_avatar(c, c.size * 0.5, c.size.x * 0.5 - 3.0 + (1.5 if hov else 0.0), Profile.spec_of(_color, g), _shown_name())
			if _glyph == g:
				c.draw_arc(c.size * 0.5, c.size.x * 0.5 - 0.5, 0.0, TAU, 32, Color.WHITE, 2.0, true)
		pk.chosen.connect(func():
			UiSfx.play("select", 1.2)
			_glyph = g
			_refresh())
		_glyph_row.add_child(pk)
	# 画像
	var img_row := HBoxContainer.new()
	img_row.add_theme_constant_override("separation", 10)
	body.add_child(img_row)
	var img_tile := Pick.new(SWATCH + 6.0)
	img_tile.tooltip_text = "画像"
	img_tile.paint = func(c: Control, hov: bool):
		var cc: Vector2 = c.size * 0.5
		if Profile.texture() != null:
			Profile.draw_avatar(c, cc, c.size.x * 0.5 - 3.0 + (1.5 if hov else 0.0), Profile.spec_of(_color, "image"), _shown_name())
		else:
			c.draw_arc(cc, c.size.x * 0.5 - 3.0, 0.0, TAU, 32, Color(1, 1, 1, 0.45 if hov else 0.25), 1.5, true)
			LazerIcons.draw_icon(c, "image", cc, 9.0, Color(1, 1, 1, 0.7 if hov else 0.45), 1.6)
		if _glyph == "image":
			c.draw_arc(cc, c.size.x * 0.5 - 0.5, 0.0, TAU, 32, Color.WHITE, 2.0, true)
	img_tile.chosen.connect(func():
		if Profile.texture() != null:
			UiSfx.play("select", 1.2)
			_glyph = "image"
			_refresh()
		else:
			_pick_image())
	img_row.add_child(img_tile)
	var pick_btn := _small_button("画像を選ぶ…", "image", _pick_image)
	img_row.add_child(pick_btn)
	_remove_btn = _small_button("画像を外す", "trash", _remove_image)
	img_row.add_child(_remove_btn)
	_remove_btn.visible = Profile.texture() != null
	# 決定・取り消し
	LazerDialog.button(_f.buttons, "保存", LazerStyle.PINK, "", Color(0.16, 0.03, 0.07), _save)
	LazerDialog.button(_f.buttons, "キャンセル", Color(0.3, 0.28, 0.38), "back", LazerStyle.TEXT, _cancel, "back")
	UiStyle.close_on_outside_click(self, _f.panel, _cancel)
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; 画像"])
	_dialog.use_native_dialog = true
	_dialog.file_selected.connect(_on_image_chosen)
	add_child(_dialog)
	LazerDialog.open_anim(self, _f)
	_edit.grab_focus.call_deferred()


func _shown_name() -> String:
	var n := _name.strip_edges()
	return n if n != "" else Profile.DEFAULT_NAME


func _small_button(caption: String, icon: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + caption
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", LazerStyle.box(Color(1, 1, 1, 0.07), LazerStyle.LINE, 1, 8, 12, 6))
	b.add_theme_stylebox_override("hover", LazerStyle.box(Color(1, 1, 1, 0.14), LazerStyle.LINE, 1, 8, 12, 6))
	b.add_theme_stylebox_override("pressed", LazerStyle.box(Color(1, 1, 1, 0.2), LazerStyle.LINE, 1, 8, 12, 6))
	b.pressed.connect(on_press)
	return b


func _redraw_glyphs() -> void:
	for row in [_color_row, _glyph_row]:
		for c in (row as Control).get_children():
			(c as Control).queue_redraw()


func _refresh() -> void:
	_preview.queue_redraw()
	_redraw_glyphs()
	for c in (_remove_btn.get_parent() as Control).get_children():
		(c as Control).queue_redraw()


func _pick_image() -> void:
	UiSfx.play("click")
	_dialog.popup_centered_ratio(0.7)


func _on_image_chosen(path: String) -> void:
	if Profile.import_image(path):
		_glyph = "image"
		_remove_btn.visible = true
		UiSfx.play("select", 1.4)
	else:
		UiSfx.play("deny")
	_refresh()


func _remove_image() -> void:
	UiSfx.play("click")
	Profile.remove_image()
	if _glyph == "image":
		_glyph = "letter"
	_remove_btn.visible = false
	_refresh()


func _save() -> void:
	if _done:
		return
	_done = true
	Profile.apply(_settings, _name, Profile.spec_of(_color, _glyph))
	Settings.save_all(_settings)
	LazerDialog.close_anim(self, _f, func(): closed.emit(), "select")


func _cancel() -> void:
	if _done:
		return
	_done = true
	LazerDialog.close_anim(self, _f, func(): closed.emit())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()
