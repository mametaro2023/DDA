extends "res://scripts/ui/multi_screen.gd"
## lazer 風のマルチプレイ画面(入口とロビー)。部屋の処理(作る・入る・曲の確認・ダウンロード・開始の条件・退出の確認)と、画面のレイアウトは
## classic のマルチ画面(multi_screen.gd)のものをそのまま使い、背景・上のツールバー・戻るボタン・パネル・ボタンの見た目だけを lazer 風に差し替える。
## 契約も同じ: signal back_requested / pick_song_requested、setup(net, notice)。

signal settings_requested(section: int)

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerChrome = preload("res://scripts/ui/lazer/lazer_chrome.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerQuit = preload("res://scripts/ui/lazer/lazer_quit.gd")

## 設定の入口(上のツールバーの歯車)を、この画面が持っている。main は、右上の「設定」ボタンを出さない(ui_set.gd の契約)
var own_settings_button := true

var _drift: Tween
var _toolbar: Control


func _build_backdrop() -> void:
	theme = LazerStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var b := LazerChrome.build_backdrop(self)
	_bg_holder = b.holder
	_bg = b.layers[0]
	_drift = b.drift
	_ambient = null   # 漂うリングはなし(視差は背景だけ)


## 見出し: 上のツールバー(歯車と、いまの場所)と、左下の戻るボタン(「退出」「タイトル」など)。
func _header(back_text: String, on_back: Callable) -> void:
	var here := "ロビー" if _page == "lobby" else "入口"
	if _toolbar != null:   # 場所が変わるたびに作り直す(画面そのものの上に置く。内容の作り直しでは消えない)
		_toolbar.queue_free()
	var t := LazerChrome.build_toolbar(self, ["マルチ", here], settings, func(): settings_requested.emit(0))
	_toolbar = t.node
	var label := back_text.trim_prefix("◀").strip_edges()
	var back := LazerButton.new(label, LazerStyle.PINK, "back")
	back.position = Vector2(0, 720 - LazerChrome.FOOTER_H)
	back.size = Vector2(168, LazerChrome.FOOTER_H)
	back.set_meta("juice_sound", "back")
	back.pressed.connect(on_back)
	_content.add_child(back)


func _panel(x: float, y: float, w: float, h: float, alpha := 0.04) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.62 + alpha * 3.0), Color(1, 1, 1, 0.06), 1, 16, 22, 18))
	_place(p, x, y, w, h)
	return p


func _button(text: String, on_press: Callable, primary := false) -> Button:
	var b := LazerButton.new("", LazerStyle.PINK if primary else Color(0.3, 0.28, 0.38), "", Color(0.2, 0.04, 0.11) if primary else LazerStyle.TEXT)
	b.text = text
	b.font_size = 16
	var w := LazerStyle.font_bold().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	b.custom_minimum_size = Vector2(ceilf(w) + 48.0, 40.0)
	b.pressed.connect(on_press)
	return b


## 確認パネル(部屋を閉じる・ダウンロードの同意)は lazer 風のもの。
func _make_confirm() -> Control:
	return LazerQuit.new()
