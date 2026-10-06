extends "res://scripts/ui/mod_panel.gd"
## lazer 風の MOD パネル: 画面の下からせり上がるシート。MOD は色の札(タイル)を並べ、押すと札が MOD の色に染まる。
## 札は「難しくする」「易しくする」「特殊」に分けて並べる。札には、MOD の絵・名前・要点(1 行)・ベーススコアの増減だけを出し、
## 詳しい効果は、カーソルを乗せた(なければ、最後に押した)札の分だけ、札の下の欄に出す。
## 右上に、選んでいる難易度の MOD 適用後 Lv と、ベーススコアの倍率(数字がなめらかに増減する)。下に「すべて解除」と「閉じる」。
## MOD の付け外し・数字の動き・キー操作(Esc / M で閉じる)・契約(setup / signal changed・closed / refresh_info / multi)は、
## classic(mod_panel.gd)のものをそのまま使う。札は ToggleCard と同じ決まり(meta の state / apply)を持つので、「すべて解除」もそのまま働く。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")

const SHEET_H := 524.0
const COLS := 4
const TILE_H := 76.0
const GAP := 14.0
const SIDE := 40.0
const GROUPS := [   # [id, 見出し, 見出しの色]
	["up", "難しくする", Color(1.0, 0.5, 0.45)],
	["down", "易しくする", Color(0.55, 0.92, 0.55)],
	["special", "特殊", Color(0.5, 0.8, 1.0)],
]

var _detail_name: Label
var _detail_text: Label
var _detail_bar: ColorRect
var _focus_id := ""          # 詳細欄に出している MOD(カーソルを外したあとは、最後に押した札)
var _last_pressed := ""
var _defs := {}              # id → MOD の定義


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
	var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.985), Color(0, 0, 0, 0), 0, 0, SIDE, 20)
	sb.border_color = LazerStyle.PINK
	sb.border_width_top = 3
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	# 上の段: 見出し(左)と、Lv・倍率(右)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 36)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(LazerStyle.label("MOD", 30, LazerStyle.TEXT, true))
	title_box.add_child(LazerStyle.label("難易度とスコアの修飾。複数つけると、効果も倍率も掛け算で重なります", 13, LazerStyle.TEXT_MUTE))
	head.add_child(title_box)
	_lv_l = LazerStyle.label("--", 38, LazerStyle.TEXT_MUTE, true)
	head.add_child(_stat_row("難易度  LV", _lv_l, 120.0))
	_mul_l = LazerStyle.label("×1.0000", 38, LazerStyle.TEXT, true)
	head.add_child(_stat_row("ベーススコア倍率", _mul_l, 170.0))
	# MOD の札(分類ごと)
	var groups := {}
	for m0 in Mods.ALL:
		_defs[m0.id] = m0
		if multi and bool(m0.get("solo", false)):
			continue
		var g: String = str(m0.get("group", "special"))
		if not groups.has(g):
			groups[g] = []
		groups[g].append(m0)
	var tiles_host := VBoxContainer.new()
	tiles_host.add_theme_constant_override("separation", 10)
	tiles_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tiles_host)
	var grids: Array = []   # [GridContainer, MOD の配列](札は、数枚ずつ数フレームに分けて作る)
	var tw := (1280.0 - SIDE * 2.0 - GAP * float(COLS - 1)) / float(COLS)   # 札 1 枚の幅
	if groups.has("up"):
		tiles_host.add_child(_group_section("up", groups.up, COLS, grids))
	var low := HBoxContainer.new()   # 易しくする(左)と特殊(右)は、同じ段に並べる
	low.add_theme_constant_override("separation", int(GAP))
	var low_n := 0
	for gid in ["down", "special"]:
		if not groups.has(gid):
			continue
		var n: int = groups[gid].size()
		var sec := _group_section(gid, groups[gid], n, grids)
		if gid == "special":
			sec.custom_minimum_size.x = tw * float(n) + GAP * float(n - 1)
		else:
			sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		low.add_child(sec)
		low_n += n
	if low_n > 0:
		tiles_host.add_child(low)
	_build_tiles_in(grids)   # 動きがあるときは、数枚ずつ数フレームに分けて作る(一度に作ると、押した瞬間に止まる)
	# 詳細欄: カーソルを乗せた札の、詳しい効果
	v.add_child(_build_detail())
	# 下の段: 「すべて解除」(左)と「閉じる」(右)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	v.add_child(foot)
	_clear_btn = LazerButton.new("すべて解除", LazerStyle.PURPLE, "retry", Color(0.1, 0.04, 0.22))
	_clear_btn.text = "すべて解除"
	_clear_btn.custom_minimum_size = Vector2(210, 44)
	_clear_btn.font_size = 16
	_clear_btn.pressed.connect(_clear_all)
	foot.add_child(_clear_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var done := LazerButton.new("閉じる", LazerStyle.PINK, "back", Color(0.2, 0.04, 0.11))
	done.text = "閉じる"
	done.custom_minimum_size = Vector2(210, 44)
	done.font_size = 16
	done.set_meta("juice_sound", "back")
	done.pressed.connect(close_panel)
	foot.add_child(done)
	_sync_clear_btn()
	_show_detail(_first_active())
	if UiStyle.animate:
		refresh_info.call_deferred(false)   # Lv の計算は、最初のフレームのあとへ(シートはまだ画面の外から上がってくる途中)
	else:
		refresh_info(false)
	UiStyle.close_on_outside_click(self, panel, close_panel)
	# 開く動き: 背景が暗くなり、シートが下からせり上がり、札が左上から順に現れる
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.6, 0.22)
	if UiStyle.animate:
		panel.position.y = 720.0
		create_tween().tween_property(panel, "position:y", 720.0 - SHEET_H, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 見出し(色の小さな印つき)と、その下の札の格子。札はここでは作らず、grids に控える。
func _group_section(gid: String, mods: Array, cols: int, grids: Array) -> VBoxContainer:
	var info: Array = GROUPS[0]
	for gi in GROUPS:
		if gi[0] == gid:
			info = gi
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = info[2]
	bar.custom_minimum_size = Vector2(4, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.add_child(bar)
	cap.add_child(LazerStyle.label(str(info[1]), 14, LazerStyle.TEXT_DIM, true))
	sec.add_child(cap)
	var grid := GridContainer.new()
	grid.columns = maxi(cols, 1)
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", 10)
	sec.add_child(grid)
	grids.append([grid, mods])
	return sec


const TILES_PER_FRAME := 3


## 札を作って並べる。動きがあるときは TILES_PER_FRAME 枚ずつ、フレームを分けて作り(札は作った順に、ふわっと現れる)、動きがないときは一度に作る。
func _build_tiles_in(grids: Array) -> void:
	var mods: Array = settings.mods
	var k := 0
	for gm in grids:
		var grid: GridContainer = gm[0]
		for m in gm[1]:
			var tile := _tile(m, mods.has(m.id), func(on: bool): _on_toggled(m.id, on))
			_cards[m.id] = tile
			grid.add_child(tile)
			if UiStyle.animate:
				UiStyle.tween(tile, "modulate:a", 0.0, 1.0, 0.24, 0.1 + 0.035 * k if k < TILES_PER_FRAME else 0.0)
				k += 1
				if k % TILES_PER_FRAME == 0:
					await get_tree().process_frame
					if not is_instance_valid(grid) or _closing:
						return


## MOD の札: 左に MOD の絵、右に「タグ(英字)+ 名前」「要点」「ベーススコアの増減」。付けると札が MOD の色に染まり、右上に印が付く。
func _tile(m: Dictionary, on: bool, on_toggle: Callable) -> PanelContainer:
	var c: Color = m.color
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(0, TILE_H)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var state := {"on": on, "k": 1.0 if on else 0.0, "hover": false, "glow": 0.0}
	var pad := StyleBoxEmpty.new()   # 面は下の draw で自分で描く(余白だけを決める)
	pad.content_margin_left = 12
	pad.content_margin_right = 34
	pad.content_margin_top = 8
	pad.content_margin_bottom = 8
	tile.add_theme_stylebox_override("panel", pad)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(h)
	var icon := Control.new()   # MOD の絵(色の丸の中)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func():
		var k: float = state.k
		var ic := icon.size * 0.5
		icon.draw_circle(ic, 22.0, Color(c.r, c.g, c.b, 0.12 + 0.2 * k))
		icon.draw_arc(ic, 21.0, 0.0, TAU, 28, Color(c.r, c.g, c.b, 0.25 + 0.5 * k), 1.4, true)
		LazerIcons.draw_icon(icon, "mod_" + str(m.id), ic, 11.5, c.lightened(0.15 * k).lerp(Color.WHITE, 0.25 * k), 1.8))
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var tag := LazerStyle.label(str(m.tag), 18, c, true)
	top.add_child(tag)
	var name_l := LazerStyle.label(str(m.name), 13, LazerStyle.TEXT_DIM, true)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(name_l)
	var short_l := LazerStyle.label(str(m.get("short", "")), 12, LazerStyle.TEXT_DIM)
	short_l.clip_text = true
	short_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	short_l.custom_minimum_size.x = 10
	v.add_child(short_l)
	var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
	var mul := LazerStyle.label("ベーススコア %+d%%" % pct, 11, Color(c.r, c.g, c.b, 0.9), true)
	v.add_child(mul)
	# 面と印は自分で描く(色の帯・染まり具合・右上の丸い印・押した瞬間の光の輪)
	var deco := tile
	deco.draw.connect(func():
		var k: float = state.k
		var r := Rect2(Vector2.ZERO, deco.size)
		var gl: float = state.glow
		if gl > 0.01:   # 付けた瞬間、縁から外へ広がって消える光の輪
			var grow := (1.0 - gl) * 10.0 + 2.0
			deco.draw_style_box(LazerStyle.box(Color(0, 0, 0, 0), Color(c.r, c.g, c.b, 0.6 * gl), 2, 12 + int(grow)), Rect2(r.position - Vector2(grow, grow), r.size + Vector2(grow, grow) * 2.0))
		var base := Color(1, 1, 1, 0.05 + (0.03 if state.hover else 0.0))
		deco.draw_style_box(LazerStyle.box(base.lerp(Color(c.r, c.g, c.b, 0.26), k), Color(c.r, c.g, c.b, 0.18 + 0.62 * k + (0.2 if state.hover else 0.0) * (1.0 - k)), 2 if k > 0.5 else 1, 12), r)
		deco.draw_style_box(LazerStyle.box(Color(c.r, c.g, c.b, 0.55 + 0.45 * k), Color(0, 0, 0, 0), 0, 2), Rect2(14, 0, deco.size.x - 28, 3))
		var mc := Vector2(deco.size.x - 20.0, 20.0)
		deco.draw_arc(mc, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25).lerp(c, k), 1.6, true)
		if k > 0.01:
			deco.draw_circle(mc, 9.0 * k, c)
			# 印のチェックは、描き込むように現れる(前半が短い線、後半が長い線)
			var p0 := mc + Vector2(-4, 0)
			var p1 := mc + Vector2(-1, 3.5)
			var p2 := mc + Vector2(4.5, -3.5)
			var f1 := clampf(k * 2.0, 0.0, 1.0)
			var f2 := clampf(k * 2.0 - 1.0, 0.0, 1.0)
			var ck := PackedVector2Array([p0, p0.lerp(p1, f1)])
			if f2 > 0.0:
				ck.append(p1.lerp(p2, f2))
			deco.draw_polyline(ck, Color(0.1, 0.05, 0.08, minf(1.0, k * 2.0)), 2.0, true))
	var apply := func():
		var to := 1.0 if state.on else 0.0
		tag.add_theme_color_override("font_color", c.lightened(0.25) if state.on else c)
		name_l.add_theme_color_override("font_color", LazerStyle.TEXT if state.on else LazerStyle.TEXT_DIM)
		short_l.add_theme_color_override("font_color", LazerStyle.TEXT if state.on else LazerStyle.TEXT_DIM)
		if UiStyle.animate and deco.is_inside_tree():
			var t := deco.create_tween()
			t.tween_method(func(x: float): state.k = x; deco.queue_redraw(); icon.queue_redraw(), float(state.k), to, 0.22)
		else:
			state.k = to
			deco.queue_redraw()
			icon.queue_redraw()
	apply.call()
	tile.mouse_entered.connect(func():
		state.hover = true
		deco.queue_redraw()
		_show_detail(str(m.id))
		UiSfx.play("hover", 0.95))
	tile.mouse_exited.connect(func():
		state.hover = false
		deco.queue_redraw()
		_show_detail(_last_pressed if _last_pressed != "" else _first_active())
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
		if state.on and UiStyle.animate and deco.is_inside_tree():   # 光の輪
			var gt := deco.create_tween()
			gt.tween_method(func(x: float): state.glow = x; deco.queue_redraw(), 1.0, 0.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_last_pressed = str(m.id)
		_show_detail(_last_pressed)
		UiSfx.play("on" if state.on else "off")
		on_toggle.call(state.on))
	tile.set_meta("state", state)
	tile.set_meta("apply", apply)
	return tile


## 札の下の詳細欄(左に MOD の色の帯、名前、効果の全文)。
func _build_detail() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, 52)
	box.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.08), 1, 10, 0, 0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	box.add_child(h)
	_detail_bar = ColorRect.new()
	_detail_bar.custom_minimum_size = Vector2(5, 0)
	_detail_bar.color = Color(1, 1, 1, 0.0)
	h.add_child(_detail_bar)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(pad)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 16)
	pad.add_child(hh)
	_detail_name = LazerStyle.label("", 16, LazerStyle.TEXT, true)
	_detail_name.custom_minimum_size.x = 150
	_detail_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hh.add_child(_detail_name)
	_detail_text = LazerStyle.label("", 13, LazerStyle.TEXT_DIM)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hh.add_child(_detail_text)
	return box


## 付けている MOD のうち、最初のもの(なければ空)。
func _first_active() -> String:
	for id in settings.mods:
		if _defs.has(id):
			return str(id)
	return ""


## 詳細欄に id の MOD を出す(空なら、何も出さない)。
func _show_detail(id: String) -> void:
	if _detail_name == null or id == _focus_id:
		return
	_focus_id = id
	if id == "" or not _defs.has(id):
		_detail_name.text = ""
		_detail_text.text = ""
		_detail_bar.color = Color(1, 1, 1, 0.0)
		return
	var m: Dictionary = _defs[id]
	var effects: Array = []
	for p in (m.desc as String).split(" / "):
		if not p.begins_with("ベーススコア"):
			effects.append(p)
	_detail_name.text = "%s  %s" % [m.name, m.tag]
	_detail_name.add_theme_color_override("font_color", (m.color as Color).lightened(0.2))
	_detail_text.text = "   ・   ".join(effects)
	_detail_bar.color = m.color
	UiStyle.tween(_detail_text, "modulate:a", 0.35, 1.0, 0.18)


func _sync_clear_btn() -> void:
	super._sync_clear_btn()
	if _clear_btn != null:
		_clear_btn.queue_redraw()


## 見出し(小さな文字)と、その下の大きな数字の段(右の段)。
func _stat_row(cap: String, value: Label, width: float) -> Control:
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
