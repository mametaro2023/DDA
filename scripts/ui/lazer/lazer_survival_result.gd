extends "res://scripts/ui/lazer/lazer_screen.gd"
## サバイバルのリザルト(docs/survival_plan.md の §7)。左に合計点(数え上がる)・自己ベストの印・クリアした曲数・届いた Lv・時間・開始の Lv・MOD、
## 右に曲ごとの内訳(曲名・難易度・Lv・点・f・加わった点)と、選んだ強化。ランクは出さない。
## 操作: R / Enter で「もう一度」(準備画面へ)、Esc で「タイトルへ」。

signal again_requested
signal menu_requested

const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const Upgrades = preload("res://scripts/survival/upgrades.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const COUNT_DELAY := 0.4
const COUNT_TIME := 1.4

var kind := "survival_result"
var rec: Dictionary = {}
var is_best := false
var _bg_tex: Texture2D
var _total_l: Label
var _t := 0.0
var _buttons: Array = []
var _options: Control


## p_rec: SurvivalRun.to_record() / p_best: 自己ベストを超えた / bg: 最後の曲の背景
func setup(p_rec: Dictionary, p_best: bool, bg: Texture2D = null) -> void:
	rec = p_rec
	is_best = p_best
	_bg_tex = bg


func _ready() -> void:
	settings = Settings.load_all()
	_build_base()
	if _bg_tex != null:
		set_background(_bg_tex, true)
	_build_toolbar(["サバイバル", "リザルト"])
	_build_left()
	_build_right()
	_build_footer()
	var back := _footer_button("タイトルへ", LazerStyle.PINK, "back", 0, 220, func(): menu_requested.emit())
	back.set_meta("juice_sound", "back")
	_buttons.append(back)
	_buttons.append(_footer_button("もう一度", LazerStyle.GREEN, "retry", 214, 210, func(): again_requested.emit(), Color(0.08, 0.18, 0.02)))
	if UiStyle.animate:
		for b in _buttons:
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var enable := create_tween()
		enable.tween_interval(1.2)
		enable.tween_callback(func():
			for b in _buttons:
				b.mouse_filter = Control.MOUSE_FILTER_STOP)
	else:
		_t = COUNT_DELAY + COUNT_TIME


func _card(x: float, y: float, w: float, h: float, accent: Color) -> Control:
	var c := Control.new()
	_place(c, x, y, w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		c.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.9), Color(accent.r, accent.g, accent.b, 0.5), 2, 18), Rect2(Vector2.ZERO, c.size)))
	return c


func _build_left() -> void:
	var left := _card(40, 64, 420, 552, LazerStyle.GREEN)
	var v := VBoxContainer.new()
	v.position = Vector2(28, 22)
	v.size = Vector2(364, 510)
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(v)
	v.add_child(_center(LazerStyle.label("SURVIVAL", 22, LazerStyle.GREEN, true)))
	v.add_child(_center(LazerStyle.label("TOTAL", 13, LazerStyle.TEXT_MUTE)))
	_total_l = LazerStyle.label("0", 54, LazerStyle.YELLOW, true)
	v.add_child(_center(_total_l))
	if is_best:
		var pill := LazerStyle.pill("自己ベスト", LazerStyle.YELLOW, 14)
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(pill)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var secs := int(round(float(rec.get("time_s", 0.0))))
	for t in [["クリアした曲", "%d 曲" % int(rec.get("cleared", 0))], ["届いた Lv", "%.2f" % float(rec.get("best_level", 0.0))],
			["時間", "%d:%02d" % [secs / 60, secs % 60]], ["開始の Lv", "%d" % int(rec.get("start_level", 0))]]:
		grid.add_child(_tile(t[0], t[1]))
	var mods: Array = rec.get("mods", [])
	var line: Array = []
	if not mods.is_empty():
		line.append("MOD: " + Mods.names(mods))
	if bool(rec.get("keyboard", false)):
		line.append("キーボード")
	if not line.is_empty():
		var ml := LazerStyle.label("  ・  ".join(line), 14, LazerStyle.TEXT_DIM)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size = Vector2(364, 0)
		v.add_child(ml)
	UiStyle.pop_in(left, 0.05, Vector2(-40, 0), 0.5)


func _center(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(364, 0)
	return l


func _tile(cap: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(176, 66)
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06), 1, 12, 14, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(LazerStyle.label(cap, 12, LazerStyle.TEXT_MUTE))
	v.add_child(LazerStyle.label(value, 26, LazerStyle.TEXT, true))
	return p


func _build_right() -> void:
	var right := _card(480, 64, 760, 552, Color(1, 1, 1, 0.3))
	var v := VBoxContainer.new()
	v.position = Vector2(24, 18)
	v.size = Vector2(712, 516)
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(v)
	v.add_child(LazerStyle.label("曲ごとの内訳", 15, LazerStyle.TEXT_DIM, true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(712, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.custom_minimum_size = Vector2(700, 0)
	sc.add_child(rows)
	rows.add_child(_row(["#", "曲", "Lv", "点", "f", "加わった点"], true, LazerStyle.TEXT_MUTE))
	var songs: Array = rec.get("songs", [])
	for i in range(songs.size()):
		var e: Dictionary = songs[i]
		var title_text := str(e.title)   # 「アーティスト - 曲名 [難易度]」
		if bool(e.failed):
			title_text += "(あきらめた)" if bool(e.get("gave_up", false)) else "(倒れた)"
		rows.add_child(_row([str(i + 1), title_text, "%.2f" % float(e.level), UiStyle.fmt(int(round(float(e.score)))), "%.2f" % float(e.f), "+ " + UiStyle.fmt(int(round(float(e.points))))],
			false, Color(1.0, 0.5, 0.52) if bool(e.failed) else LazerStyle.TEXT))
	v.add_child(LazerStyle.label("選んだ強化", 15, LazerStyle.TEXT_DIM, true))
	var ups: Array = rec.get("upgrades", [])
	var counts := {}
	var order: Array = []
	for id in ups:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var names: Array = order.map(func(id): return "%s ×%d" % [str(Upgrades.find(str(id)).get("name", id)), int(counts[id])] if int(counts[id]) > 1 else str(Upgrades.find(str(id)).get("name", id)))
	var ul := LazerStyle.label(" ・ ".join(names) if not names.is_empty() else "なし", 15, LazerStyle.TEXT)
	ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ul.custom_minimum_size = Vector2(712, 0)
	v.add_child(ul)
	UiStyle.pop_in(right, 0.12, Vector2(40, 0), 0.5)


const COL_W := [30.0, 330.0, 56.0, 104.0, 50.0, 120.0]


func _row(cells: Array, head: bool, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in range(cells.size()):
		var fs := 12 if head else 14
		var text := str(cells[k])
		if k == 1:
			text = LazerStyle.fit(LazerStyle.font(), text, fs, COL_W[1])
		var l := LazerStyle.label(text, fs, col, k == 5 and not head)
		l.custom_minimum_size = Vector2(COL_W[k], 0)
		l.clip_text = true
		if k >= 2:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return h


func _process(delta: float) -> void:
	super._process(delta)
	if _total_l == null:
		return
	var before := _t
	_t += delta
	var x := clampf((_t - COUNT_DELAY) / COUNT_TIME, 0.0, 1.0)
	x = 1.0 - pow(1.0 - x, 3.0)
	_total_l.text = UiStyle.fmt(int(round(float(rec.get("total", 0.0)) * x)))
	if before < COUNT_DELAY + COUNT_TIME and _t >= COUNT_DELAY + COUNT_TIME and UiStyle.animate:
		UiSfx.play("stamp")
		_total_l.pivot_offset = _total_l.size * 0.5
		UiStyle.spring(_total_l, "scale", Vector2(1.08, 1.08), Vector2.ONE, 0.4)


func on_overlay(open: bool, panel: Control = null) -> void:
	_options = panel if open else null


func _unhandled_key_input(event: InputEvent) -> void:
	if _options != null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_R, KEY_ENTER, KEY_KP_ENTER:
			again_requested.emit()
		KEY_ESCAPE:
			menu_requested.emit()
		_:
			return
	get_viewport().set_input_as_handled()
