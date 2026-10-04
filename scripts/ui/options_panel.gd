extends Control
## 設定パネル(選曲画面の上に重ねる)。操作 / 音 / 画面 / 曲 / その他 の 5 セクション(MOD は、難易度選択画面の MOD ボタンから)。
## 使う順に並べてある: 操作(マウスが標準)→ 音(音量とオフセット)→ 画面(ウィンドウの大きさが先頭)→ 曲(osu! の Songs フォルダ)→ その他(更新・ファイルの関連付け)。
## 右上の ✕、パネルの外のクリック、左下の「閉じる」、Esc で閉じる。
## settings(Settings.load_all の辞書)を直接書き換え、変えたら changed(kind) を出す。保存は閉じるときに呼び出し側が行う。
##   kind: "volume" | "control" | "misc" | "songs"(osu! の Songs フォルダの使う・使わない・場所が変わった)

signal changed(kind: String)
signal closed

const Settings = preload("res://scripts/settings.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Volume = preload("res://scripts/volume.gd")
const FileAssoc = preload("res://scripts/file_assoc.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const ToggleCard = preload("res://scripts/ui/toggle_card.gd")
const FpsOverlay = preload("res://scripts/ui/fps_overlay.gd")

const SECTIONS := ["操作", "音", "画面", "曲", "その他"]

var settings: Dictionary

var _pages: Array = []
var _nav: Array = []
var _size_label: Label
var _size_btns: Array = []
var _fullscreen_btn: Button
var _dim: ColorRect
var _panel: PanelContainer
var _closing := false
var _nav_ind: Panel          # 選択中の項目の下で、上下に滑る枠
var _nav_holder: Control
var _nav_tween: Tween
var _cur := -1               # 表示中のセクション


func setup(p_settings: Dictionary) -> void:
	settings = p_settings


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
	_pages = [_build_control(), _build_audio(), _build_screen(), _build_songs(), _build_other()]
	for p in _pages:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	var x_btn := UiStyle.close_button(close_panel)   # 右上の ✕(ページの見出しの行の右端)
	x_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	x_btn.offset_left = -38.0
	x_btn.offset_bottom = 36.0
	stack.add_child(x_btn)
	UiStyle.close_on_outside_click(self, panel, close_panel)

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
			if not c is CanvasItem:
				continue
			UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.3, 0.03 * j)
			j += 1
	_move_nav_indicator(prev < 0)
	if i == 2:
		refresh_size()


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


## トグルのカード(toggle_card.gd)。on_toggle(新しい状態) を呼ぶ。
func _toggle_card(title: String, lines: String, color: Color, on: bool, right_text: String, on_toggle: Callable) -> PanelContainer:
	return ToggleCard.make(self, title, lines, color, on, right_text, on_toggle)


func _set_toggle(c: PanelContainer, on: bool) -> void:
	ToggleCard.set_on(c, on)


## スライダー 1 行: 見出し + スライダー + 値。値の表示は fmt(値) -> String。幅(見出し・スライダー・値)は、行の合計が 669px に収まる範囲で変えられる。
func _slider_row(parent: Control, cap: String, lo: float, hi: float, step: float, value: float, fmt: Callable, cap_w := 170.0, slider_w := 380.0, val_w := 90.0) -> HSlider:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UiStyle.label(cap, 15, UiStyle.TEXT)
	l.custom_minimum_size = Vector2(cap_w, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(slider_w, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	h.add_child(s)
	var v := UiStyle.label(fmt.call(value), 15, UiStyle.ACCENT)
	v.custom_minimum_size = Vector2(val_w, 0)
	h.add_child(v)
	s.value_changed.connect(func(x: float):
		v.text = fmt.call(x)
		if v.is_visible_in_tree():   # 値の文字が、変わるたびにぴょこっと跳ねる
			v.pivot_offset = Vector2(0.0, v.size.y * 0.5)
			UiStyle.spring(v, "scale", Vector2(1.18, 1.18), Vector2.ONE, 0.3))
	parent.add_child(h)
	return s


# --- 各セクション ---

func _build_control() -> Control:
	var v := _page("操作", "")
	var refs := {}   # ラムダは変数を値で捕まえるので、互いに参照する 2 枚のカードは辞書経由にする
	# 感度はマウスのときだけ効くので、キーボードのときは薄くして触れなくする
	var sync_sens := func():
		var mouse: bool = settings.control == "mouse"
		for c in refs.sens_row.get_children():   # (行そのものの透明度は、ページを開くときのフェードが使う)
			c.modulate.a = 1.0 if mouse else 0.35
		refs.sens.editable = mouse
	refs.ms = _toggle_card("マウス", "", UiStyle.ACCENT, settings.control == "mouse", "",   # 標準の操作なので先頭
		func(on: bool):
			if not on:
				_set_toggle(refs.ms, true)   # 必ずどちらか 1 つ
			_set_toggle(refs.kb, false)
			settings.control = "mouse"
			sync_sens.call()
			changed.emit("control"))
	refs.kb = _toggle_card("キーボード", "", UiStyle.ACCENT, settings.control != "mouse", "",
		func(on: bool):
			if not on:
				_set_toggle(refs.kb, true)
			_set_toggle(refs.ms, false)
			settings.control = "keyboard"
			sync_sens.call()
			changed.emit("control"))
	v.add_child(refs.ms)
	v.add_child(refs.kb)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	v.add_child(gap)
	var s := _slider_row(v, "マウス感度", 0.3, 3.0, 0.1, float(settings.mouse_sens), func(x): return "×%.1f" % x)
	s.value_changed.connect(func(x: float):
		settings.mouse_sens = x
		changed.emit("misc"))
	refs.sens = s
	refs.sens_row = s.get_parent()
	sync_sens.call()
	return v


func _build_audio() -> Control:
	var v := _page("音", "")
	var a := _slider_row(v, "全体音量", 0, 100, 5, float(settings.volume), func(x): return "%d%%" % int(x))
	a.value_changed.connect(func(x: float):
		settings.volume = int(x)
		Settings.apply_volume(x)
		changed.emit("volume"))
	var m := _slider_row(v, "音楽", 0, 100, 5, float(settings.music_volume), func(x): return "%d%%" % int(x))   # 全体 → 音楽 → 効果音(ホイールのメーター・ポーズと同じ並び)
	m.value_changed.connect(func(x: float):
		settings.music_volume = int(x)
		Volume.set_music(x)
		changed.emit("volume"))
	var b := _slider_row(v, "効果音", 0, 100, 5, float(settings.sfx_volume), func(x): return "%d%%" % int(x))
	b.value_changed.connect(func(x: float):
		settings.sfx_volume = int(x)
		Volume.set_sfx(x)
		changed.emit("volume"))
	# 音と弾のタイミング校正(音に関わる設定なので、ここに置く)。+ で弾が遅れる、− で早まる
	var gap_o := Control.new()
	gap_o.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap_o)
	var o := _slider_row(v, "オフセット", -300, 300, 5, float(settings.offset_ms), func(x):
		return "%+d ms%s" % [int(x), "   弾が遅れる" if x > 0.0 else ("   弾が早まる" if x < 0.0 else "")], 170.0, 300.0, 180.0)   # 見出しの幅は他の行と同じ(スライダーの左端をそろえる)
	o.value_changed.connect(func(x: float):
		settings.offset_ms = int(x)
		changed.emit("misc"))
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


func _build_screen() -> Control:
	var v := _page("画面", "")
	v.add_child(UiStyle.label("解像度(ウィンドウの大きさ)", 16, UiStyle.TEXT, true))   # いちばん触る項目なので先頭
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for sz in Settings.WINDOW_SIZES:
		var b := Button.new()
		b.text = "%d × %d" % [sz.x, sz.y]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 34)
		var size: Vector2i = sz
		b.pressed.connect(func():
			settings.window_size = "%dx%d" % [size.x, size.y]
			Settings.apply_window_size(size)
			refresh_size.call_deferred())
		b.set_meta("size", size)
		seg.add_child(b)
		_size_btns.append(b)
	var fs_btn := Button.new()
	fs_btn.text = "全画面"
	fs_btn.toggle_mode = true
	fs_btn.button_group = group
	fs_btn.focus_mode = Control.FOCUS_NONE
	fs_btn.custom_minimum_size = Vector2(130, 34)
	fs_btn.pressed.connect(func():
		settings.window_size = "fullscreen"
		Settings.apply_fullscreen()
		refresh_size.call_deferred())
	seg.add_child(fs_btn)
	_fullscreen_btn = fs_btn
	v.add_child(seg)
	_size_label = UiStyle.label("", 13, UiStyle.TEXT_DIM)
	v.add_child(_size_label)
	var hint := UiStyle.label("ウィンドウの枠をドラッグして、好きな大きさにもできます(縦横の比は保たれ、余白は黒くなります)。", 12, UiStyle.TEXT_FAINT)
	hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(hint)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(_toggle_card("垂直同期", "画面の更新に合わせて描きます(ずれ・ちぎれを抑える)。切ると遅延が少し減りますが、ずれが出ることがあります", UiStyle.ACCENT,
		bool(settings.vsync), "", func(on: bool):
			settings.vsync = on
			Settings.apply_vsync(on)))
	# UI の見た目(クラシック / lazer 風など)。選んだあと、設定を閉じると、いまのタイトル・選曲画面から切り替わる
	var gap_u := Control.new()
	gap_u.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap_u)
	v.add_child(UiStyle.label("UI の見た目", 16, UiStyle.TEXT, true))
	var ui_sets = load("res://scripts/ui/ui_sets.gd")   # (preload だと、UI セット ↔ このパネルが循環するので、使うときに読む)
	var ui_seg := HBoxContainer.new()
	ui_seg.add_theme_constant_override("separation", 8)
	var ui_group := ButtonGroup.new()
	for id in ui_sets.ids():
		var ub := Button.new()
		ub.text = str(ui_sets.get_set(id).display_name())
		ub.toggle_mode = true
		ub.button_group = ui_group
		ub.focus_mode = Control.FOCUS_NONE
		ub.custom_minimum_size = Vector2(150, 34)
		ub.set_pressed_no_signal(str(settings.get("ui_style", "classic")) == id)
		var ui_id: String = id
		ub.pressed.connect(func():
			settings.ui_style = ui_id
			changed.emit("ui_style"))
		ui_seg.add_child(ub)
	v.add_child(ui_seg)
	var ui_gap := Control.new()
	ui_gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(ui_gap)
	v.add_child(_toggle_card("目に優しい表示", "プレイ画面の弾の色を落ち着かせ、白い芯・予兆の点滅・キアイの拍の光を弱めます(弾の位置・当たり判定・難易度は変わりません)。弾が多いときの、目のチカチカが気になる方向け", UiStyle.ACCENT,
		bool(settings.get("eye_comfort", true)), "", func(on: bool):
			settings.eye_comfort = on))
	v.add_child(_toggle_card("FPS を表示", "画面の右下に、描画と処理の FPS を出します(プレイ中は、弾の判定の計算回数も出ます)", UiStyle.ACCENT,
		FpsOverlay.enabled, "", func(on: bool):
			settings.show_fps = on
			FpsOverlay.enabled = on))
	return v


## いまのウィンドウの大きさを表示し、候補のうち同じ大きさのものを選んだ状態にする。画面に入らない候補は押せなくする。F11 で変わったときも main が呼ぶ。
func refresh_size() -> void:
	if _size_label == null:
		return
	var cur := DisplayServer.window_get_size()
	var mode := DisplayServer.window_get_mode()
	_size_label.text = "現在  %d × %d%s" % [cur.x, cur.y, "(全画面)" if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN else ""]
	var full: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	for b in _size_btns:
		var sz: Vector2i = b.get_meta("size")
		b.set_pressed_no_signal(sz == cur and not full)
		b.disabled = not Settings.size_fits(sz)
	_fullscreen_btn.set_pressed_no_signal(full)


## 曲: osu! の Songs フォルダ(osu!stable が展開した曲を、コピーせずに一覧へ加える)。使うかどうか + 場所(空なら自動で探す)+ 今の状態。
func _build_songs() -> Control:
	var box := _page("曲", "")
	var st := UiStyle.label("", 13, UiStyle.TEXT_DIM)
	st.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var choose := Button.new()
	choose.text = "フォルダを選ぶ…"
	choose.focus_mode = Control.FOCUS_NONE
	var auto := Button.new()
	auto.text = "自動で探す"
	auto.focus_mode = Control.FOCUS_NONE
	var refresh := func():
		var on: bool = bool(settings.get("osu_songs", false))
		choose.disabled = not on
		auto.disabled = not on or str(settings.get("osu_songs_dir", "")) == ""
		if not on:
			st.text = ""
		elif SongLibrary.osu_dir == "":
			st.text = "osu! の Songs フォルダが見つかりません。「フォルダを選ぶ…」で、osu! の Songs フォルダを指定してください。"
		else:
			var pr := SongLibrary.warm_progress()   # 裏で調べている。待たずに、いまの進み具合を出す
			st.text = "使うフォルダ: %s\n%s" % [SongLibrary.osu_dir, ("準備しています… %d / %d(選曲画面は、できた曲から順に出ます)" % [pr.done, pr.total]) if pr.running else ("%d 曲" % SongLibrary.ready_count())]
	var apply := func():
		SongLibrary.apply_osu_settings(settings)
		SongLibrary.start_osu_warmup()   # 曲の索引を裏で作る(選曲画面を開いたときに待たせない)
		refresh.call()
		changed.emit("songs")
	box.add_child(_toggle_card("osu! の Songs フォルダの曲を使う", "osu!(osu!stable)に入っている曲を、コピーせずにそのまま選曲画面に加えます(曲が多いときは、裏で準備して、できた曲から順に選曲画面へ出します)。ふつうは自動で見つかります", UiStyle.ACCENT,
		bool(settings.get("osu_songs", false)), "", func(on: bool):
			settings.osu_songs = on
			apply.call()))
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.dir_selected.connect(func(d: String):
		settings.osu_songs_dir = d.replace("\\", "/")
		apply.call())
	add_child(dialog)   # ページの中には入れない(ページを開く動きは、中の子すべてに透明度の動きをつけるため、画面の部品でないものがあると壊れる)
	choose.pressed.connect(func(): dialog.popup_centered_ratio(0.7))
	auto.pressed.connect(func():
		settings.osu_songs_dir = ""
		apply.call())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(choose)
	row.add_child(auto)
	box.add_child(row)
	box.add_child(st)
	refresh.call()
	var tick := Timer.new()   # 準備の進み具合を、ときどき更新する
	tick.wait_time = 0.5
	tick.autostart = true
	tick.timeout.connect(func(): if _cur == 3 and bool(settings.get("osu_songs", false)): refresh.call())
	add_child(tick)
	return box


func _build_other() -> Control:
	var v := _page("その他", "")
	# 更新の確認
	v.add_child(_toggle_card("起動時に更新を確認する", "新しいバージョンがあれば、タイトル画面でお知らせします(GitHub に問い合わせます)", UiStyle.ACCENT,
		bool(settings.check_update), "", func(on: bool): settings.check_update = on))
	v.add_child(_toggle_card("見つけたら自動で更新する", "新しいバージョンが見つかったら、起動したタイトル画面で、ダウンロードして入れ替え、再起動します(書き出した版のみ。曲や設定はそのまま)", UiStyle.ACCENT,
		bool(settings.auto_update), "", func(on: bool): settings.auto_update = on))
	# 弾速の実験(開発用のデータ集め。scripts/speed_study.gd)
	v.add_child(_toggle_card("弾速の実験に参加する", "ひとりで遊ぶとき、弾の速さなどを少し変えた弾幕になることがあります(どれになったかはプレイ中は出ません)。結果は、難易度の計算を確かめるために記録します(user://speed_study.csv。外には送りません)。弾幕に効く MOD を付けているときは、ふだんどおりです", UiStyle.ACCENT,
		bool(settings.get("speed_study", false)), "", func(on: bool): settings.speed_study = on))
	# .osz を開くとき(Windows)。このアプリの関連付け(書き出した版のみ。既定のアプリは、Windows の設定で選ぶ)
	if FileAssoc.supported():
		var gap_a := Control.new()
		gap_a.custom_minimum_size = Vector2(0, 8)
		v.add_child(gap_a)
		v.add_child(UiStyle.label(".osz ファイルを開いたとき", 16, UiStyle.TEXT, true))
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
			var hint := UiStyle.label("Windows は、アプリが勝手に既定のアプリを変えることを認めていません。追加したあと「既定のアプリの設定を開く」で、「.osz」を検索して Danmaku を選んでください(または .osz を右クリック →「プログラムから開く」→ Danmaku →「常に使う」)。", 12, UiStyle.TEXT_FAINT)
			hint.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			v.add_child(hint)
			v.add_child(st)
	return v
