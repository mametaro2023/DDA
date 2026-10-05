extends Control
## lazer 風 UI の画面の土台: 背景(曲の画像を暗く敷く)・上のツールバー・下のフッター・視差・時計。
## 画面は、これを継承して _build_base() を呼び、中身を置く。画面の種類(kind)・signal は、画面ごとに契約(ui_set.gd)に従って足す。
## 枠の部品そのものは LazerChrome(classic の画面を継承した lazer 版も、同じものを使う)。

## 設定を開く(パネルは main が持つ。どの画面でも開ける)。section: 0=操作 1=音 2=画面 3=曲 4=その他
signal settings_requested(section: int)

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerChrome = preload("res://scripts/ui/lazer/lazer_chrome.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const TOOLBAR_H := LazerChrome.TOOLBAR_H
const FOOTER_H := LazerChrome.FOOTER_H
const SIZE_PX := LazerChrome.SIZE_PX

var settings: Dictionary = {}
## 設定の入口(上のツールバーの歯車)を、この画面が持っている。main は、右上の「設定」ボタンを出さない(ui_set.gd の契約)
var own_settings_button := true

var _bg_holder: Control
var _bg: TextureRect          # 今見えている背景(もう 1 枚 _bg2 と交代でクロスフェードする)
var _bg2: TextureRect
var _par := Vector2.ZERO
## 背景の画像を明るめに見せる(選曲・開始前画面)。_build_base の前に決める
var backdrop_bright := false
var _toolbar: Control
var _footer: Control
var _clock_l: Label
var _clock_t := 1.0


## 画面の土台(背景・暗幕)を作る。中身より先に呼ぶ。
func _build_base() -> void:
	theme = LazerStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var b := LazerChrome.build_backdrop(self, backdrop_bright)
	_bg_holder = b.holder
	_bg = b.layers[0]
	_bg2 = b.layers[1]


## 背景画像を、前の画像からクロスフェードで切り替える(null なら、画像なし = 暗い単色)。instant = true なら、すぐ切り替える(ゲームから続く背景など)。
func set_background(tex: Texture2D, instant := false) -> void:
	var cur := _bg
	var nxt := _bg2
	nxt.texture = tex
	if instant:
		nxt.modulate.a = 1.0 if tex != null else 0.0
		cur.modulate.a = 0.0
		_bg = nxt
		_bg2 = cur
		return
	var to_a := 1.0 if tex != null else 0.0
	UiStyle.tween(nxt, "modulate:a", 0.0, to_a, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	UiStyle.tween(cur, "modulate:a", cur.modulate.a, 0.0, 0.7, 0.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_bg = nxt
	_bg2 = cur


func _process(delta: float) -> void:
	_par = UiStyle.parallax(_bg_holder, null, _par, delta, get_viewport())
	_clock_t += delta
	if _clock_t >= 1.0 and _clock_l != null:
		_clock_t = 0.0
		LazerChrome.update_clock(_clock_l)


func _place(c: Control, x: float, y: float, w: float, h: float) -> Control:
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	add_child(c)
	return c


## 上のツールバー: 左に設定の歯車と、いまの場所(パンくず。最後が現在地)、右に時計とプレイヤー名。
func _build_toolbar(crumbs: Array) -> void:
	var t := LazerChrome.build_toolbar(self, crumbs, settings, func(): settings_requested.emit(0))
	_toolbar = t.node
	_clock_l = t.clock
	_clock_t = 0.0


func _build_footer() -> void:
	_footer = LazerChrome.build_footer(self)


## フッターにボタンを置く(x は左端。斜めの端が重なるので、次のボタンは x + w - 斜め幅 + すきま)。
func _footer_button(caption: String, color: Color, icon: String, x: float, w: float, on_press: Callable, ink := Color(0.16, 0.05, 0.10)) -> LazerButton:
	return LazerChrome.footer_button(_footer, caption, color, icon, x, w, on_press, ink)
