extends RefCounted
## UI の共通スタイル(色・部品・Theme)。メニュー・設定・ポーズ・リザルトで共有する。
## 方針: 暗い背景 / 細い線 / 水色のアクセント(プレイ中の HUD と揃える)。点滅・フラッシュは使わない。

const BG := Color(0.03, 0.035, 0.06)
const PANEL := Color(0.055, 0.065, 0.1, 1.0)
const LINE := Color(1, 1, 1, 0.12)
const ACCENT := Color(0.42, 0.95, 1.0)
const TEXT := Color(1, 1, 1, 0.92)
const TEXT_DIM := Color(1, 1, 1, 0.58)
const TEXT_FAINT := Color(1, 1, 1, 0.36)
const DANGER := Color(1.0, 0.4, 0.42)
const GOLD := Color(1.0, 0.88, 0.4)
const GOOD := Color(0.5, 1.0, 0.7)

## 難易度(Lv)の色の停留点。Lv に応じて連続的に変わる。
const LEVEL_STOPS := [
	[1.0, Color(0.45, 0.85, 1.0)], [3.0, Color(0.5, 1.0, 0.7)], [5.0, Color(1.0, 0.9, 0.45)],
	[7.0, Color(1.0, 0.55, 0.4)], [9.0, Color(1.0, 0.4, 0.62)], [12.0, Color(0.8, 0.45, 1.0)],
]

static var _bold: FontVariation


static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.35
	return _bold


## 角丸の四角。margin は内側の余白(横, 縦)。
static func box(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := 4, mh := 0.0, mv := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mh
	s.content_margin_right = mh
	s.content_margin_top = mv
	s.content_margin_bottom = mv
	return s


static func level_color(lv: float) -> Color:
	var st := LEVEL_STOPS
	if lv <= st[0][0]:
		return st[0][1]
	for i in range(1, st.size()):
		if lv <= st[i][0]:
			return (st[i - 1][1] as Color).lerp(st[i][1], (lv - st[i - 1][0]) / (st[i][0] - st[i - 1][0]))
	return st[st.size() - 1][1]


static func rank_color(rank: String) -> Color:
	match rank:
		"SS":
			return Color(0.78, 0.97, 1.0)
		"S":
			return GOLD
		"A":
			return Color(0.5, 1.0, 0.7)
		"B":
			return ACCENT
		"C":
			return Color(0.75, 0.62, 1.0)
		"D":
			return Color(1.0, 0.62, 0.35)
		"F":
			return Color(1.0, 0.4, 0.45)
	return TEXT_DIM


## 3 桁ごとにカンマを入れる(1234567 → "1,234,567")。
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


## 全画面共通の Theme(ボタン・スライダー・スクロールバーを暗色・細線に揃える)。
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	# ボタン
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.06), LINE, 1, 4, 16, 8))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.28), 1, 4, 16, 8))
	t.set_stylebox("pressed", "Button", box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.2), ACCENT, 1, 4, 16, 8))
	t.set_stylebox("hover_pressed", "Button", box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.26), ACCENT, 1, 4, 16, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_hover_pressed_color", "Button", ACCENT)
	# スライダー(細い溝 + 水色の塗り)
	var track := box(Color(1, 1, 1, 0.14), Color(0, 0, 0, 0), 0, 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), Color(0, 0, 0, 0), 0, 2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", knob(7.0, Color(1, 1, 1, 0.95), ACCENT))
	t.set_icon("grabber_highlight", "HSlider", knob(10.0, Color.WHITE, ACCENT))
	t.set_icon("grabber_disabled", "HSlider", knob(6.0, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.2)))
	# スクロールバー(細く控えめ)
	var sb_track := box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 3)
	sb_track.content_margin_left = 3
	sb_track.content_margin_right = 3
	var sb_grab := box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 3)
	sb_grab.content_margin_left = 3
	sb_grab.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", sb_track)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	return t


## スライダーのつまみ(丸。半径 r、中は fill、縁は rim)。縁をなめらかにするため、画素ごとに距離から透明度を決めて描く。
static func knob(r: float, fill: Color, rim: Color) -> ImageTexture:
	var n := int(ceil(r * 2.0)) + 6
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in range(n):
		for x in range(n):
			var d := Vector2(x - c, y - c).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var ring := clampf(d - (r - 2.2) + 0.5, 0.0, 1.0)   # 外側 2px だけ縁の色
			var col := fill.lerp(rim, ring)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 15, color := TEXT, bold_font := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold_font:
		l.add_theme_font_override("font", bold())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 小さな見出し(セクションのキャプション)。
static func caption(text: String) -> Label:
	return label(text, 11, TEXT_FAINT)


## 小さな角丸タグ(MOD 名・数値など)。
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(color.r, color.g, color.b, 0.14), Color(color.r, color.g, color.b, 0.7), 1, 10, 9, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, 12, color))
	return p


static func hline() -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 押せるカード(PanelContainer)。左クリックで on_click、ダブルクリックで on_double。押している間は少し縮み、離すと弾んで戻る。
static func card(min_h: float, on_click: Callable, on_double := Callable()) -> PanelContainer:
	var c := PanelContainer.new()
	c.custom_minimum_size = Vector2(0, min_h)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_card_press(c, 0.975, 0.06, false)
				on_click.call()
				if ev.double_click and on_double.is_valid():
					on_double.call()
			else:
				_card_press(c, 1.0, 0.3, true))
	c.mouse_exited.connect(func(): _card_press(c, 1.0, 0.2, false))
	return c


static func _card_press(c: Control, to: float, dur: float, back: bool) -> void:
	if not animate or not c.is_inside_tree():
		c.scale = Vector2.ONE
		return
	c.pivot_offset = c.size * 0.5
	var old = c.get_meta("press_tween") if c.has_meta("press_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(to, to), dur).set_trans(Tween.TRANS_BACK if back else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("press_tween", t)


## カードの見た目: selected(選択中)/ focus(この列が操作対象か)/ accent(選択の色)。
static func style_card(c: PanelContainer, selected: bool, focused := true, accent := ACCENT, hover := false) -> void:
	var s: StyleBoxFlat
	if selected:
		var a := 0.85 if focused else 0.35
		s = box(Color(accent.r, accent.g, accent.b, 0.11 if focused else 0.06), Color(accent.r, accent.g, accent.b, a), 1, 5, 14, 9)
		s.border_width_left = 3
	elif hover:
		s = box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.18), 1, 5, 14, 9)
	else:
		s = box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.07), 1, 5, 14, 9)
	c.add_theme_stylebox_override("panel", s)


## 画面全体に敷く背景(暗い単色)。
static func backdrop(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


# --- アニメーション(なめらかな動きだけ。点滅・フラッシュは使わない) ---

## false のときは、動かさずに最終状態にする(スクリーンショット用の開発フックが使う)。
static var animate := true


## node の prop を from → to へ動かす(delay 秒後に開始。待っている間は from のまま)。animate が false なら to にするだけ。
static func tween(node: Node, prop: NodePath, from: Variant, to: Variant, dur := 0.35, delay := 0.0,
		trans := Tween.TRANS_CUBIC, ease_type := Tween.EASE_OUT) -> Tween:
	if not animate or not node.is_inside_tree():
		node.set_indexed(prop, to)
		return null
	node.set_indexed(prop, from)
	var t := node.create_tween()
	t.tween_property(node, prop, to, dur).set_delay(delay).set_trans(trans).set_ease(ease_type)
	return t


## 値 from → to を、コールバック(v)へ渡しながら動かす(数字のカウントアップなど)。
static func tween_value(node: Node, from: float, to: float, dur: float, on_value: Callable, delay := 0.0,
		trans := Tween.TRANS_CUBIC, ease_type := Tween.EASE_OUT) -> void:
	if not animate or not node.is_inside_tree():
		on_value.call(to)
		return
	on_value.call(from)
	var t := node.create_tween()
	t.tween_method(on_value, from, to, dur).set_delay(delay).set_trans(trans).set_ease(ease_type)


## 位置で置いた Control を、少しずらした位置からフェードしながら滑り込ませる(何度呼んでも最終位置は同じ)。
static func pop_in(c: Control, delay := 0.0, from_offset := Vector2(24, 0), dur := 0.4) -> void:
	var final_pos: Vector2 = c.get_meta("base_pos", c.position)
	c.set_meta("base_pos", final_pos)
	var old = c.get_meta("pop_tween") if c.has_meta("pop_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	if not animate or not c.is_inside_tree():
		c.position = final_pos
		c.modulate.a = 1.0
		return
	c.position = final_pos + from_offset
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "modulate:a", 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position", final_pos, dur).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("pop_tween", t)


## (旧)ホバーで少し大きくなるボタン。いまは Juice(juice.gd)が、すべてのボタンに自動でつけるので、何もしない。
static func hover_scale(_c: Control, _amount := 1.04) -> void:
	pass


## 弾んで止まる動き: from → to へ、行き過ぎてから戻る(TRANS_BACK)。何度呼んでも、前の同じ prop の動きは止めて置き換える。
static func spring(node: Node, prop: NodePath, from: Variant, to: Variant, dur := 0.4, delay := 0.0) -> Tween:
	if not animate or not node.is_inside_tree():
		node.set_indexed(prop, to)
		return null
	node.set_indexed(prop, from)
	var key := "spring_" + str(prop).replace(":", "_")
	var old = node.get_meta(key) if node.has_meta(key) else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := node.create_tween()
	t.tween_property(node, prop, to, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	node.set_meta(key, t)
	return t


## 中心から弾んで現れる(拡大しながらフェードイン)。パネル・トースト・ランクなど。作った直後で大きさが未確定なら、1 フレーム待つ。
static func pop_scale(c: Control, from_scale := 0.86, dur := 0.38, delay := 0.0) -> void:
	if not animate or not c.is_inside_tree():
		c.scale = Vector2.ONE
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	c.scale = Vector2(from_scale, from_scale)
	if c.size == Vector2.ZERO:
		await c.get_tree().process_frame
		if not is_instance_valid(c) or not c.is_inside_tree():
			return
	c.pivot_offset = c.size * 0.5
	spring(c, "scale", Vector2(from_scale, from_scale), Vector2.ONE, dur, delay)
	tween(c, "modulate:a", 0.0, 1.0, minf(dur, 0.22), delay)


## 背景の視差: マウスの位置へ、ゆっくり追従して動く(背景はマウスと逆へ、漂うリングは同じ向きへ。奥行きが出る)。
## par は前回の戻り値(最初は Vector2.ZERO)を渡す。bg は拡大して画面をはみ出している背景の入れもの(動かしても端が見えないよう、±10px 程度)。
static func parallax(bg: Control, amb: Node2D, par: Vector2, delta: float, viewport: Viewport) -> Vector2:
	if not animate:
		return par
	var n := ((viewport.get_mouse_position() - Vector2(640, 360)) / Vector2(640, 360)).clampf(-1.0, 1.0)
	par = par.lerp(n, 1.0 - exp(-3.0 * delta))
	if bg != null:
		bg.position = -par * Vector2(10, 6)
	if amb != null:
		amb.position = par * Vector2(22, 14)
	return par


## 全面に広げたページ(アンカーで親いっぱい)を、dx だけ横にずれた位置から滑り込ませる。位置ではなく左右の端のオフセットを一緒に動かす。
static func slide_page(page: Control, dx: float, dur := 0.34) -> void:
	if not animate or not page.is_inside_tree():
		page.offset_left = 0.0
		page.offset_right = 0.0
		return
	var old = page.get_meta("slide_tween") if page.has_meta("slide_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := page.create_tween()
	t.tween_method(func(v: float):
		page.offset_left = v
		page.offset_right = v, dx, 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	page.set_meta("slide_tween", t)


## 子を、上から順に少しずつ遅らせて、下から浮かび上がらせる(base 秒後から step 秒おき)。
static func stagger_in(items: Array, base := 0.0, step := 0.045, from_offset := Vector2(0, 14), dur := 0.38) -> void:
	var k := 0
	for c in items:
		if c is Control and c.is_inside_tree():
			pop_in(c, base + step * k, from_offset, dur)
			k += 1


## コンテナの中でも動かせるように、カードを Control で包む(カードは holder いっぱいに広がり、offset で動く)。
static func wrap_card(card: Control, h: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(card)
	return holder


## 横ずれ dx を、offset に反映する。左端は dx だけ動く。右端は、正のずれでは 10px を超えた分だけ、負のずれでは dx だけ動く
## (選択中の 10px は「左から入って少し右へ出る」ので、右端は元の位置のまま = 右へはみ出さない)。
static func _set_dx(card: Control, dx: float) -> void:
	card.offset_left = dx
	card.offset_right = dx if dx < 0.0 else maxf(dx - 10.0, 0.0)


## 包んだカードを横にずらす(選択中・ホバー中のカードが少し右に出る)。登場の途中なら、目標だけ更新する(登場が終わる位置になる)。
static func shift_card(card: Control, dx: float, dur := 0.26) -> void:
	var target: float = card.get_meta("dx", 0.0)
	if is_equal_approx(target, dx):
		return
	card.set_meta("dx", dx)
	if card.get_meta("entering", false):
		return
	_kill_meta_tween(card)
	if not animate or not card.is_inside_tree():
		_set_dx(card, dx)
		return
	var t := card.create_tween()
	t.tween_method(func(v: float): _set_dx(card, v), card.offset_left, dx, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card.set_meta("shift_tween", t)


## 包んだカードの登場: 横から滑り込みながらフェードイン。最終位置は meta "dx"(選択中なら少し右。登場中に変わっても追従する)。
static func enter_card(card: Control, delay: float, from_dx: float) -> void:
	_kill_meta_tween(card)
	if not animate or not card.is_inside_tree():
		_set_dx(card, card.get_meta("dx", 0.0))
		return
	card.modulate.a = 0.0
	_set_dx(card, from_dx)
	card.set_meta("entering", true)
	var t := card.create_tween().set_parallel(true)
	t.tween_property(card, "modulate:a", 1.0, 0.35).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): _set_dx(card, lerpf(from_dx, card.get_meta("dx", 0.0), v)), 0.0, 1.0, 0.45) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func(): card.set_meta("entering", false))
	card.set_meta("shift_tween", t)


static func _kill_meta_tween(card: Control) -> void:
	card.set_meta("entering", false)
	var old = card.get_meta("shift_tween") if card.has_meta("shift_tween") else null
	if old is Tween and old.is_valid():
		old.kill()


## 残量に応じた体力の色: 赤(20% 以下)→ 琥珀(35%)→ 青緑(55% 以上)。色相でなめらかにつなぐ(RGB で混ぜると灰色がかった濁った色になる)。
## 体力バーと、自機の周りのリングで共有する。
static func hp_color(g: float) -> Color:
	if g < 0.2:
		return Color.from_hsv(0.99, 0.73, 1.0)
	if g < 0.35:
		return Color.from_hsv(lerpf(0.99, 1.115, (g - 0.2) / 0.15), 0.72, 1.0)   # 赤 → 琥珀(色相は 1 を超えて回す)
	var t := clampf((g - 0.35) / 0.2, 0.0, 1.0)
	return Color.from_hsv(lerpf(0.115, 0.5, t), lerpf(0.68, 0.58, t), 1.0)   # 琥珀 → 青緑
