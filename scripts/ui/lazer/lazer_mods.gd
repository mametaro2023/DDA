extends "res://scripts/ui/mod_panel.gd"
## lazer 風の MOD パネル: 画面の下からせり上がるシート。MOD は色の札(タイル)を横に並べ、押すと札が MOD の色に染まる。
## 右上に、選んでいる難易度の MOD 適用後 Lv と、ベーススコアの倍率。下に「すべて解除」と「閉じる」。
## MOD の付け外し・数字の動き・キー操作(Esc / M で閉じる)・契約(setup / signal changed・closed / refresh_info / multi)は、
## classic(mod_panel.gd)のものをそのまま使う。札は ToggleCard と同じ決まり(meta の state / apply)を持つので、「すべて解除」もそのまま働く。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")

const SHEET_H := 452.0
const COLS := 4
const TILE_H := 132.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = LazerStyle.make_theme()
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.015, 0.05, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var panel := PanelContainer.new()
	_panel = panel
	panel.position = Vector2(0, 720.0 - SHEET_H)
	panel.size = Vector2(1280, SHEET_H)
	var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.985), Color(0, 0, 0, 0), 0, 0, 40, 22)
	sb.border_color = LazerStyle.PINK
	sb.border_width_top = 3
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	# 上の段: 見出し(左)と、Lv・倍率(右)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(LazerStyle.label("MOD", 30, LazerStyle.TEXT, true))
	title_box.add_child(LazerStyle.label("難易度とスコアの修飾。複数つけると、効果も倍率も掛け算で重なります", 13, LazerStyle.TEXT_MUTE))
	head.add_child(title_box)
	_lv_l = LazerStyle.label("--", 38, LazerStyle.TEXT_MUTE, true)
	head.add_child(_stat_block("難易度  LV", _lv_l, 120.0))
	_mul_l = LazerStyle.label("×1.0000", 38, LazerStyle.TEXT, true)
	head.add_child(_stat_block("ベーススコア倍率", _mul_l, 170.0))
	# MOD の札(横 COLS 枚ずつ)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	var mods: Array = settings.mods
	for m in Mods.ALL:
		if multi and bool(m.get("solo", false)):
			continue
		var tile := _tile(m, mods.has(m.id), func(on: bool): _on_toggled(m.id, on))
		_cards[m.id] = tile
		grid.add_child(tile)
	# 下の段: 「すべて解除」(左)と「閉じる」(右)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	v.add_child(foot)
	_clear_btn = LazerButton.new("すべて解除", LazerStyle.PURPLE, "retry", Color(0.1, 0.04, 0.22))
	_clear_btn.text = "すべて解除"
	_clear_btn.custom_minimum_size = Vector2(210, 48)
	_clear_btn.font_size = 16
	_clear_btn.pressed.connect(_clear_all)
	foot.add_child(_clear_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var done := LazerButton.new("閉じる", LazerStyle.PINK, "back", Color(0.2, 0.04, 0.11))
	done.text = "閉じる"
	done.custom_minimum_size = Vector2(210, 48)
	done.font_size = 16
	done.set_meta("juice_sound", "back")
	done.pressed.connect(close_panel)
	foot.add_child(done)
	_sync_clear_btn()
	refresh_info(false)
	UiStyle.close_on_outside_click(self, panel, close_panel)
	# 開く動き: 背景が暗くなり、シートが下からせり上がり、札が左上から順に現れる
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.6, 0.22)
	if UiStyle.animate:
		panel.position.y = 720.0
		create_tween().tween_property(panel, "position:y", 720.0 - SHEET_H, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var k := 0
		for id in _cards:
			UiStyle.tween(_cards[id], "modulate:a", 0.0, 1.0, 0.24, 0.1 + 0.035 * k)
			k += 1


## MOD の札: 上に色の帯、タグ(英字)と名前、効果、下にベーススコアの倍率。付けると札が MOD の色に染まり、右上に印が付く。
func _tile(m: Dictionary, on: bool, on_toggle: Callable) -> PanelContainer:
	var c: Color = m.color
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(0, TILE_H)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var state := {"on": on, "k": 1.0 if on else 0.0, "hover": false}
	var pad := StyleBoxEmpty.new()   # 面は下の draw で自分で描く(余白だけを決める)
	pad.content_margin_left = 16
	pad.content_margin_right = 40
	pad.content_margin_top = 14
	pad.content_margin_bottom = 12
	tile.add_theme_stylebox_override("panel", pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var tag := LazerStyle.label(str(m.tag), 20, c, true)
	top.add_child(tag)
	var name_l := LazerStyle.label(str(m.name), 14, LazerStyle.TEXT_DIM, true)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(name_l)
	var effects: Array = []
	for p in (m.desc as String).split(" / "):
		if not p.begins_with("ベーススコア"):
			effects.append(p)
	var desc := LazerStyle.label("\n".join(effects), 12, LazerStyle.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.max_lines_visible = 3
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(desc)
	var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
	var mul := LazerStyle.label("ベーススコア %+d%%" % pct, 12, Color(c.r, c.g, c.b, 0.9), true)
	v.add_child(mul)
	# 面と印は自分で描く(色の帯・染まり具合・右上の丸い印)
	var deco := tile
	deco.draw.connect(func():
		var k: float = state.k
		var r := Rect2(Vector2.ZERO, deco.size)
		var base := Color(1, 1, 1, 0.05 + (0.03 if state.hover else 0.0))
		deco.draw_style_box(LazerStyle.box(base.lerp(Color(c.r, c.g, c.b, 0.26), k), Color(c.r, c.g, c.b, 0.18 + 0.62 * k), 2 if k > 0.5 else 1, 12), r)
		deco.draw_style_box(LazerStyle.box(Color(c.r, c.g, c.b, 0.55 + 0.45 * k), Color(0, 0, 0, 0), 0, 2), Rect2(14, 0, deco.size.x - 28, 3))
		var mc := Vector2(deco.size.x - 22.0, 22.0)
		deco.draw_arc(mc, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25).lerp(c, k), 1.6, true)
		if k > 0.01:
			deco.draw_circle(mc, 9.0 * k, c)
			deco.draw_polyline(PackedVector2Array([mc + Vector2(-4, 0), mc + Vector2(-1, 3.5), mc + Vector2(4.5, -3.5)]), Color(0.1, 0.05, 0.08, k), 2.0, true))
	var apply := func():
		var to := 1.0 if state.on else 0.0
		tag.add_theme_color_override("font_color", c.lightened(0.25) if state.on else c)
		name_l.add_theme_color_override("font_color", LazerStyle.TEXT if state.on else LazerStyle.TEXT_DIM)
		if UiStyle.animate and deco.is_inside_tree():
			var t := deco.create_tween()
			t.tween_method(func(x: float): state.k = x; deco.queue_redraw(), float(state.k), to, 0.18)
		else:
			state.k = to
			deco.queue_redraw()
	apply.call()
	tile.mouse_entered.connect(func():
		state.hover = true
		deco.queue_redraw()
		UiSfx.play("hover", 0.95))
	tile.mouse_exited.connect(func():
		state.hover = false
		deco.queue_redraw()
		UiStyle._card_press(tile, 1.0, 0.2, false))
	tile.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		if not ev.pressed:
			UiStyle._card_press(tile, 1.0, 0.32, true)
			return
		UiStyle._card_press(tile, 0.97, 0.06, false)
		state.on = not state.on
		apply.call()
		UiSfx.play("on" if state.on else "off")
		on_toggle.call(state.on))
	tile.set_meta("state", state)
	tile.set_meta("apply", apply)
	return tile


func _sync_clear_btn() -> void:
	super._sync_clear_btn()
	if _clear_btn != null:
		_clear_btn.queue_redraw()


## 見出し(小さな文字)と、その下の大きな数字(右の段)。
func _stat_block(cap: String, value: Label, width: float) -> Control:
	var b := VBoxContainer.new()
	b.custom_minimum_size = Vector2(width, 0)
	b.add_theme_constant_override("separation", -4)
	b.add_child(LazerStyle.label(cap, 12, LazerStyle.TEXT_MUTE))
	b.add_child(value)
	return b


func _show_lv(v: float) -> void:
	super._show_lv(v)
	_lv_l.add_theme_color_override("font_color", LazerStyle.level_color(v))   # 星の色(lazer の難易度の色)


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	# 閉じる動き: シートが下へ沈み、背景が明るさを戻す
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.2)
	t.tween_property(_panel, "position:y", 720.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())
