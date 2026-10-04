extends Button
## 斜めに切った、フッターの大きなボタン(lazer 風)。左右の端を slant だけ斜めにして、色で塗る。アイコン + 文字を中央に描く。
## 押せる範囲は四角全体(見た目だけ斜め)。クリック音の種類は set_meta("juice_sound", "back") で変える(文字は自分で描くので、text は空のまま)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")

var color := LazerStyle.PINK
var ink := Color(0.16, 0.05, 0.10)
var icon_kind := ""
var caption := ""
var slant := 14.0
var font_size := 18
## true: アイコンを上、文字を下に縦に並べる(タイトルの大きなボタン)。false: アイコンと文字を横に並べる(フッター)
var stacked := false
## 強調(選んでいるボタン)。明るくする
var emphasized := false


func _init(p_caption := "", p_color := LazerStyle.PINK, p_icon := "", p_ink := Color(0.16, 0.05, 0.10)) -> void:
	caption = p_caption
	color = p_color
	icon_kind = p_icon
	ink = p_ink
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())   # 面は _draw で自分で描く
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(k, Color(0, 0, 0, 0))   # Button 自身の文字は隠す(文字は _draw で自分で描く)


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, button_down, button_up]:
		sig.connect(queue_redraw)


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
	draw_colored_polygon(PackedVector2Array([Vector2(slant, 0), Vector2(w, 0), Vector2(w - slant, h), Vector2(0, h)]), c)
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
