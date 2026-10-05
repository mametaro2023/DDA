extends RefCounted
## lazer 風 UI の見た目(色・フォント・テーマ・小さな部品)。classic の UiStyle には手を入れず、こちらで独立して持つ。
## 方針: 暗い紫がかった地 / 角丸のパネル / ピンクを主役にした色 / 斜めに切ったボタン / 難易度は星の色。点滅・フラッシュ・画面揺れは使わない。
## 動きの道具(UiStyle.pop_in / tween / spring など)は見た目に依存しないので、classic と共用する。

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const BG := Color(0.090, 0.086, 0.122)
const BAR := Color(0.051, 0.047, 0.075)          # ツールバー・フッターの地
const PANEL := Color(0.169, 0.157, 0.224)
const PANEL_SEL := Color(0.263, 0.188, 0.361)
const PANEL_DARK := Color(0.055, 0.047, 0.086)   # 情報パネルの地(背景の上に、濃く重ねる)

const PINK := Color(1.0, 0.400, 0.671)
const BLUE := Color(0.400, 0.800, 1.0)
const PURPLE := Color(0.549, 0.400, 1.0)
const GREEN := Color(0.698, 1.0, 0.400)
const YELLOW := Color(1.0, 0.867, 0.333)
const RED := Color(0.878, 0.314, 0.416)

const TEXT := Color(1, 1, 1, 0.96)
const TEXT_DIM := Color(0.812, 0.796, 0.878)
const TEXT_MUTE := Color(0.608, 0.592, 0.690)
const LINE := Color(1, 1, 1, 0.10)

## 背景(曲の画像)を暗くする色。画像の明るさに関係なく、文字が読める暗さにする
const BG_TINT := Color(0.33, 0.33, 0.39)
## 選曲・開始前画面の背景は、もう少し明るく(暗幕も薄く)する。曲の画像を見せたい画面
const BG_TINT_BRIGHT := Color(0.42, 0.42, 0.50)
const BG_SHADE_A := 0.60
const BG_SHADE_A_BRIGHT := 0.50
## 背景の拡大(視差で動かしても端が見えない大きさ。止めたまま動かさない)
const BG_SCALE := 1.04

## 発進(選曲 → 開始前画面)の間、背景がゆっくりズームインし続ける速さ(倍率 / 秒)。選曲の発進の演出で加速し、開始前画面は同じ速さで続ける
## (止まったり、戻ったりしないので、一続きの動きに見える)
const LAUNCH_ZOOM_SPEED := 0.03

## 難易度(Lv)を「星の数」に直す倍率(DDA の Lv は 1〜12 ほどなので、星の色の帯に収める)
const STAR_PER_LV := 0.62
## 星の数 → 色の停留点(osu! の星の色の帯と同じ並び: 青 → 水色 → 緑 → 黄 → 橙 → 赤 → 紫 → 濃紺 → 黒)
const STAR_STOPS := [
	[0.0, Color(0.259, 0.565, 0.984)], [1.25, Color(0.310, 0.753, 1.0)], [2.0, Color(0.310, 1.0, 0.835)],
	[2.5, Color(0.486, 1.0, 0.310)], [3.3, Color(0.965, 0.941, 0.361)], [4.2, Color(1.0, 0.502, 0.408)],
	[4.9, Color(1.0, 0.306, 0.435)], [5.8, Color(0.776, 0.271, 0.722)], [6.7, Color(0.396, 0.388, 0.871)],
	[7.7, Color(0.094, 0.082, 0.557)], [9.0, Color(0.0, 0.0, 0.0)],
]

static var _font: Font
static var _font_bold: Font


## 本文のフォント。OS の UI フォント(Windows なら Segoe UI)+ 日本語は OS の日本語フォントへ落とす。見つからなければ、標準フォント。
static func font() -> Font:
	if _font == null:
		_font = _system_font(400)
	return _font


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = _system_font(700)
	return _font_bold


## 数字はすべて同じ幅(等幅の数字)にする。
## 日本語は、OS に毎回たずねず(文字列ごとに OS のフォント探しが走り、パネルを開くたびに止まる)、日本語のフォントを明示の代替にしておく。
static func _system_font(weight: int) -> Font:
	var jp := SystemFont.new()
	jp.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo UI", "Yu Gothic", "Meiryo", "Hiragino Sans", "Noto Sans CJK JP", "Noto Sans JP"])
	jp.font_weight = weight
	jp.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	jp.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	jp.allow_system_fallback = false
	jp.fallbacks = [ThemeDB.fallback_font]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Variable Text", "Segoe UI", "Yu Gothic UI", "Meiryo UI", "Hiragino Sans", "Noto Sans CJK JP", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.allow_system_fallback = false
	f.fallbacks = [jp, ThemeDB.fallback_font]
	var v := FontVariation.new()   # 数字は等幅(tnum)。スコアなどの変わり続ける数字が、「1」が出るたびに左右へぶれないように
	v.base_font = f
	v.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return v


## 星の数に対応する色(連続的に変わる)。
static func star_color(stars: float) -> Color:
	var st := STAR_STOPS
	if stars <= st[0][0]:
		return st[0][1]
	for i in range(1, st.size()):
		if stars <= st[i][0]:
			return (st[i - 1][1] as Color).lerp(st[i][1], (stars - st[i - 1][0]) / (st[i][0] - st[i - 1][0]))
	return st[st.size() - 1][1]


## DDA の Lv の色。
static func level_color(lv: float) -> Color:
	return star_color(lv * STAR_PER_LV)


## その色の上に載せる文字の色(明るい色には暗い文字、暗い色(高難度)には明るい文字)
static func ink_on(c: Color) -> Color:
	if c.get_luminance() > 0.45:
		return Color(0.12, 0.08, 0.02)
	return Color(1.0, 0.93, 0.62)


## 曲の題名から決めた色(曲の画像を持たない一覧の行の、サムネイルの色。同じ題名は、いつも同じ色)
static func title_color(title: String) -> Color:
	var h := 0
	for i in range(title.length()):
		h = (h * 31 + title.unicode_at(i)) & 0xFFFF
	return Color.from_hsv(float(h % 360) / 360.0, 0.55, 0.9)


## 1 行に入りきらない文字は、後ろを「…」にして、max_w に収める(draw_string で描く文字用)。
static func fit(f: Font, text: String, size: int, max_w: float) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return text
	while text.length() > 1 and f.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		text = text.left(text.length() - 1)
	return text + "…"


static func box(bg: Color, border := Color(0, 0, 0, 0), border_w := 0, radius := 8, mh := 0.0, mv := 0.0) -> StyleBoxFlat:
	return UiStyle.box(bg, border, border_w, radius, mh, mv)


static func label(text: String, size := 16, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font_bold() if bold else font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 小さな丸い札(文字 + 色の地)。ランク・MOD・Lv の表示などに使う。
static func pill(text: String, color: Color, size := 14, ink := Color(-1, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, Color(0, 0, 0, 0), 0, 999, 11, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, size, ink_on(color) if ink.r < 0.0 else ink, true))
	return p


## 全画面共通の Theme(フォント・ボタン・スライダー・スクロールバー・入力欄を、lazer 風に揃える)。
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	# ふつうのボタン(設定の解像度の選択など): 角丸のうす面。押している(トグルが入っている)ときはピンク。斜めのフッターボタン(LazerButton)は、自分で描く
	t.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.07), LINE, 1, 10, 16, 8))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.26), 1, 10, 16, 8))
	t.set_stylebox("pressed", "Button", box(Color(PINK.r, PINK.g, PINK.b, 0.28), PINK, 1, 10, 16, 8))
	t.set_stylebox("hover_pressed", "Button", box(Color(PINK.r, PINK.g, PINK.b, 0.36), PINK, 1, 10, 16, 8))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.03), LINE, 1, 10, 16, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", PINK)
	t.set_color("font_disabled_color", "Button", TEXT_MUTE)
	# 入力欄(部屋の名前・招待コード・検索)
	t.set_stylebox("normal", "LineEdit", box(Color(1, 1, 1, 0.08), LINE, 1, 10, 14, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(1, 1, 1, 0.12), PINK, 1, 10, 14, 8))
	t.set_stylebox("read_only", "LineEdit", box(Color(1, 1, 1, 0.05), LINE, 1, 10, 14, 8))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTE)
	t.set_color("caret_color", "LineEdit", PINK)
	t.set_color("selection_color", "LineEdit", Color(PINK.r, PINK.g, PINK.b, 0.4))
	# スライダー(細い溝 + ピンクの塗り)
	var track := box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 0, 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := box(PINK, Color(0, 0, 0, 0), 0, 2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", UiStyle.knob(7.0, Color.WHITE, PINK))
	t.set_icon("grabber_highlight", "HSlider", UiStyle.knob(9.0, Color.WHITE, PINK))
	t.set_icon("grabber_disabled", "HSlider", UiStyle.knob(6.0, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.2)))
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
