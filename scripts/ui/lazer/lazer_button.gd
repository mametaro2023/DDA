extends Button
## 斜めに切った、フッターの大きなボタン(lazer 風)。左右の端を slant だけ斜めにして、色で塗る。アイコン + 文字を中央に描く。
## 押せる範囲は四角全体(見た目だけ斜め)。クリック音の種類は set_meta("juice_sound", "back") で変える(文字は自分で描くので、text は空のまま)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")

var color := LazerStyle.PINK
var ink := Color(0.16, 0.05, 0.10)
var icon_kind := ""
var caption := ""
var slant := 14.0
var font_size := 18
## true: アイコンを上、文字を下に縦に並べる(タイトルの大きなボタン)。false: アイコンと文字を横に並べる(フッター)
var stacked := false
## 強調(選んでいるボタン)。明るくして、外側に淡い光(グロー)を出し、光沢の帯がときどき流れる
var emphasized := false:
	set(v):
		if emphasized == v:
			return
		emphasized = v
		z_index = 1 if v else 0   # 光が、隣のボタンの下に隠れないように
		_sheen_t = 0.0
		set_process(v and UiStyle.animate)
		queue_redraw()
## 拍の脈動など、外から与える明るさ(0..1。押せるときだけ効く)
var glow := 0.0:
	set(v):
		if not is_equal_approx(glow, v):
			glow = v
			queue_redraw()

const SHEEN_PERIOD := 2.6   # 光沢の帯が流れる間隔(秒)
const SHEEN_DELAY := 0.15
const SHEEN_DUR := 0.9
var _sheen_t := 0.0


func _init(p_caption := "", p_color := LazerStyle.PINK, p_icon := "", p_ink := Color(0.16, 0.05, 0.10)) -> void:
	caption = p_caption
	color = p_color
	icon_kind = p_icon
	ink = p_ink
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())   # 面は _draw で自分で描く
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(k, Color(0, 0, 0, 0))   # Button 自身の文字は隠す(文字は _draw で自分で描く)


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, button_down, button_up]:
		sig.connect(queue_redraw)


func _process(delta: float) -> void:
	_sheen_t = fmod(_sheen_t + delta, SHEEN_PERIOD)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := color
	if disabled:
		c = Color(1, 1, 1, 0.10)
	elif button_pressed or (is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		c = color.darkened(0.14)
	elif is_hovered() or emphasized:
		c = color.lightened(0.16)
	elif glow > 0.0:
		c = color.lightened(0.16 * clampf(glow, 0.0, 1.0))
	var poly := PackedVector2Array([Vector2(slant, 0), Vector2(w, 0), Vector2(w - slant, h), Vector2(0, h)])
	if disabled:
		draw_colored_polygon(poly, c)
	else:
		if emphasized:   # 外側の淡い光
			for g in [[13.0, 0.04], [8.0, 0.07], [4.0, 0.12]]:
				for part in Geometry2D.offset_polygon(poly, g[0]):
					draw_colored_polygon(part, Color(c.r, c.g, c.b, g[1]))
		draw_polygon(poly, PackedColorArray([c.lightened(0.14), c.lightened(0.14), c.darkened(0.16), c.darkened(0.16)]))   # 上が明るく、下が深い縦のグラデーション
		var gh := h * 0.46   # 上半分の薄い光沢
		var gloss := PackedVector2Array([Vector2(slant, 0), Vector2(w, 0), Vector2(w - slant * gh / h, gh), Vector2(slant * (1.0 - gh / h), gh)])
		draw_colored_polygon(gloss, Color(1, 1, 1, 0.10))
		draw_line(Vector2(slant, 1.0), Vector2(w, 1.0), Color(1, 1, 1, 0.45), 2.0)   # 上の縁のハイライト
		draw_line(Vector2(0, h - 1.0), Vector2(w - slant, h - 1.0), Color(0, 0, 0, 0.25), 2.0)   # 下の縁の影
		if emphasized and UiStyle.animate:   # 光沢の帯が、左から右へゆっくり流れる
			var u := clampf((_sheen_t - SHEEN_DELAY) / SHEEN_DUR, 0.0, 1.0)
			if u > 0.0 and u < 1.0:
				u = u * u * (3.0 - 2.0 * u)
				var bw := w * 0.16
				var x0 := lerpf(-bw - slant, w, u)
				var band := PackedVector2Array([Vector2(x0 + slant, 0), Vector2(x0 + slant + bw, 0), Vector2(x0 + bw, h), Vector2(x0, h)])
				for part in Geometry2D.intersect_polygons(poly, band):
					draw_colored_polygon(part, Color(1, 1, 1, 0.22))
	var f := LazerStyle.font_bold()
	var cap := caption if caption != "" else text.get_slice("   [", 0)   # caption が空なら、Button の text を使う(キーの案内の「   [Space]」より後ろは出さない)
	if stacked:
		var colr := LazerStyle.TEXT_MUTE if disabled else ink
		if icon_kind != "":
			LazerIcons.draw_icon(self, icon_kind, Vector2(w * 0.5, h * 0.40), font_size * 1.1, colr, 2.6)
		var by := h * 0.78 + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
		draw_string(f, Vector2(0, by), cap, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, colr)
		return
	var ts := f.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var icon_w := float(font_size) + 8.0 if icon_kind != "" else 0.0
	var x := (w - (icon_w + ts.x)) * 0.5
	var col := LazerStyle.TEXT_MUTE if disabled else ink
	if icon_kind != "":
		LazerIcons.draw_icon(self, icon_kind, Vector2(x + font_size * 0.5, h * 0.5), font_size * 0.5, col, 2.0)
	var base_y := (h - (f.get_ascent(font_size) + f.get_descent(font_size))) * 0.5 + f.get_ascent(font_size)
	draw_string(f, Vector2(x + icon_w, base_y), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
