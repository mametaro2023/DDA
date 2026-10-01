extends Control
## アップデートのパネル(タイトル画面の上に重ねる)。新しいバージョンの案内 → 「今すぐ更新」でダウンロード(進み具合を表示)→ 自動で入れ替えて再起動。
## 入れ替えられない場合(開発中の実行・書き込めない場所)は、リリースのページを開くボタンにする。Esc / 「後で」で閉じる。

signal closed

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const Updater = preload("res://scripts/updater.gd")

var updater
var _dim: ColorRect
var _panel: PanelContainer
var _closing := false
var _busy := false
var _bar: ProgressBar
var _status: Label
var _btn_update: Button
var _btn_later: Button
var _progress_box: VBoxContainer


func setup(p_updater) -> void:
	updater = p_updater


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
	_panel.position = Vector2(300, 130)
	_panel.size = Vector2(680, 460)
	_panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 30, 26))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	v.add_child(UiStyle.label("アップデート", 26, UiStyle.TEXT, true))
	v.add_child(UiStyle.hline())
	var info: Dictionary = updater.info
	var ver := HBoxContainer.new()
	ver.add_theme_constant_override("separation", 14)
	ver.add_child(UiStyle.label("v%s" % updater.current, 20, UiStyle.TEXT_DIM))
	ver.add_child(UiStyle.label("→", 20, UiStyle.TEXT_FAINT))
	ver.add_child(UiStyle.label("v%s" % str(info.get("version", "?")), 26, UiStyle.ACCENT, true))
	v.add_child(ver)
	v.add_child(UiStyle.caption("RELEASE NOTES"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var notes := UiStyle.label(_clean_notes(str(info.get("notes", ""))), 14, UiStyle.TEXT_DIM)
	notes.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(notes)
	v.add_child(scroll)
	# ダウンロードの進み具合
	_progress_box = VBoxContainer.new()
	_progress_box.add_theme_constant_override("separation", 6)
	_progress_box.visible = false
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.add_theme_stylebox_override("background", UiStyle.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3))
	_bar.add_theme_stylebox_override("fill", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 3))
	_progress_box.add_child(_bar)
	_status = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	_progress_box.add_child(_status)
	v.add_child(_progress_box)
	# ボタン
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_btn_later = Button.new()
	_btn_later.text = "後で"
	_btn_later.focus_mode = Control.FOCUS_NONE
	_btn_later.pressed.connect(close_panel)
	row.add_child(_btn_later)
	_btn_update = Button.new()
	_btn_update.focus_mode = Control.FOCUS_NONE
	_btn_update.custom_minimum_size = Vector2(200, 40)
	_btn_update.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.9), Color(0, 0, 0, 0), 0, 4, 16, 8))
	_btn_update.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.ACCENT, Color(0, 0, 0, 0), 0, 4, 16, 8))
	_btn_update.add_theme_stylebox_override("disabled", UiStyle.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 4, 16, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_btn_update.add_theme_color_override(k, Color(0.02, 0.06, 0.1))
	_btn_update.add_theme_color_override("font_disabled_color", UiStyle.TEXT_FAINT)
	_btn_update.add_theme_font_override("font", UiStyle.bold())
	if updater.can_self_update():
		_btn_update.text = "今すぐ更新"
		_btn_update.pressed.connect(_start)
	else:   # 入れ替えられない場合は、リリースのページへ
		_btn_update.text = "ダウンロードページを開く"
		_btn_update.pressed.connect(func(): OS.shell_open(str(info.get("page", Updater.PAGE_URL))))
	row.add_child(_btn_update)
	updater.progress.connect(_on_progress)
	updater.failed.connect(_on_failed)
	updater.staged.connect(_on_staged)
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.22)
	UiStyle.pop_scale(_panel, 0.93, 0.42)


func _exit_tree() -> void:
	if updater == null:
		return
	for pair in [[updater.progress, _on_progress], [updater.failed, _on_failed], [updater.staged, _on_staged]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


## GitHub の説明文(Markdown)を、装飾記号を減らした読みやすい文字にする。
static func _clean_notes(s: String) -> String:
	var out: Array = []
	for line in s.replace("\r", "").split("\n"):
		var t: String = line
		while t.begins_with("#"):
			t = t.substr(1)
		t = t.strip_edges(true, false).replace("**", "").replace("`", "")
		if t.begins_with("- ") or t.begins_with("* "):
			t = "・" + t.substr(2)
		out.append(t)
	return "\n".join(out).strip_edges()


func _start() -> void:
	if _busy:
		return
	_busy = true
	_btn_update.disabled = true
	_btn_later.disabled = true
	_progress_box.visible = true
	_status.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	updater.start_download()


func _on_progress(frac: float, text: String) -> void:
	_bar.value = frac
	_status.text = text


func _on_failed(msg: String) -> void:
	_busy = false
	_progress_box.visible = true
	_status.text = msg
	_status.add_theme_color_override("font_color", UiStyle.DANGER)
	_btn_later.disabled = false
	_btn_update.disabled = false
	_btn_update.text = "ダウンロードページを開く"
	for c in _btn_update.pressed.get_connections():
		_btn_update.pressed.disconnect(c.callable)
	_btn_update.pressed.connect(func(): OS.shell_open(str(updater.info.get("page", Updater.PAGE_URL))))


func _on_staged() -> void:
	_status.text = "再起動して更新します…"
	await get_tree().create_timer(0.6).timeout
	updater.apply_and_quit()


func close_panel() -> void:
	if _closing or _busy:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	_panel.pivot_offset = _panel.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_panel, "modulate:a", 0.0, 0.16)
	t.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
