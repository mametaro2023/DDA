extends RefCounted
## lazer 風のパネルの枠(設定・遊び方などで共通): 画面の左に貼りつく縦長のパネル。左に見出しと項目の一覧(選んでいる項目の下を、ピンクの枠が滑る)、
## 右に内容、下に「閉じる」。背景は暗くなり、パネルの外のクリックで閉じる。classic のパネル(options_panel.gd など)の中身の作りと同じ部品名で返すので、
## それらを継承した lazer 版が、同じ処理(ページの切り替え・設定の書き換え)をそのまま使える。
## あわせて、トグル・スライダーの 1 行の部品も、ここに置く。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")

const NAV_W := 196.0


## host に枠を作る。返す辞書: {dim, panel, nav(項目のボタン), nav_holder, nav_ind(滑る枠), stack(内容を入れる入れもの), close(閉じるボタン)}
static func build(host: Control, title: String, caption: String, sections: Array, width: float, on_pick: Callable) -> Dictionary:
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.theme = LazerStyle.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(0, 0)
	panel.size = Vector2(width, 720)
	var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.985), Color(0, 0, 0, 0), 0, 0, 0, 0)
	sb.border_color = LazerStyle.PINK
	sb.border_width_right = 3
	panel.add_theme_stylebox_override("panel", sb)
	host.add_child(panel)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	# 左: 見出しと項目
	var nav_box := VBoxContainer.new()
	nav_box.add_theme_constant_override("separation", 6)
	var nav_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		nav_margin.add_theme_constant_override("margin_" + side, 22)
	nav_margin.add_child(nav_box)
	var nav_holder := Control.new()   # 枠(nav_ind)を、ボタンの下で自由に動かすための入れもの
	nav_holder.custom_minimum_size = Vector2(NAV_W, 0)
	var nav_ind := Panel.new()
	nav_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ind_style := LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.2), Color(0, 0, 0, 0), 0, 10)
	ind_style.border_color = LazerStyle.PINK
	ind_style.border_width_left = 4
	nav_ind.add_theme_stylebox_override("panel", ind_style)
	nav_ind.visible = false
	nav_holder.add_child(nav_ind)
	nav_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nav_holder.add_child(nav_margin)
	root.add_child(nav_holder)
	nav_box.add_child(LazerStyle.label(title, 26, LazerStyle.TEXT, true))
	nav_box.add_child(LazerStyle.label(caption, 12, LazerStyle.TEXT_MUTE))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	nav_box.add_child(sp)
	var group := ButtonGroup.new()
	var nav: Array = []
	var none := StyleBoxEmpty.new()
	for i in range(sections.size()):
		var b := Button.new()
		b.text = str(sections[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for st in ["normal", "hover", "pressed", "hover_pressed"]:   # 面は、滑る枠が描く(ボタン自身は文字の色だけ)
			b.add_theme_stylebox_override(st, LazerStyle.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 18, 9))
		b.add_theme_font_override("font", LazerStyle.font_bold())
		b.add_theme_font_size_override("font_size", 16)
		b.add_theme_color_override("font_color", LazerStyle.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.set_meta("juice_sound", "select")
		b.pressed.connect(func(): on_pick.call(i))
		nav_box.add_child(b)
		nav.append(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_box.add_child(fill)
	var close := LazerButton.new("閉じる", Color(0.3, 0.28, 0.38), "back", LazerStyle.TEXT)
	close.custom_minimum_size = Vector2(0, 46)
	close.font_size = 16
	close.set_meta("juice_sound", "back")
	nav_box.add_child(close)
	var vline := ColorRect.new()
	vline.color = LazerStyle.LINE
	vline.custom_minimum_size = Vector2(1, 0)
	root.add_child(vline)
	# 右: 内容
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content_margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(content_margin)
	var stack := Control.new()
	content_margin.add_child(stack)
	return {"dim": dim, "panel": panel, "nav": nav, "nav_holder": nav_holder, "nav_ind": nav_ind, "stack": stack, "close": close}


## 開く動き: 背景が暗くなり、パネルが左から滑り込む。
static func open_anim(host: Control, dim: ColorRect, panel: Control, nav: Array) -> void:
	UiSfx.play("open")
	UiStyle.tween(dim, "color:a", 0.0, 0.62, 0.22)
	if UiStyle.animate and host.is_inside_tree():
		var w := panel.size.x
		panel.position.x = -w
		var t := host.create_tween()
		t.tween_property(panel, "position:x", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k in range(nav.size()):   # 項目が上から順に、弾んで現れる(コンテナの中なので、位置ではなく大きさで動かす)
		UiStyle.pop_scale(nav[k], 0.9, 0.36, 0.12 + 0.05 * k)


## 閉じる動き: パネルが左へ滑り出て、背景が明るさを戻す。終わったら done。
static func close_anim(host: Control, dim: ColorRect, panel: Control, done: Callable) -> void:
	UiSfx.play("close")
	if not UiStyle.animate:
		done.call()
		return
	var t := host.create_tween().set_parallel(true)
	t.tween_property(dim, "color:a", 0.0, 0.2)
	t.tween_property(panel, "position:x", -panel.size.x, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(done)


# --- 1 行の部品 ---

## トグルの行(タイトル・説明・右のスイッチ)。on_toggle(新しい状態) を呼ぶ。toggle_card.gd と同じく、外から ToggleCard.set_on で状態を変えられる(meta の state / apply)。
static func toggle(host: Control, title: String, lines: String, on: bool, on_toggle: Callable) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"on": on, "k": 1.0 if on else 0.0}
	var sw := Control.new()   # スイッチ(つまみが左右に動く)
	sw.custom_minimum_size = Vector2(48, 26)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.draw.connect(func():
		var k: float = state.k
		sw.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.16).lerp(LazerStyle.PINK, k), Color(0, 0, 0, 0), 0, 13), Rect2(0, 0, 48, 26))
		sw.draw_circle(Vector2(13.0 + 22.0 * k, 13), 9.5, Color.WHITE))
	var apply := func():
		c.add_theme_stylebox_override("panel", LazerStyle.box(Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.10) if state.on else Color(1, 1, 1, 0.045),
			Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.5) if state.on else Color(1, 1, 1, 0.07), 1, 12, 16, 12))
		var to := 1.0 if state.on else 0.0
		if UiStyle.animate and sw.is_inside_tree():
			var t := sw.create_tween()
			t.tween_method(func(v: float): state.k = v; sw.queue_redraw(), float(state.k), to, 0.16)
		else:
			state.k = to
			sw.queue_redraw()
	apply.call()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	c.add_child(h)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(LazerStyle.label(title, 17, LazerStyle.TEXT, true))
	if lines != "":
		var l := LazerStyle.label(lines, 13, LazerStyle.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		col.add_child(l)
	h.add_child(col)
	h.add_child(sw)
	c.mouse_entered.connect(func(): UiSfx.play("hover", 0.95))
	c.mouse_exited.connect(func(): UiStyle._card_press(c, 1.0, 0.2, false))
	c.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		if not ev.pressed:
			UiStyle._card_press(c, 1.0, 0.32, true)
			return
		UiStyle._card_press(c, 0.99, 0.06, false)
		state.on = not state.on
		apply.call()
		UiSfx.play("on" if state.on else "off")
		on_toggle.call(state.on))
	c.set_meta("state", state)
	c.set_meta("apply", apply)
	return c


## スライダーの行: 上に見出しと値、下に細いスライダー。値の表示は fmt(値) -> String。
static func slider_row(parent: Control, cap: String, lo: float, hi: float, step: float, value: float, fmt: Callable) -> HSlider:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	var l := LazerStyle.label(cap, 16, LazerStyle.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var val := LazerStyle.label(str(fmt.call(value)), 16, LazerStyle.PINK, true)
	top.add_child(val)
	v.add_child(top)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	v.add_child(s)
	s.value_changed.connect(func(x: float):
		val.text = str(fmt.call(x))
		if val.is_visible_in_tree():   # 値の文字が、変わるたびにぴょこっと跳ねる
			val.pivot_offset = Vector2(val.size.x, val.size.y * 0.5)
			UiStyle.spring(val, "scale", Vector2(1.16, 1.16), Vector2.ONE, 0.3))
	parent.add_child(v)
	return s
