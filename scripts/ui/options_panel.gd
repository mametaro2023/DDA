extends Control
## 設定パネル(選曲画面の上に重ねる)。MOD / 操作 / 音 / ゲーム の 4 セクション。
## settings(Settings.load_all の辞書)を直接書き換え、変えたら changed(kind) を出す。保存は閉じるときに呼び出し側が行う。
##   kind: "mods" | "volume" | "control" | "misc"

signal changed(kind: String)
signal closed

const Mods = preload("res://scripts/mods.gd")
const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const FileAssoc = preload("res://scripts/file_assoc.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")

const SECTIONS := ["MOD", "操作", "音", "ゲーム"]

var settings: Dictionary
## MOD 適用後の Lv のプレビュー文(選択中の難易度)を返す Callable(-> String)
var preview: Callable = Callable()

var _pages: Array = []
var _nav: Array = []
var _mod_cards := {}
var _mod_summary: Label
var _mod_preview: Label
var _dim: ColorRect
var _panel: PanelContainer
var _closing := false
var _nav_ind: Panel          # 選択中の項目の下で、上下に滑る枠
var _nav_holder: Control
var _nav_tween: Tween
var _cur := -1               # 表示中のセクション


func setup(p_settings: Dictionary, p_preview: Callable) -> void:
	settings = p_settings
	preview = p_preview


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
	panel.position = Vector2(150, 36)
	panel.size = Vector2(980, 648)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 0, 0))
	add_child(panel)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)

	# 左: セクション見出し
	var nav_box := VBoxContainer.new()
	nav_box.custom_minimum_size = Vector2(210, 0)
	nav_box.add_theme_constant_override("separation", 6)
	var nav_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		nav_margin.add_theme_constant_override("margin_" + side, 22)
	nav_margin.add_child(nav_box)
	_nav_holder = Control.new()   # 枠(_nav_ind)を、ボタンの下で自由に動かすための入れもの
	_nav_holder.custom_minimum_size = Vector2(254, 0)
	_nav_ind = Panel.new()
	_nav_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ia := UiStyle.ACCENT
	var ind_style := UiStyle.box(Color(ia.r, ia.g, ia.b, 0.14), Color(ia.r, ia.g, ia.b, 0.8), 1, 4)
	ind_style.border_width_left = 3
	_nav_ind.add_theme_stylebox_override("panel", ind_style)
	_nav_ind.visible = false
	_nav_holder.add_child(_nav_ind)
	nav_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nav_holder.add_child(nav_margin)
	root.add_child(_nav_holder)
	nav_box.add_child(UiStyle.label("OPTIONS", 22, UiStyle.TEXT, true))
	nav_box.add_child(UiStyle.caption("設定"))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	nav_box.add_child(sp)
	var group := ButtonGroup.new()
	for i in range(SECTIONS.size()):
		var b := Button.new()
		b.text = SECTIONS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for st in ["pressed", "hover_pressed"]:   # 選択の面は、滑る枠が描く(ボタン自身は文字の色だけ)
			b.add_theme_stylebox_override(st, UiStyle.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 16, 8))
		b.set_meta("juice_sound", "select")
		b.pressed.connect(func(): _show(i))
		nav_box.add_child(b)
		_nav.append(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_box.add_child(fill)
	var close := Button.new()
	close.text = "閉じる"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	nav_box.add_child(close)
	var vline := ColorRect.new()
	vline.color = UiStyle.LINE
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
	_pages = [_build_mods(), _build_control(), _build_audio(), _build_game()]
	for p in _pages:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)

	_show(0)
	# 開く動き: 背景が暗くなり、パネルが下からふわっと上がる
	UiSfx.play("open")
	UiStyle.tween(_dim, "color:a", 0.0, 0.66, 0.22)
	UiStyle.pop_scale(panel, 0.93, 0.42)
	for k in range(_nav.size()):   # 項目が上から順に、弾んで現れる(コンテナの中なので、位置ではなく大きさで動かす)
		UiStyle.pop_scale(_nav[k], 0.88, 0.4, 0.12 + 0.05 * k)


func show_section(i: int) -> void:
	_show(clampi(i, 0, SECTIONS.size() - 1))


func _show(i: int) -> void:
	var changed_page: bool = not _pages[i].visible
	var dir := 1 if i >= _cur else -1
	var prev := _cur
	_cur = i
	for k in range(_pages.size()):
		_pages[k].visible = (k == i)
		_nav[k].set_pressed_no_signal(k == i)
	if changed_page and _panel != null and _panel.is_inside_tree():
		# セクションを切り替えると、ページは進む向きから滑り込み、中身が上から順にふわっと現れる
		if prev >= 0:
			UiStyle.slide_page(_pages[i], 30.0 * dir)
		var j := 0
		for c in _pages[i].get_children():
			UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.3, 0.03 * j)
			j += 1
	_move_nav_indicator(prev < 0)
	if i == 0:
		refresh_mod_info()


## 選択の枠を、選んだ項目の位置へ動かす(行き過ぎてから戻る。最初だけ、レイアウトが決まってから、その場に置く)。
func _move_nav_indicator(first: bool) -> void:
	if first or not _nav_holder.is_inside_tree() or _nav[_cur].size == Vector2.ZERO:
		await get_tree().process_frame
		if not is_instance_valid(_nav_ind) or _cur < 0:
			return
		_place_nav_indicator(false)
		_nav_ind.visible = true
		UiStyle.tween(_nav_ind, "modulate:a", 0.0, 1.0, 0.3, 0.1)
		return
	_place_nav_indicator(true)


func _place_nav_indicator(animated: bool) -> void:
	var b: Control = _nav[_cur]
	var to := b.global_position - _nav_holder.global_position
	_nav_ind.size = b.size
	if _nav_tween != null and _nav_tween.is_valid():
		_nav_tween.kill()
	if not animated or not UiStyle.animate:
		_nav_ind.position = to
		return
	UiSfx.play("select", UiSfx.scale_pitch(float(_cur) / 4.0, 1.0))
	_nav_tween = _nav_ind.create_tween()
	_nav_tween.tween_property(_nav_ind, "position", to, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	match event.keycode:
		KEY_ESCAPE, KEY_O:
			close_panel()
		KEY_TAB:
			var cur := 0
			for k in range(_pages.size()):
				if _pages[k].visible:
					cur = k
			_show((cur + (-1 if event.shift_pressed else 1) + _pages.size()) % _pages.size())


# --- 共通の部品 ---

func _page(title: String, sub: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiStyle.label(title, 24, UiStyle.TEXT, true))
	if sub != "":
		v.add_child(UiStyle.label(sub, 13, UiStyle.TEXT_DIM))
	v.add_child(UiStyle.hline())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	return v


## トグルのカード。タイトル・説明・(任意の)右端の文字。on_toggle(新しい状態) を呼ぶ。
func _toggle_card(title: String, lines: String, color: Color, on: bool, right_text: String, on_toggle: Callable) -> PanelContainer:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"on": on}
	var ind := PanelContainer.new()
	ind.custom_minimum_size = Vector2(18, 18)
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var apply := func():
		var s := state.on as bool
		c.add_theme_stylebox_override("panel", UiStyle.box(Color(color.r, color.g, color.b, 0.10 if s else 0.035),
			Color(color.r, color.g, color.b, 0.8 if s else 0.09), 1, 6, 16, 12))
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
	col.add_child(UiStyle.label(title, 18, color, true))
	if lines != "":
		var l := UiStyle.label(lines, 13, UiStyle.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		col.add_child(l)
	h.add_child(col)
	if right_text != "":
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
			UiFx.burst(self, ind.get_global_rect().get_center() - global_position, color, 9, 120.0, 0.5, 2.6)
		on_toggle.call(state.on))
	# 外から見た目を更新できるように、状態をメタに持たせる
	c.set_meta("state", state)
	c.set_meta("apply", apply)
	return c


func _set_toggle(c: PanelContainer, on: bool) -> void:
	c.get_meta("state").on = on
	c.get_meta("apply").call()


## スライダー 1 行: 見出し + スライダー + 値。値の表示は fmt(値) -> String。
func _slider_row(parent: Control, cap: String, lo: float, hi: float, step: float, value: float, fmt: Callable) -> HSlider:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UiStyle.label(cap, 15, UiStyle.TEXT)
	l.custom_minimum_size = Vector2(170, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(380, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var v := UiStyle.label(fmt.call(value), 15, UiStyle.ACCENT)
	v.custom_minimum_size = Vector2(90, 0)
	h.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = fmt.call(x)
		if v.is_visible_in_tree():   # 値の文字が、変わるたびにぴょこっと跳ねる
			v.pivot_offset = Vector2(0.0, v.size.y * 0.5)
			UiStyle.spring(v, "scale", Vector2(1.18, 1.18), Vector2.ONE, 0.3))
	parent.add_child(h)
	return s


# --- 各セクション ---

func _build_mods() -> Control:
	var v := _page("MOD", "")
	var mods: Array = settings.mods
	# カードが増えても合計表示が隠れないよう、カード一覧だけをスクロールにする
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for m in Mods.ALL:
		var parts: PackedStringArray = (m.desc as String).split(" / ")
		var effects: Array = []
		for p in parts:
			if not p.begins_with("ベーススコア"):
				effects.append(p)
		var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
		var card := _toggle_card("%s   %s" % [m.name, m.tag], "  /  ".join(effects), m.color, mods.has(m.id), "ベーススコア %+d%%" % pct,
			func(on: bool): _on_mod_toggled(m.id, on))
		list.add_child(card)
		_mod_cards[m.id] = card
	v.add_child(UiStyle.hline())
	_mod_summary = UiStyle.label("", 16, UiStyle.TEXT)
	v.add_child(_mod_summary)
	_mod_preview = UiStyle.label("", 14, UiStyle.TEXT_DIM)
	v.add_child(_mod_preview)
	return v


func _on_mod_toggled(id: String, on: bool) -> void:
	var mods: Array = settings.mods
	if on and not mods.has(id):
		mods.append(id)
	elif not on:
		mods.erase(id)
	settings.mods = mods
	changed.emit("mods")
	refresh_mod_info()


## 合計ベーススコアと、選択中の難易度の MOD 適用後 Lv を更新する。
func refresh_mod_info() -> void:
	if _mod_summary == null:
		return
	var p := Mods.params(settings.mods)
	if p.ids.is_empty():
		_mod_summary.text = "MOD なし     ベーススコア 1,000,000"
	else:
		_mod_summary.text = "合計  ベーススコア ×%.4f  =  %s" % [p.score_mul, UiStyle.fmt(int(round(1000000.0 * p.score_mul)))]
	_mod_preview.text = preview.call() if preview.is_valid() else ""


func _build_control() -> Control:
	var v := _page("操作", "")
	var refs := {}   # ラムダは変数を値で捕まえるので、互いに参照する 2 枚のカードは辞書経由にする
	refs.kb = _toggle_card("キーボード", "", UiStyle.ACCENT, settings.control != "mouse", "",
		func(on: bool):
			if not on:
				_set_toggle(refs.kb, true)   # 必ずどちらか 1 つ
			_set_toggle(refs.ms, false)
			settings.control = "keyboard"
			changed.emit("control"))
	refs.ms = _toggle_card("マウス", "", UiStyle.ACCENT, settings.control == "mouse", "",
		func(on: bool):
			if not on:
				_set_toggle(refs.ms, true)
			_set_toggle(refs.kb, false)
			settings.control = "mouse"
			changed.emit("control"))
	v.add_child(refs.kb)
	v.add_child(refs.ms)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	var s := _slider_row(v, "マウス感度", 0.3, 3.0, 0.1, float(settings.mouse_sens), func(x): return "×%.1f" % x)
	s.value_changed.connect(func(x: float):
		settings.mouse_sens = x
		changed.emit("misc"))
	return v


func _build_audio() -> Control:
	var v := _page("音", "")
	var a := _slider_row(v, "全体音量", 0, 100, 5, float(settings.volume), func(x): return "%d%%" % int(x))
	a.value_changed.connect(func(x: float):
		settings.volume = int(x)
		Settings.apply_volume(x)
		changed.emit("volume"))
	var b := _slider_row(v, "効果音", 0, 100, 5, float(settings.sfx_volume), func(x): return "%d%%" % int(x))
	b.value_changed.connect(func(x: float):
		settings.sfx_volume = int(x)
		Volume.set_sfx(x)
		changed.emit("volume"))
	var m := _slider_row(v, "音楽", 0, 100, 5, float(settings.music_volume), func(x): return "%d%%" % int(x))
	m.value_changed.connect(func(x: float):
		settings.music_volume = int(x)
		Volume.set_music(x)
		changed.emit("volume"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(_toggle_card("UI の音", "ボタンに触れたとき・選んだとき・パネルを開いたときなどの小さな音(音量は「効果音」に従います)", UiStyle.ACCENT,
		bool(settings.ui_sound), "", func(on: bool):
			settings.ui_sound = on
			UiSfx.enabled = on
			if on:
				UiSfx.play("on")))
	return v


func _build_game() -> Control:
	var v := _page("ゲーム", "")
	var o := _slider_row(v, "オフセット", -300, 300, 5, float(settings.offset_ms), func(x): return "%+d ms" % int(x))
	o.value_changed.connect(func(x: float):
		settings.offset_ms = int(x)
		changed.emit("misc"))
	# 更新の確認
	var gap_u := Control.new()
	gap_u.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap_u)
	v.add_child(_toggle_card("起動時に更新を確認する", "新しいバージョンがあれば、タイトル画面でお知らせします(GitHub に問い合わせます)", UiStyle.ACCENT,
		bool(settings.check_update), "", func(on: bool): settings.check_update = on))
	# .osz を開くとき(Windows)。開いたときの動き + このアプリの関連付け(書き出した版のみ。既定のアプリは、Windows の設定で選ぶ)
	if FileAssoc.supported():
		var gap_a := Control.new()
		gap_a.custom_minimum_size = Vector2(0, 8)
		v.add_child(gap_a)
		v.add_child(UiStyle.label(".osz ファイルを開いたとき", 16, UiStyle.TEXT, true))
		var seg := HBoxContainer.new()
		seg.add_theme_constant_override("separation", 8)
		var group := ButtonGroup.new()
		for m in [["ask", "毎回選ぶ"], ["dda", "このアプリで開く"], ["osu", "osu! で開く"]]:
			var b := Button.new()
			b.text = m[1]
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(150, 34)
			b.button_pressed = str(settings.osz_open) == m[0]
			var mode: String = m[0]
			b.pressed.connect(func(): settings.osz_open = mode)
			seg.add_child(b)
		v.add_child(seg)
		if OS.has_feature("template"):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var st := UiStyle.label("", 13, UiStyle.TEXT_DIM)
			var reg := Button.new()
			reg.focus_mode = Control.FOCUS_NONE
			var refresh := func():
				var on := FileAssoc.is_registered(OS.get_executable_path())
				reg.text = "「プログラムから開く」に追加済み" if on else "「プログラムから開く」に追加"
				reg.disabled = on
			refresh.call()
			reg.pressed.connect(func():
				var ok := FileAssoc.register(OS.get_executable_path())
				refresh.call()
				st.text = "" if ok else "登録できませんでした")
			row.add_child(reg)
			var dflt := Button.new()
			dflt.text = "既定のアプリの設定を開く"
			dflt.focus_mode = Control.FOCUS_NONE
			dflt.pressed.connect(FileAssoc.open_default_apps)
			row.add_child(dflt)
			v.add_child(row)
			var hint := UiStyle.label("Windows は、アプリが勝手に既定のアプリを変えることを認めていません。追加したあと「既定のアプリの設定を開く」で、「.osz」を検索して DDA を選んでください(または .osz を右クリック →「プログラムから開く」→ DDA →「常に使う」)。", 12, UiStyle.TEXT_FAINT)
			hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			v.add_child(hint)
			v.add_child(st)
	return v
