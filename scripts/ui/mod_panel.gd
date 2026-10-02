extends Control
## MOD パネル(難易度選択の画面に重ねる)。付ける MOD を選ぶ。
## settings(選曲画面の設定の辞書)の mods を直接書き換え、変えたら changed を出す。保存は閉じるときに呼び出し側が行う。
## 下には、MOD 適用後の難易度(Lv。色つき)とベーススコアの倍率だけを出す。切り替えるたびに、数字がなめらかに動き、Lv の色も一緒に変わる。

signal changed
signal closed

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const ToggleCard = preload("res://scripts/ui/toggle_card.gd")
const SmoothScroll = preload("res://scripts/ui/smooth_scroll.gd")

const EASE_TIME := 0.5   # 数字が動く時間(秒)

var settings: Dictionary
## 選択中の難易度の、MOD 適用後の Lv を返す Callable(-> float。難易度がなければ負の値)
var level_cb: Callable = Callable()

var _lv_l: Label
var _mul_l: Label
var _lv_shown := -1.0     # いま表示している Lv(負 = まだ何も出していない)
var _mul_shown := 1.0
var _lv_tween: Tween
var _mul_tween: Tween
var _dim: ColorRect
var _panel: PanelContainer
var _closing := false


func setup(p_settings: Dictionary, p_level_cb: Callable) -> void:
	settings = p_settings
	level_cb = p_level_cb


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.66)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var panel := PanelContainer.new()
	_panel = panel
	panel.position = Vector2(240, 36)
	panel.size = Vector2(800, 648)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 28, 24))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(UiStyle.label("MOD", 24, UiStyle.TEXT, true))
	title_box.add_child(UiStyle.caption("難易度とスコアの修飾"))
	head.add_child(title_box)
	var close := Button.new()
	close.text = "閉じる"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(110, 34)
	close.pressed.connect(close_panel)
	head.add_child(close)
	v.add_child(head)
	v.add_child(UiStyle.hline())

	# カードが増えても合計表示が隠れないよう、カード一覧だけをスクロールにする
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	SmoothScroll.attach(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var mods: Array = settings.mods
	for m in Mods.ALL:
		var parts: PackedStringArray = (m.desc as String).split(" / ")
		var effects: Array = []
		for p in parts:
			if not p.begins_with("ベーススコア"):
				effects.append(p)
		var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
		list.add_child(ToggleCard.make(self, "%s   %s" % [m.name, m.tag], "  /  ".join(effects), m.color, mods.has(m.id), "ベーススコア %+d%%" % pct,
			func(on: bool): _on_toggled(m.id, on)))
	v.add_child(UiStyle.hline())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 60)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(foot)
	_lv_l = UiStyle.label("--", 44, UiStyle.TEXT_FAINT, true)
	foot.add_child(_stat_block("難易度  LV", _lv_l))
	_mul_l = UiStyle.label("×1.0000", 44, UiStyle.TEXT, true)
	foot.add_child(_stat_block("ベーススコア倍率", _mul_l))
	refresh_info(false)

	# 開く動き: 背景が暗くなり、パネルが下からふわっと上がる
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.66, 0.22)
	UiStyle.pop_scale(panel, 0.93, 0.42)


func _on_toggled(id: String, on: bool) -> void:
	var mods: Array = settings.mods
	if on and not mods.has(id):
		mods.append(id)
	elif not on:
		mods.erase(id)
	settings.mods = mods
	changed.emit()
	refresh_info()


## 見出し(小さな文字)と、その下の大きな数字。
func _stat_block(cap: String, value: Label) -> Control:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", -2)
	b.add_child(UiStyle.caption(cap))
	b.add_child(value)
	return b


## 合計ベーススコアの倍率と、選択中の難易度の MOD 適用後 Lv を更新する。animate なら、いま出している数字から新しい数字へ動かす。
func refresh_info(animate := true) -> void:
	if _lv_l == null:
		return
	var lv: float = level_cb.call() if level_cb.is_valid() else -1.0
	var mul: float = Mods.params(settings.mods).score_mul
	_ease_lv(lv, animate)
	_ease_mul(mul, animate)


func _show_lv(v: float) -> void:
	_lv_shown = v
	_lv_l.text = "%.2f" % v
	_lv_l.add_theme_color_override("font_color", UiStyle.level_color(v))   # 数字が動くあいだ、色も Lv に合わせて変わる


func _ease_lv(to: float, animate: bool) -> void:
	if _lv_tween != null and _lv_tween.is_valid():
		_lv_tween.kill()
	if to < 0.0:
		_lv_shown = -1.0
		_lv_l.text = "--"
		_lv_l.add_theme_color_override("font_color", UiStyle.TEXT_FAINT)
		return
	if not animate or not UiStyle.animate or _lv_shown < 0.0 or not is_inside_tree():
		_show_lv(to)
		return
	if is_equal_approx(_lv_shown, to):
		return
	_lv_tween = create_tween()
	_lv_tween.tween_method(_show_lv, _lv_shown, to, EASE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop(_lv_l)


func _show_mul(v: float) -> void:
	_mul_shown = v
	_mul_l.text = "×%.4f" % v


func _ease_mul(to: float, animate: bool) -> void:
	if _mul_tween != null and _mul_tween.is_valid():
		_mul_tween.kill()
	if not animate or not UiStyle.animate or not is_inside_tree():
		_show_mul(to)
		return
	if is_equal_approx(_mul_shown, to):
		return
	_mul_tween = create_tween()
	_mul_tween.tween_method(_show_mul, _mul_shown, to, EASE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pop(_mul_l)


## 数字が変わるとき、ぽんと少し弾む。
func _pop(l: Label) -> void:
	l.pivot_offset = Vector2(l.size.x * 0.5, l.size.y * 0.5)
	UiStyle.spring(l, "scale", Vector2(1.08, 1.08), Vector2.ONE, 0.35)


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	# 閉じる動き: パネルが少し縮みながら消え、背景が明るさを戻す
	_panel.pivot_offset = _panel.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_panel, "modulate:a", 0.0, 0.16)
	t.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()   # 開いている間、キー操作は、下の画面へ渡さない
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
		close_panel()
