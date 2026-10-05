extends RefCounted
## lazer 風の画面の「枠」の部品(上のツールバー・下のフッター・背景)。LazerScreen を継承できない画面(classic の画面を継承した lazer 版)も使えるよう、static にしてある。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerPlayer = preload("res://scripts/ui/lazer/lazer_player.gd")
const LazerProfileChip = preload("res://scripts/ui/lazer/lazer_profile_chip.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const TOOLBAR_H := 40.0
const FOOTER_H := 56.0
const SIZE_PX := Vector2(1280, 720)


## 背景(曲の画像を暗く敷く)を host に作る。bright = true なら、画像を明るめに見せる(選曲・開始前画面)。
## 返す辞書: {holder(視差で動かす入れもの), layers(クロスフェードする 2 枚)}。背景は、マウスの動きに合わせて動く(視差)だけで、ひとりでに揺れ動くことはない。
static func build_backdrop(host: Control, bright := false) -> Dictionary:
	var tint: Color = LazerStyle.BG_TINT_BRIGHT if bright else LazerStyle.BG_TINT
	var base := ColorRect.new()
	base.color = LazerStyle.BG
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(base)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.pivot_offset = SIZE_PX * 0.5
	holder.scale = Vector2(LazerStyle.BG_SCALE, LazerStyle.BG_SCALE)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(holder)
	var layers: Array = []
	for i in range(2):
		var t := TextureRect.new()
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.modulate = Color(tint.r, tint.g, tint.b, 0.0)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
		layers.append(t)
	var shade := ColorRect.new()   # 暗幕(画像の明るさに関係なく、文字が読める暗さにする)
	shade.color = Color(0.055, 0.045, 0.10, LazerStyle.BG_SHADE_A_BRIGHT if bright else LazerStyle.BG_SHADE_A)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(shade)
	return {"holder": holder, "layers": layers}


## 上のツールバー: 左に設定の歯車と、いまの場所(パンくず。最後が現在地)、右に流れている曲のプレイヤー・時計・プレイヤー名(押すと名前とアイコンを変えられる)。返す辞書: {node, clock(時計の Label)}
static func build_toolbar(host: Control, crumbs: Array, settings: Dictionary, on_gear: Callable) -> Dictionary:
	var tb := Control.new()
	tb.position = Vector2.ZERO
	tb.size = Vector2(SIZE_PX.x, TOOLBAR_H)
	host.add_child(tb)
	var bar := ColorRect.new()
	bar.color = Color(LazerStyle.BAR.r, LazerStyle.BAR.g, LazerStyle.BAR.b, 0.94)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(bar)
	var gear := Button.new()
	gear.focus_mode = Control.FOCUS_NONE
	gear.position = Vector2(0, 0)
	gear.size = Vector2(52, TOOLBAR_H)
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		gear.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	gear.add_child(LazerIcons.new("gear", LazerStyle.TEXT_DIM, 20.0))
	gear.get_child(0).position = Vector2(16, 10)
	gear.set_meta("juice_sound", "open")
	gear.pressed.connect(on_gear)
	tb.add_child(gear)
	var x := 66.0
	for i in range(crumbs.size()):
		var last := i == crumbs.size() - 1
		var l := LazerStyle.label(str(crumbs[i]), 15, LazerStyle.TEXT if last else LazerStyle.TEXT_MUTE, last)
		l.position = Vector2(x, 9)
		tb.add_child(l)
		var w := l.get_minimum_size().x
		if last:
			var ul := ColorRect.new()
			ul.color = LazerStyle.PINK
			ul.position = Vector2(x - 2, TOOLBAR_H - 3)
			ul.size = Vector2(w + 4, 3)
			ul.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tb.add_child(ul)
		x += w + 14.0
		if not last:
			var sep := LazerStyle.label("›", 15, LazerStyle.TEXT_MUTE)
			sep.position = Vector2(x - 8, 9)
			tb.add_child(sep)
			x += 12.0
	# 右: プレイヤー(丸いアイコン + 名前。押すと変えられる)と時計
	var chip := LazerProfileChip.new(settings)
	chip.position = Vector2(SIZE_PX.x - 14.0 - LazerProfileChip.W, (TOOLBAR_H - LazerProfileChip.H) * 0.5)
	tb.add_child(chip)
	var clock := LazerStyle.label("", 14, LazerStyle.TEXT_MUTE)
	clock.size = Vector2(60, 20)
	clock.position = Vector2(chip.position.x - 12.0 - 44.0, 10)
	tb.add_child(clock)
	update_clock(clock)
	var music := LazerPlayer.new()   # 時計の左: いま流れている曲
	music.position = Vector2(clock.position.x - 6.0 - LazerPlayer.W, 0)
	tb.add_child(music)
	return {"node": tb, "clock": clock}


static func update_clock(clock: Label) -> void:
	var t := Time.get_time_dict_from_system()
	clock.text = "%02d:%02d" % [t.hour, t.minute]


## 下のフッター(暗い帯)を host の下に置く。ボタンは footer_button で足す。
static func build_footer(host: Control) -> Control:
	var f := Control.new()
	f.position = Vector2(0, SIZE_PX.y - FOOTER_H)
	f.size = Vector2(SIZE_PX.x, FOOTER_H)
	host.add_child(f)
	var bar := ColorRect.new()
	bar.color = Color(LazerStyle.BAR.r, LazerStyle.BAR.g, LazerStyle.BAR.b, 0.96)
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(bar)
	return f


## フッターにボタンを置く(x は左端。斜めの端が重なるので、次のボタンは x + w - 斜め幅 + すきま)。
static func footer_button(footer: Control, caption: String, color: Color, icon: String, x: float, w: float, on_press: Callable, ink := Color(0.16, 0.05, 0.10)) -> LazerButton:
	var b := LazerButton.new(caption, color, icon, ink)
	b.position = Vector2(x, 0)
	b.size = Vector2(w, FOOTER_H)
	b.pressed.connect(on_press)
	footer.add_child(b)
	return b
