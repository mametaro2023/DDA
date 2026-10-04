extends RefCounted
## lazer 風の確認ダイアログの枠(終了の確認・部屋を閉じる確認・ダウンロードの同意・アップデートで共通)。
## 背景が暗くなり、中央に角丸のカード: 上に丸い輪のアイコン、見出し、説明、その下に、横幅いっぱいの斜めのボタンが縦に並ぶ。
## 開くときは、カードが少し下から浮かび上がり、アイコンの輪が描かれていく(点滅・フラッシュなし)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")

const ICON_R := 34.0
const SCREEN := Vector2(1280, 720)


## host に枠を作る。返す辞書: {dim, panel, body(本文を入れる VBox), buttons(ボタンを入れる VBox), icon(輪のアイコン)}
## body_text が空なら、説明の行は出さない。中身(body)は呼び出し側が足してよい。
static func build(host: Control, icon: String, accent: Color, title: String, body_text := "", width := 500.0) -> Dictionary:
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	host.theme = LazerStyle.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.05, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(dim)
	var panel := PanelContainer.new()
	var sb := LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.98), Color(1, 1, 1, 0.08), 1, 18, 34, 0)
	sb.content_margin_top = ICON_R + 26.0
	sb.content_margin_bottom = 28.0
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	sb.border_width_top = 3
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size = Vector2(width, 0)
	host.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := LazerStyle.label(title, 24, LazerStyle.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(width - 68.0, 0)   # 折り返す文字は、幅を決めておく(決めないと、1 文字ずつ折り返した高さでカードが縦に伸びる)
	v.add_child(t)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	if body_text != "":
		var b := LazerStyle.label(body_text, 15, LazerStyle.TEXT_DIM)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(width - 68.0, 0)
		body.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	# 上の丸いアイコン(カードの上辺にまたがる)。輪は、開くときに描かれていく
	var ring := Control.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(ICON_R * 2.0 + 12.0, ICON_R * 2.0 + 12.0)
	ring.set_meta("k", 0.0 if UiStyle.animate else 1.0)
	ring.draw.connect(func():
		var c := ring.size * 0.5
		var k: float = ring.get_meta("k")
		ring.draw_circle(c, ICON_R + 4.0, Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 1.0))
		ring.draw_circle(c, ICON_R, Color(accent.r, accent.g, accent.b, 0.16))
		ring.draw_arc(c, ICON_R, -PI * 0.5, -PI * 0.5 + TAU * k, 64, accent, 3.0, true)
		LazerIcons.draw_icon(ring, icon, c, ICON_R * 0.5, Color(1, 1, 1, 0.5 + 0.45 * k), 2.6))
	host.add_child(ring)   # (コンテナの子にすると大きさを決められてしまうので、host に置いて、カードの上辺に合わせる)
	var recenter := func():
		panel.position = ((SCREEN - panel.size) * 0.5 + Vector2(0, 14.0)).round()
		panel.pivot_offset = panel.size * 0.5
		ring.position = panel.position + Vector2((panel.size.x - ring.size.x) * 0.5, -ring.size.y * 0.5 + 6.0)
	panel.resized.connect(recenter)
	panel.minimum_size_changed.connect(func(): panel.size = Vector2(width, 0.0))   # 中身が縮んだら、カードも縮める(大きさは最小の大きさに合わせる)
	recenter.call()
	return {"dim": dim, "panel": panel, "body": body, "buttons": buttons, "icon": ring}


## 横幅いっぱいの斜めのボタンを parent に足す。
static func button(parent: Control, caption: String, color: Color, icon: String, ink: Color, on_press: Callable, sound := "") -> LazerButton:
	var b := LazerButton.new(caption, color, icon, ink)
	b.text = caption   # (確認用のコードが text を読む。描くのは caption)
	b.custom_minimum_size = Vector2(0, 50)
	b.font_size = 17
	b.slant = 12.0
	if sound != "":
		b.set_meta("juice_sound", sound)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## 開く動き: 背景が暗くなり、カードが少し下から浮かび上がり、アイコンの輪が描かれる。
static func open_anim(host: Control, f: Dictionary) -> void:
	UiSfx.play("open")
	var dim: ColorRect = f.dim
	var panel: Control = f.panel
	var ring: Control = f.icon
	UiStyle.tween(dim, "color:a", 0.0, 0.7, 0.22)
	if not UiStyle.animate or not host.is_inside_tree():
		ring.set_meta("k", 1.0)
		ring.queue_redraw()
		return
	panel.modulate.a = 0.0
	ring.modulate.a = 0.0
	var t := host.create_tween().set_parallel(true)
	t.tween_property(panel, "modulate:a", 1.0, 0.2)
	t.tween_property(ring, "modulate:a", 1.0, 0.2)
	t.tween_property(panel, "scale", Vector2.ONE, 0.42).from(Vector2(0.94, 0.94)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(func(k: float):
		ring.set_meta("k", k)
		ring.queue_redraw(), 0.0, 1.0, 0.55).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var btns: Array = (f.buttons as Control).get_children()
	for k in range(btns.size()):   # ボタンが上から順に、少し遅れて現れる
		UiStyle.tween(btns[k], "modulate:a", 0.0, 1.0, 0.22, 0.12 + 0.05 * k)


## 閉じる動き: カードが少し縮みながら消え、背景が明るさを戻す。終わったら done。
static func close_anim(host: Control, f: Dictionary, done: Callable, sound := "close") -> void:
	if sound != "":
		UiSfx.play(sound)
	if not UiStyle.animate or not host.is_inside_tree():
		done.call()
		return
	var panel: Control = f.panel
	var t := host.create_tween().set_parallel(true)
	t.tween_property(f.dim, "color:a", 0.0, 0.18)
	t.tween_property(panel, "modulate:a", 0.0, 0.16)
	t.tween_property(f.icon, "modulate:a", 0.0, 0.16)
	t.tween_property(panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(done)
