extends RefCounted
## トグルのカード(設定パネル・MOD パネルで共有)。タイトル・説明・(任意の)右端の文字を持ち、押すと入り切りが変わる。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")


## host はカードを置く画面(入れたときの粒を、その座標系で出す)。on_toggle(新しい状態) を呼ぶ。
## compact = true は、右端の文字(チップ)をタイトルの行へ移し、縦を詰めたカード(多くの項目を、スクロールなしで並べたいとき)。
static func make(host: Control, title: String, lines: String, color: Color, on: bool, right_text: String, on_toggle: Callable, compact := false) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"on": on}
	var mv := 7.0 if compact else 12.0
	var ind := PanelContainer.new()
	ind.custom_minimum_size = Vector2(18, 18)
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var apply := func():
		var s := state.on as bool
		c.add_theme_stylebox_override("panel", UiStyle.box(Color(color.r, color.g, color.b, 0.10 if s else 0.035),
			Color(color.r, color.g, color.b, 0.8 if s else 0.09), 1, 6, 16, mv))
		ind.add_theme_stylebox_override("panel", UiStyle.box(Color(color.r, color.g, color.b, 0.95) if s else Color(0, 0, 0, 0),
			Color(color.r, color.g, color.b, 0.9 if s else 0.35), 1, 9))
	apply.call()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	c.add_child(h)
	var ind_wrap := CenterContainer.new()
	ind_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ind_wrap.add_child(ind)
	h.add_child(ind_wrap)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_l := UiStyle.label(title, 18, color, true)
	if compact and right_text != "":
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 12)
		trow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(title_l)
		trow.add_child(UiStyle.chip(right_text, color))
		col.add_child(trow)
	else:
		col.add_child(title_l)
	if lines != "":
		var l := UiStyle.label(lines, 13, UiStyle.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		col.add_child(l)
	h.add_child(col)
	if right_text != "" and not compact:
		var chip_wrap := CenterContainer.new()
		chip_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_wrap.add_child(UiStyle.chip(right_text, color))
		h.add_child(chip_wrap)
	c.mouse_entered.connect(func(): UiSfx.play("hover", 0.95))
	c.mouse_exited.connect(func(): UiStyle._card_press(c, 1.0, 0.2, false))
	c.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		if not ev.pressed:
			UiStyle._card_press(c, 1.0, 0.32, true)
			return
		UiStyle._card_press(c, 0.98, 0.06, false)
		state.on = not state.on
		apply.call()
		ind.pivot_offset = ind.size * 0.5
		UiStyle.spring(ind, "scale", Vector2(0.4, 0.4), Vector2.ONE, 0.42)
		UiSfx.play("on" if state.on else "off")
		if state.on:   # 入れたときは、つまみから粒が弾ける
			UiFx.burst(host, ind.get_global_rect().get_center() - host.global_position, color, 9, 120.0, 0.5, 2.6)
		on_toggle.call(state.on))
	# 外から見た目を更新できるように、状態をメタに持たせる
	c.set_meta("state", state)
	c.set_meta("apply", apply)
	return c


static func set_on(c: PanelContainer, on: bool) -> void:
	c.get_meta("state").on = on
	c.get_meta("apply").call()
