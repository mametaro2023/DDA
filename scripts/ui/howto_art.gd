extends Control
## 遊び方パネル(howto_panel.gd / lazer_howto.gd)の挿絵。文章だけでは伝わりにくいところ(画面の見かた・グレイズ・特殊エリア・ランクなど)を、
## ゲームの絵と同じ色・形で描く。幅は入れものに合わせて変わり(高さは kind ごとに決まる)、字は UI の字体で描く。動かない(点滅もしない)。
##   使い方: HowtoArt.make("hud") → 文章の間に add_child する。kind は下の ART の名前。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

## kind → 高さ
const HEIGHTS := {
	"flow": 140, "arena": 262, "hud": 352, "keys": 214, "zones": 372, "timeline": 168, "gauge": 150, "ranks": 132, "eq": 96,
	"lv": 74, "select": 346, "multi": 238, "songs": 118,
}

var kind := ""
var _font: Font


static func make(k: String) -> Control:
	var a: Control = (load("res://scripts/ui/howto_art.gd") as GDScript).new()
	a.kind = k
	a.custom_minimum_size = Vector2(0, float(HEIGHTS.get(k, 100)))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


func _draw() -> void:
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	# 台紙: 暗い面と細い縁
	draw_style_box(UiStyle.box(Color(0.015, 0.02, 0.04, 0.62), Color(1, 1, 1, 0.1), 1, 10), Rect2(0, 0, w, h))
	match kind:
		"flow": _flow(w, h)
		"arena": _arena(w, h)
		"hud": _hud(w, h)
		"keys": _keys(w, h)
		"zones": _zones(w, h)
		"timeline": _timeline(w, h)
		"gauge": _gauge(w, h)
		"ranks": _ranks(w, h)
		"eq": _eq(w, h)
		"lv": _lv(w, h)
		"select": _select(w, h)
		"multi": _multi(w, h)
		"songs": _songs(w, h)


# --- 部品 ---

func _t(text: String, pos: Vector2, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos, text, align, width, fs, col)


## 折り返す文字(pos は 1 行目の基準線の左端)。
func _tw(text: String, pos: Vector2, width: float, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_multiline_string(_font, pos, text, align, width, fs, -1, col)


func _dim() -> Color:
	return UiStyle.TEXT_DIM


func _accent() -> Color:
	return UiStyle.ACCENT


## 自機: 水色の三角形と、白い芯(当たり判定の点)。s = 大きさの倍率。
func _ship(c: Vector2, s := 1.0, col := Color(0.42, 0.88, 1.0)) -> void:
	var p := PackedVector2Array([c + Vector2(0, -12) * s, c + Vector2(-9, 9) * s, c + Vector2(0, 4) * s, c + Vector2(9, 9) * s])
	draw_colored_polygon(p, Color(col.r, col.g, col.b, 0.9))
	draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), col.lerp(Color.WHITE, 0.5), 1.5 * s, true)
	draw_circle(c + Vector2(0, 1) * s, 3.2 * s, Color.WHITE)


## 弾: パステルの塗りと、明るい縁。
func _bullet(c: Vector2, r: float, idx: int) -> void:
	var col: Color = BulletField.PALETTE[idx % 5].lerp(Color.WHITE, 0.3)
	draw_circle(c, r, col.darkened(0.15))
	draw_circle(c, r * 0.62, col.lerp(Color.WHITE, 0.4))
	draw_arc(c, r, 0.0, TAU, 24, col.lerp(Color.WHITE, 0.2), 1.5, true)


func _dashed_circle(c: Vector2, r: float, col: Color, width := 1.5, n := 28) -> void:
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		draw_arc(c, r, a0, a0 + TAU / float(n) * 0.55, 6, col, width, true)


func _dashed_rect(r: Rect2, col: Color, width := 1.5, dash := 6.0) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in range(4):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len := a.distance_to(b)
		var d := (b - a) / maxf(len, 0.001)
		var t := 0.0
		while t < len:
			draw_line(a + d * t, a + d * minf(t + dash, len), col, width, true)
			t += dash * 2.0


## 番号の丸(画面の見かたの印)。
func _num(c: Vector2, n: int, col := Color(1.0, 0.85, 0.3)) -> void:
	draw_circle(c, 10.0, col)
	_t(str(n), c + Vector2(-10.0, 5.0), 13, Color(0.1, 0.07, 0.0), HORIZONTAL_ALIGNMENT_CENTER, 20.0)


## 引き出し線つきの短いラベル。
func _call(from: Vector2, to: Vector2, text: String, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, fs := 13) -> void:
	draw_line(from, to, col, 1.5, true)
	draw_circle(from, 2.5, col)
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		_t(text, to + Vector2(5, 4), fs, col)
	else:
		_t(text, to + Vector2(-205, 4), fs, col, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)


func _card(r: Rect2, col: Color, fill := 0.12) -> void:
	draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, fill), Color(col.r, col.g, col.b, 0.55), 1, 8), r)


func _keycap(r: Rect2, text: String, fs := 14, col := Color(1, 1, 1)) -> void:
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.5), 1, 5), r)
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4), Rect2(r.position + Vector2(2, r.size.y - 5), Vector2(r.size.x - 4, 3)))
	_t(text, r.position + Vector2(0, r.size.y * 0.5 + fs * 0.36), fs, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# --- はじめに: 遊びの流れ ---

func _flow(w: float, h: float) -> void:
	var items := [
		["曲を選ぶ", ".osz を入れて、難易度を選ぶ", Color(0.42, 0.88, 1.0)],
		["弾をよける", "当たっている間だけ、体力が減る", Color(1.0, 0.55, 0.75)],
		["かすって稼ぐ", "弾のすぐそばを通ると、ボーナス", Color(1.0, 0.85, 0.3)],
		["最後まで生き残る", "クリアして、ランクが決まる", Color(0.6, 1.0, 0.7)],
	]
	var gap := 22.0
	var cw := (w - 24.0 - gap * 3.0) / 4.0
	for i in range(4):
		var x := 12.0 + (cw + gap) * float(i)
		var col: Color = items[i][2]
		_card(Rect2(x, 12, cw, h - 24), col)
		_num(Vector2(x + 16, 28), i + 1, col)
		var ic := Vector2(x + cw * 0.5, 50)
		match i:
			0:   # 音符
				draw_circle(ic + Vector2(-5, 8), 5.5, col)
				draw_line(ic + Vector2(0, 8), ic + Vector2(0, -12), col, 2.5, true)
				draw_polyline(PackedVector2Array([ic + Vector2(0, -12), ic + Vector2(10, -8), ic + Vector2(10, -2)]), col, 2.5, true)
			1:
				_ship(ic + Vector2(0, 4), 1.1)
				_bullet(ic + Vector2(-24, -8), 5, 1)
				_bullet(ic + Vector2(24, -4), 5, 3)
			2:
				_ship(ic + Vector2(-6, 4), 1.1)
				_dashed_circle(ic + Vector2(-6, 2), 20.0, col, 1.5, 18)
				_bullet(ic + Vector2(22, -6), 5, 4)
			3:
				var star := PackedVector2Array()
				for q in range(11):
					star.append(ic + Vector2(0, 2) + Vector2.from_angle(-PI * 0.5 + PI * 0.2 * q) * (15.0 if q % 2 == 0 else 6.5))
				draw_polyline(star, col, 2.5, true)
		_t(items[i][0], Vector2(x, 96), 15, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cw)
		_tw(items[i][1], Vector2(x + 8, 114), cw - 16.0, 11, _dim(), HORIZONTAL_ALIGNMENT_CENTER)
		if i < 3:
			var ax := x + cw + 3.0
			draw_polyline(PackedVector2Array([Vector2(ax, h * 0.5 - 7), Vector2(ax + 9, h * 0.5), Vector2(ax, h * 0.5 + 7)]), _dim(), 2.0, true)


# --- 弾とグレイズ ---

func _arena(w: float, h: float) -> void:
	var ar := Rect2(14, 14, w * 0.5 - 14, h - 28)
	draw_rect(ar, Color(0.02, 0.025, 0.05, 0.95))
	draw_rect(ar, Color(1, 1, 1, 0.35), false, 1.5)
	var c := ar.get_center() + Vector2(0, 14)
	# 遠い弾・かすった弾・当たった弾
	_bullet(c + Vector2(-82, -78), 7, 2)
	_bullet(c + Vector2(-30, -92), 5, 0)
	_bullet(c + Vector2(76, -66), 6, 3)
	draw_line(c + Vector2(-60, -60), c + Vector2(-22, -30), Color(1, 1, 1, 0.14), 2.0, true)
	var graze_r := 46.0
	_dashed_circle(c, graze_r, Color(1.0, 0.85, 0.3, 0.95), 2.0, 32)
	_bullet(c + Vector2(44, 12), 7, 4)   # 輪にかかる弾(かすり)
	_bullet(c + Vector2(2, 3), 6, 1)     # 当たり(中心の点に重なる)
	_ship(c, 1.5)
	draw_arc(c, 9.0, 0.0, TAU, 20, Color(1.0, 0.4, 0.42), 2.0, true)
	# 引き出し線
	var lx := ar.end.x + 18.0
	_call(c + Vector2(0, 1), Vector2(lx - 10, c.y - 70), "", Color(1.0, 0.4, 0.42))
	_t("当たり判定", Vector2(lx, c.y - 66), 14, Color(1.0, 0.45, 0.47))
	_tw("自機の中心の、小さな白い点だけ。\n三角形の見た目より、ずっと小さい", Vector2(lx, c.y - 48), w - lx - 12.0, 12, _dim())
	_call(c + Vector2(graze_r * 0.7, -graze_r * 0.7), Vector2(lx - 10, c.y - 4), "", Color(1.0, 0.85, 0.3))
	_t("グレイズの範囲", Vector2(lx, c.y), 14, Color(1.0, 0.88, 0.4))
	_tw("弾の縁がこの輪に入ると +1 回。\n同じ弾は 1 回だけ数えます", Vector2(lx, c.y + 18), w - lx - 12.0, 12, _dim())
	_call(c + Vector2(-82, -78) + Vector2(0, 7), Vector2(lx - 10, ar.position.y + 20), "", Color(1, 1, 1, 0.4))
	_t("遠い弾は、何も起きない", Vector2(lx, ar.position.y + 24), 13, _dim())
	_t("× 被弾: 触れている間だけゲージが減る", Vector2(lx, c.y + 70), 13, Color(1.0, 0.5, 0.52))


# --- 画面の見かた ---

func _hud(w: float, h: float) -> void:
	var sh := minf(minf(w - 28.0, 600.0) * 9.0 / 16.0, h - 24.0)
	var sw := sh * 16.0 / 9.0
	var o := Vector2((w - sw) * 0.5, (h - sh) * 0.5)
	var R := func(x: float, y: float, rw: float, rh: float) -> Rect2:
		return Rect2(o + Vector2(x * sw, y * sh), Vector2(rw * sw, rh * sh))
	draw_rect(Rect2(o, Vector2(sw, sh)), Color(0.05, 0.02, 0.04))
	# 左右のパネル
	var left: Rect2 = R.call(0.012, 0.03, 0.105, 0.3)
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.2), 1, 5), left)
	for k in range(3):
		draw_rect(Rect2(left.position + Vector2(6, 8 + k * 11), Vector2(left.size.x - 12 - k * 8, 4)), Color(1, 1, 1, 0.5 - k * 0.12))
	draw_style_box(UiStyle.box(Color(0.7, 0.9, 0.35, 0.9), Color(0, 0, 0, 0), 0, 9), Rect2(left.position + Vector2(6, 46), Vector2(34, 12)))
	var right: Rect2 = R.call(0.883, 0.03, 0.105, 0.3)
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.2), 1, 5), right)
	draw_rect(Rect2(right.position + Vector2(6, 8), Vector2(24, 3)), Color(1, 1, 1, 0.4))
	draw_rect(Rect2(right.position + Vector2(6, 15), Vector2(34, 8)), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(right.position + Vector2(6, 34), Vector2(30, 3)), Color(1, 1, 1, 0.4))
	draw_rect(Rect2(right.position + Vector2(6, 41), Vector2(44, 8)), Color(1, 0.8, 0.85, 0.85))
	# アリーナ
	var arena: Rect2 = R.call(0.125, 0.0, 0.75, 1.0)
	draw_rect(arena, Color(0.02, 0.022, 0.04))
	draw_rect(arena, Color(1, 1, 1, 0.3), false, 1.0)
	# 危険エリア(半面)
	var zone: Rect2 = R.call(0.125, 0.5, 0.75, 0.28)
	draw_rect(zone, Color(1.0, 0.85, 0.3, 0.14))
	draw_rect(zone, Color(1.0, 0.85, 0.3, 0.8), false, 1.5)
	# 弾
	var seed := 7
	for i in range(34):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var bx := float(seed % 1000) / 1000.0
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var by := float(seed % 1000) / 1000.0
		_bullet(arena.position + Vector2(bx * arena.size.x, 0.08 * sh + by * arena.size.y * 0.88), 2.8 + float(i % 3) * 0.7, i)
	# HP・スコア
	var hp: Rect2 = R.call(0.15, 0.05, 0.3, 0.035)
	draw_style_box(UiStyle.box(Color(0, 0, 0, 0.5), Color(1.0, 0.4, 0.42, 0.9), 1, 2), hp)
	draw_rect(Rect2(hp.position + Vector2(2, 2), Vector2((hp.size.x - 4) * 0.72, hp.size.y - 4)), Color(1.0, 0.4, 0.42))
	var sc: Rect2 = R.call(0.68, 0.04, 0.19, 0.075)
	draw_rect(sc, Color(1, 1, 1, 0.9))
	draw_rect(Rect2(sc.position + Vector2(sc.size.x * 0.4, sc.size.y + 3), Vector2(sc.size.x * 0.6, 4)), Color(1.0, 0.45, 0.65, 0.9))
	# 進み具合
	draw_rect(Rect2(o + Vector2(arena.position.x - o.x, sh - 3), Vector2(arena.size.x * 0.55, 3)), Color(1.0, 0.45, 0.7))
	# 自機
	var ship_p: Vector2 = o + Vector2(0.5 * sw, 0.9 * sh)
	_ship(ship_p, 0.9)
	_dashed_circle(ship_p, 14.0, Color(1.0, 0.85, 0.3, 0.8), 1.2, 16)
	# 番号
	_num(hp.position + Vector2(hp.size.x + 14, hp.size.y * 0.5), 1)
	_num(sc.position + Vector2(-14, sc.size.y * 0.5), 2)
	_num(right.position + Vector2(right.size.x * 0.5, right.size.y + 14), 3)
	_num(left.position + Vector2(left.size.x * 0.5, left.size.y + 14), 4)
	_num(Vector2(arena.position.x + arena.size.x * 0.55 + 14, o.y + sh - 12), 5)
	_num(zone.position + Vector2(18, zone.size.y * 0.5), 6)
	_num(ship_p + Vector2(26, 0), 7)


# --- 操作 ---

func _keys(w: float, h: float) -> void:
	var u := 34.0
	var x0 := 22.0
	var y0 := 30.0
	_t("キーボード", Vector2(x0, 22), 13, _dim())
	# WASD
	var wasd := [["W", 1, 0], ["A", 0, 1], ["S", 1, 1], ["D", 2, 1]]
	for k in wasd:
		_keycap(Rect2(x0 + u * float(k[1]) + u * float(k[1]) * 0.08, y0 + (u + 4) * float(k[2]), u, u), k[0])
	# 矢印キー
	var ax := x0 + u * 3.0 + 40.0
	var arrows := [["↑", 1, 0], ["←", 0, 1], ["↓", 1, 1], ["→", 2, 1]]
	for k in arrows:
		_keycap(Rect2(ax + u * float(k[1]) + u * float(k[1]) * 0.08, y0 + (u + 4) * float(k[2]), u, u), k[0])
	_t("または", Vector2(x0 + u * 3.0 + 2, y0 + u + 26), 11, _dim())
	var mx := ax + u * 3.4 + 14.0
	_t("移動", Vector2(mx, y0 + u + 26), 17, UiStyle.TEXT)
	# 下段: Shift / Space(1 行目)、Esc / R(2 行目)
	var rows := [
		[["Shift", 70.0, "低速", Color(0.42, 0.88, 1.0)], ["Space", 92.0, "イントロを飛ばす", Color(0.6, 1.0, 0.7)]],
		[["Esc", 54.0, "ポーズ", Color(1.0, 0.85, 0.3)], ["R", 34.0, "長押しでリトライ", Color(1.0, 0.55, 0.75)]],
	]
	for ri in range(rows.size()):
		var x := x0
		var yy := y0 + (u + 4) * 2.0 + 18.0 + 42.0 * float(ri)
		for c in rows[ri]:
			var cw: float = c[1]
			_keycap(Rect2(x, yy, cw, 30), c[0], 13, c[3])
			_t(c[2], Vector2(x + cw + 8.0, yy + 20), 13, UiStyle.TEXT)
			x += 190.0
	# マウス
	var mxr := w - 150.0
	_t("マウス(標準)", Vector2(mxr - 6, 22), 13, _dim())
	var body := Rect2(mxr + 18, y0, 56, 80)
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.5), 2, 26), body)
	draw_line(body.position + Vector2(0, 32), body.position + Vector2(body.size.x, 32), Color(1, 1, 1, 0.4), 1.0)
	draw_line(body.position + Vector2(body.size.x * 0.5, 0), body.position + Vector2(body.size.x * 0.5, 32), Color(1, 1, 1, 0.4), 1.0)
	draw_rect(Rect2(body.position + Vector2(body.size.x * 0.5 + 1, 1), Vector2(body.size.x * 0.5 - 2, 31)), Color(0.42, 0.88, 1.0, 0.35))
	for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var tip: Vector2 = body.get_center() + d * 52.0 + Vector2(0, 8)
		draw_line(body.get_center() + d * 40.0 + Vector2(0, 8), tip, Color(1.0, 0.85, 0.3), 2.0, true)
	_t("動かす = 移動", Vector2(mxr - 4, y0 + 124), 13, UiStyle.TEXT)
	_t("右クリック = 低速", Vector2(mxr - 4, y0 + 144), 13, Color(0.42, 0.88, 1.0))
	draw_line(Vector2(w - 168, 16), Vector2(w - 168, h - 16), Color(1, 1, 1, 0.1), 1.0)


# --- 特殊エリア ---

const ZONE_ORDER_TRIAL := ["slow", "fragile", "poison", "flow", "haste"]
const ZONE_ORDER_BOON := ["heal", "precise", "bonus", "warp"]
const ZONE_EFFECT := {
	"slow": "移動 0.45 倍", "fragile": "被ダメージ 2 倍", "poison": "ゲージが毎秒 10% 減る", "flow": "一定の向きへ押される", "haste": "中の弾が 1.5 倍の速さ",
	"heal": "ゲージが毎秒 5% 回復", "precise": "当たり判定 0.6 倍・移動 0.75 倍", "bonus": "グレイズの点が 2 倍", "warp": "中の弾が 0.55 倍の速さ",
}

func _zones(w: float, h: float) -> void:
	var cw := (w - 24.0 - 20.0) / 3.0
	var y := 10.0
	for g in [["試練 — 自機が不利になる", Color(1.0, 0.45, 0.45), ZONE_ORDER_TRIAL], ["恩恵 — 自機が有利になる", Color(0.5, 1.0, 0.7), ZONE_ORDER_BOON]]:
		_t(g[0], Vector2(14, y + 14), 14, g[1])
		draw_line(Vector2(14, y + 20), Vector2(w - 14, y + 20), Color(g[1].r, g[1].g, g[1].b, 0.35), 1.0)
		y += 28.0
		var list: Array = g[2]
		for i in range(list.size()):
			var cx := 12.0 + (cw + 10.0) * float(i % 3)
			var cy := y + 74.0 * float(i / 3)
			var type: String = list[i]
			var col := GameSim.zone_color(type)
			_card(Rect2(cx, cy, cw, 66), col, 0.1)
			draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, 0.18), Color(col.r, col.g, col.b, 0.8), 1, 8), Rect2(cx + 8, cy + 9, 48, 48))
			_zone_icon(type, Vector2(cx + 32, cy + 33), col, 0.78)
			_t(GameSim.zone_name(type), Vector2(cx + 64, cy + 26), 16, col)
			_tw(str(ZONE_EFFECT[type]), Vector2(cx + 64, cy + 45), cw - 70.0, 12, _dim())
		y += 74.0 * float((list.size() + 2) / 3) + 8.0


## エリアの種類を示すマーク(arena_view.gd の _draw_zone_icon と同じ形)。s = 大きさ。
func _zone_icon(type: String, c: Vector2, col: Color, s: float) -> void:
	draw_set_transform(c, 0.0, Vector2(s, s))
	match type:
		"slow":
			draw_polyline(PackedVector2Array([Vector2(-16, -16), Vector2(0, -2), Vector2(16, -16)]), col, 4.0, true)
			draw_polyline(PackedVector2Array([Vector2(-16, 2), Vector2(0, 16), Vector2(16, 2)]), col, 4.0, true)
		"fragile":
			draw_arc(Vector2.ZERO, 20.0, 0.5, TAU - 0.5, 32, col, 4.0, true)
			draw_polyline(PackedVector2Array([Vector2(4, -14), Vector2(-4, -3), Vector2(5, 4), Vector2(-3, 16)]), col, 3.0, true)
		"poison":
			draw_polyline(PackedVector2Array([Vector2(0, -22), Vector2(-13, -2)]), col, 4.0, true)
			draw_polyline(PackedVector2Array([Vector2(0, -22), Vector2(13, -2)]), col, 4.0, true)
			draw_arc(Vector2(0, 6), 13.0, -0.5, PI + 0.5, 24, col, 4.0, true)
		"heal":
			draw_line(Vector2(-17, 0), Vector2(17, 0), col, 6.0, true)
			draw_line(Vector2(0, -17), Vector2(0, 17), col, 6.0, true)
		"precise":
			draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, col, 3.0, true)
			for i in range(4):
				var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * i)
				draw_line(d * 24.0, d * 14.0, col, 3.5, true)
		"bonus":
			var star := PackedVector2Array()
			for q in range(11):
				star.append(Vector2.from_angle(-PI * 0.5 + PI * 0.2 * q) * (20.0 if q % 2 == 0 else 8.5))
			draw_polyline(star, col, 3.5, true)
		"warp":
			draw_polyline(PackedVector2Array([Vector2(-14, -18), Vector2(14, -18), Vector2.ZERO, Vector2(-14, -18)]), col, 3.5, true)
			draw_polyline(PackedVector2Array([Vector2(-14, 18), Vector2(14, 18), Vector2.ZERO, Vector2(-14, 18)]), col, 3.5, true)
		"haste":
			draw_polyline(PackedVector2Array([Vector2(6, -22), Vector2(-9, 2), Vector2(1, 2), Vector2(-6, 22), Vector2(10, -4), Vector2(0, -4)]), col, 3.5, true)
		"flow":
			for dx in [-9.0, 9.0]:
				draw_polyline(PackedVector2Array([Vector2(dx - 8.4, -9.8), Vector2(dx + 7.0, 0), Vector2(dx - 8.4, 9.8)]), col, 4.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 予告 → 発動 → 終わる直前、の見た目の移り変わり。
func _timeline(w: float, h: float) -> void:
	var col := GameSim.zone_color("bonus")
	var gap := 34.0
	var pw := (w - 28.0 - gap * 2.0) / 3.0
	var ph := h - 64.0
	var titles := [["① 予告", "点線の枠と、薄い面。\n発動に近づくほど、点滅が速くなる"], ["② 発動", "実線の太い枠と、濃い面。\nこの間だけ、効果を受ける"], ["③ 終わる直前", "枠と面が薄れて消える。\nそのあと、自機は元に戻る"]]
	for i in range(3):
		var x := 14.0 + (pw + gap) * float(i)
		var arena := Rect2(x, 12, pw, ph)
		draw_rect(arena, Color(0.02, 0.025, 0.05, 0.95))
		draw_rect(arena, Color(1, 1, 1, 0.25), false, 1.0)
		for k in range(7):
			_bullet(arena.position + Vector2(10 + float((k * 53) % int(pw - 20)), 8 + float((k * 29) % int(ph - 16))), 3.2, k)
		var zr := Rect2(arena.position + Vector2(arena.size.x * 0.3, 0), Vector2(arena.size.x * 0.7, arena.size.y))
		match i:
			0:
				draw_rect(zr, Color(col.r, col.g, col.b, 0.05))
				_dashed_rect(zr.grow(-2.0), Color(col.r, col.g, col.b, 0.9), 1.5, 5.0)
			1:
				draw_rect(zr, Color(col.r, col.g, col.b, 0.22))
				draw_rect(zr.grow(-1.5), Color(col.r, col.g, col.b, 1.0), false, 3.0)
				draw_rect(zr.grow(-4.5), Color(1, 1, 1, 0.55), false, 1.0)
			2:
				draw_rect(zr, Color(col.r, col.g, col.b, 0.08))
				draw_rect(zr.grow(-1.5), Color(col.r, col.g, col.b, 0.4), false, 2.0)
		_zone_icon("bonus", zr.get_center(), Color(col.r, col.g, col.b, [0.6, 1.0, 0.35][i]), 0.7)
		_ship(arena.position + Vector2(arena.size.x * 0.18, arena.size.y * 0.7), 0.8)
		_t(titles[i][0], Vector2(x, ph + 30), 14, UiStyle.TEXT)
		_tw(titles[i][1], Vector2(x, ph + 46), pw + gap * 0.7, 11, _dim())
		if i < 2:
			var ax := x + pw + 8.0
			draw_polyline(PackedVector2Array([Vector2(ax, 12 + ph * 0.5 - 7), Vector2(ax + 9, 12 + ph * 0.5), Vector2(ax, 12 + ph * 0.5 + 7)]), _dim(), 2.0, true)


# --- ゲージとスコア ---

func _gauge(w: float, h: float) -> void:
	var bar := Rect2(24, 52, w - 48, 26)
	var low := 0.2
	var cur := 0.62
	draw_style_box(UiStyle.box(Color(0, 0, 0, 0.55), Color(1.0, 0.4, 0.42, 0.9), 1, 4), bar)
	draw_rect(Rect2(bar.position + Vector2(3, 3), Vector2((bar.size.x - 6) * low, bar.size.y - 6)), Color(1.0, 0.35, 0.35, 0.35))
	draw_rect(Rect2(bar.position + Vector2(3, 3), Vector2((bar.size.x - 6) * cur, bar.size.y - 6)), Color(1.0, 0.4, 0.42))
	var lx := bar.position.x + 3.0 + (bar.size.x - 6.0) * low
	draw_line(Vector2(lx, bar.position.y - 8), Vector2(lx, bar.end.y + 8), Color(1, 1, 1, 0.8), 1.5)
	_t("体力のゲージ", Vector2(24, 32), 13, UiStyle.TEXT)
	_t("満タン", Vector2(bar.end.x - 60, 44), 12, _dim(), HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
	# 20% 以下
	draw_polyline(PackedVector2Array([Vector2(lx, bar.end.y + 14), Vector2(lx, bar.end.y + 24), Vector2(bar.position.x + 3, bar.end.y + 24), Vector2(bar.position.x + 3, bar.end.y + 14)]), Color(1.0, 0.5, 0.5), 1.5)
	_t("20% 以下は、被ダメージが半分", Vector2(bar.position.x, bar.end.y + 46), 13, Color(1.0, 0.55, 0.55))
	# 減る(左向きの赤い矢印)・戻る(右向きの緑の矢印)
	var ay := bar.end.y + 24.0
	var dx := bar.position.x + bar.size.x * 0.40
	var red := Color(1.0, 0.45, 0.47)
	draw_line(Vector2(dx + 60, ay), Vector2(dx - 40, ay), red, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(dx - 32, ay - 6), Vector2(dx - 42, ay), Vector2(dx - 32, ay + 6)]), red, 2.0, true)
	_t("弾に当たっている間: 減る", Vector2(dx - 60, ay + 22), 13, red)
	var rx := bar.position.x + bar.size.x * 0.76
	var green := Color(0.5, 1.0, 0.7)
	draw_line(Vector2(rx - 30, ay), Vector2(rx + 70, ay), green, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(rx + 62, ay - 6), Vector2(rx + 72, ay), Vector2(rx + 62, ay + 6)]), green, 2.0, true)
	_t("当たっていない間: 毎秒 1.5% 回復", Vector2(rx - 70, ay + 22), 13, green)


func _ranks(w: float, h: float) -> void:
	var x0 := 24.0
	var bw := w - 48.0 - 90.0
	var y := 38.0
	var stops := [["F", 0.0], ["D", 0.40], ["C", 0.55], ["B", 0.70], ["A", 0.85], ["S", 0.95], ["", 1.0]]
	_t("達成率 = 最終スコア ÷ ベーススコア", Vector2(x0, 24), 13, _dim())
	for i in range(6):
		var a: float = stops[i][1]
		var b: float = stops[i + 1][1]
		var rank: String = stops[i][0]
		var col := UiStyle.rank_color(rank)
		var r := Rect2(x0 + bw * a, y, bw * (b - a) - 2.0, 34)
		draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, 0.25), Color(col.r, col.g, col.b, 0.9), 1, 4), r)
		_t(rank, r.position + Vector2(0, 24), 18, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if i > 0:
			_t("%d%%" % int(round(a * 100.0)), Vector2(x0 + bw * a - 20.0, y + 52), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	_t("100%", Vector2(x0 + bw + 4.0, y + 24), 12, _dim())
	# SS
	var ss := UiStyle.rank_color("SS")
	var sr := Rect2(w - 24.0 - 76.0, y, 76, 34)
	draw_style_box(UiStyle.box(Color(ss.r, ss.g, ss.b, 0.3), ss, 2, 4), sr)
	_t("SS", sr.position + Vector2(0, 24), 18, ss, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x)
	_t("ノーミス", sr.position + Vector2(-8, 52), 12, ss, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x + 16.0)
	_t("被弾 0 回でクリア", Vector2(x0, h - 12), 12, _dim())
	_t("ゲームオーバーは「—」(ランクなし)", Vector2(w - 24 - 220, h - 12), 12, _dim(), HORIZONTAL_ALIGNMENT_RIGHT, 220.0)


## スコアの式: (基本点 + グレイズ) × 被ダメージ係数。
func _eq(w: float, h: float) -> void:
	var parts := [["基本点", "1,000,000", Color(0.42, 0.88, 1.0)], ["+", "", Color(1, 1, 1, 0.6)], ["グレイズ", "最大 30,000", Color(1.0, 0.85, 0.3)], ["×", "", Color(1, 1, 1, 0.6)],
		["被ダメージ係数", "1.0 → 0 に近づく", Color(1.0, 0.45, 0.47)], ["=", "", Color(1, 1, 1, 0.6)], ["最終スコア", "", Color(0.6, 1.0, 0.7)]]
	var widths := [0.19, 0.04, 0.17, 0.04, 0.22, 0.04, 0.16]
	var x := 14.0
	var avail := w - 28.0
	for i in range(parts.size()):
		var pw: float = avail * float(widths[i])
		var col: Color = parts[i][2]
		if str(parts[i][1]) == "" and i != 6:
			_t(parts[i][0], Vector2(x, h * 0.5 + 9), 24, col, HORIZONTAL_ALIGNMENT_CENTER, pw)
		else:
			_card(Rect2(x, 14, pw, h - 28), col, 0.14)
			_t(parts[i][0], Vector2(x, 40), 14, col, HORIZONTAL_ALIGNMENT_CENTER, pw)
			if str(parts[i][1]) != "":
				_t(parts[i][1], Vector2(x, 62), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, pw)
		x += pw


## Lv の色の移り変わり。
func _lv(w: float, h: float) -> void:
	var x0 := 24.0
	var bw := w - 48.0
	var top := 26.0
	var steps := 80
	for i in range(steps):
		var lv := 0.6 + (8.2 - 0.6) * float(i) / float(steps - 1)
		draw_rect(Rect2(x0 + bw * float(i) / float(steps), top, bw / float(steps) + 1.0, 22), LazerStyle.level_color(lv))
	for lv in [1, 2, 3, 4, 5, 6, 7, 8]:
		var px := x0 + bw * (float(lv) - 0.6) / (8.2 - 0.6)
		draw_line(Vector2(px, top + 22), Vector2(px, top + 28), Color(1, 1, 1, 0.6), 1.0)
		_t("Lv %d" % lv if lv in [1, 8] else str(lv), Vector2(px - 20, top + 44), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	_t("易しい", Vector2(x0, 16), 12, _dim())
	_t("難しい", Vector2(x0 + bw - 60, 16), 12, _dim(), HORIZONTAL_ALIGNMENT_RIGHT, 60.0)


# --- 選曲画面 ---

func _select(w: float, h: float) -> void:
	var sh := minf(minf(w - 28.0, 600.0) * 9.0 / 16.0, h - 24.0)
	var sw := sh * 16.0 / 9.0
	var o := Vector2((w - sw) * 0.5, (h - sh) * 0.5)
	draw_rect(Rect2(o, Vector2(sw, sh)), Color(0.05, 0.03, 0.08))
	var pink := Color(1.0, 0.4, 0.7)
	# 左: 曲の情報
	var info := Rect2(o + Vector2(0, sh * 0.08), Vector2(sw * 0.44, sh * 0.3))
	draw_style_box(UiStyle.box(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 0), info)
	draw_rect(Rect2(info.position + Vector2(12, 10), Vector2(info.size.x * 0.5, 7)), Color(1, 1, 1, 0.9))
	draw_rect(Rect2(info.position + Vector2(12, 24), Vector2(info.size.x * 0.3, 4)), Color(1, 1, 1, 0.5))
	draw_style_box(UiStyle.box(LazerStyle.level_color(4.2), Color(0, 0, 0, 0), 0, 10), Rect2(info.position + Vector2(12, 38), Vector2(46, 14)))
	for k in range(3):
		draw_rect(Rect2(o + Vector2(12, sh * 0.44 + k * 15), Vector2(sw * 0.3, 5)), Color(1, 1, 1, 0.14))
		draw_rect(Rect2(o + Vector2(12, sh * 0.44 + k * 15), Vector2(sw * (0.12 + 0.07 * k), 5)), pink)
	var rec := Rect2(o + Vector2(0, sh * 0.66), Vector2(sw * 0.42, sh * 0.2))
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1, 6), rec)
	# 右: 検索・並び替え・一覧
	var rx := o.x + sw * 0.47
	var rw := sw * 0.52
	draw_style_box(UiStyle.box(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.25), 1, 5), Rect2(rx, o.y + 6, rw * 0.3, 14))
	for k in range(6):
		var bx := rx + rw * 0.33 + (rw * 0.67 - 4.0) / 6.0 * float(k)
		var bcol := pink if k == 4 else Color(1, 1, 1, 0.18)
		draw_style_box(UiStyle.box(Color(bcol.r, bcol.g, bcol.b, 0.3), bcol, 1, 5), Rect2(bx, o.y + 6, (rw * 0.67) / 6.0 - 3.0, 14))
	var ry := o.y + sh * 0.13
	var sel_y := 0.0
	var diff_y := 0.0
	for k in range(4):
		var rr := Rect2(rx + (0.0 if k == 1 else 14.0), ry, rw - (0.0 if k == 1 else 14.0), sh * 0.1)
		draw_style_box(UiStyle.box(Color(0.35 + 0.1 * k, 0.2, 0.4, 0.55), pink if k == 1 else Color(1, 1, 1, 0.12), 2 if k == 1 else 1, 6), rr)
		draw_rect(Rect2(rr.position + Vector2(10, 6), Vector2(rr.size.x * 0.4, 5)), Color(1, 1, 1, 0.85))
		for q in range(4):
			draw_rect(Rect2(rr.position + Vector2(10 + q * 9, rr.size.y - 10), Vector2(7, 4)), LazerStyle.level_color(2.0 + q * 1.4))
		ry += sh * 0.1 + 6.0
		if k == 1:   # 開いた難易度の一覧
			sel_y = rr.position.y + rr.size.y * 0.5
			diff_y = ry + sh * 0.05
			for q in range(3):
				var dr := Rect2(rx + 22, ry, rw - 22, sh * 0.062)
				draw_style_box(UiStyle.box(Color(0, 0, 0, 0.5), LazerStyle.level_color(3.0 + q * 1.6), 1, 5), dr)
				draw_style_box(UiStyle.box(LazerStyle.level_color(3.0 + q * 1.6), Color(0, 0, 0, 0), 0, 8), Rect2(dr.position + Vector2(5, 3), Vector2(30, dr.size.y - 6)))
				ry += sh * 0.062 + 4.0
			ry += 2.0
	# 下: ボタン
	var bcols := [pink, Color(0.6, 0.35, 1.0), Color(0.3, 0.75, 1.0), Color(0.5, 0.5, 0.6), Color(1.0, 0.85, 0.3)]
	for k in range(5):
		var by := o.y + sh - 16.0
		var bx2 := o.x + (sw / 5.0) * float(k) + (0.0 if k < 4 else 0.0)
		draw_rect(Rect2(bx2, by, sw / 5.0 - 3.0 if k < 4 else sw / 5.0, 16), Color(bcols[k].r, bcols[k].g, bcols[k].b, 0.8))
	# 番号
	_num(Vector2(rx + rw * 0.15, o.y + 6 + 7), 1)
	_num(Vector2(rx + rw * 0.33 + (rw * 0.67) / 6.0 * 4.5, o.y - 4), 2)
	_num(Vector2(rx + rw * 0.55, sel_y), 3)
	_num(Vector2(rx + 6, diff_y), 4)
	_num(Vector2(o.x + 6, o.y + sh * 0.08 + 4), 5)
	_num(Vector2(o.x + sw * 0.42 - 12, o.y + sh * 0.66 + sh * 0.1), 6)
	_num(Vector2(o.x + sw * 0.9, o.y + sh - 28), 7)


# --- マルチプレイ ---

func _multi(w: float, h: float) -> void:
	var half := w * 0.5
	var pink := Color(1.0, 0.45, 0.65)
	var cy := 30.0
	_t("対戦 — 各自の画面で、同じ弾幕をよける", Vector2(14, 22), 14, Color(1.0, 0.7, 0.4))
	_t("協力 — 全員が同じ盤面で、体力を共有する", Vector2(half + 14, 22), 14, Color(0.5, 1.0, 0.7))
	draw_line(Vector2(half, 12), Vector2(half, h - 12), Color(1, 1, 1, 0.1), 1.0)
	# 対戦: 小さな盤面が 2 つ
	var aw := (half - 14.0 - 28.0 - 14.0) / 2.0
	for i in range(2):
		var ar := Rect2(14.0 + (aw + 14.0) * float(i), cy + 8, aw, 118)
		draw_rect(ar, Color(0.02, 0.025, 0.05, 0.95))
		draw_rect(ar, Color(1, 1, 1, 0.3), false, 1.0)
		for k in range(6):
			_bullet(ar.position + Vector2(10 + float((k * 41 + i * 17) % int(aw - 20)), 10 + float((k * 23 + i * 31) % 70)), 3.5, k + i)
		_ship(ar.position + Vector2(aw * (0.4 + 0.2 * float(i)), 100), 0.9, [Color(0.42, 0.88, 1.0), Color(1.0, 0.7, 0.4)][i])
		_t(["あなた", "友達"][i], Vector2(ar.position.x, ar.end.y + 16), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, aw)
		_t(["912,400", "874,200"][i], Vector2(ar.position.x, ar.end.y + 34), 13, UiStyle.TEXT if i == 0 else _dim(), HORIZONTAL_ALIGNMENT_CENTER, aw)
	_t("スコアの高い人の勝ち", Vector2(14, h - 12), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, half - 28.0)
	# 協力: 1 つの盤面に 3 人
	var ar2 := Rect2(half + 14.0, cy + 8, half - 28.0, 118)
	draw_rect(ar2, Color(0.02, 0.025, 0.05, 0.95))
	draw_rect(ar2, Color(1, 1, 1, 0.3), false, 1.0)
	for k in range(9):
		_bullet(ar2.position + Vector2(12 + float((k * 47) % int(ar2.size.x - 24)), 12 + float((k * 29) % 72)), 3.5, k)
	for i in range(3):
		_ship(ar2.position + Vector2(ar2.size.x * (0.25 + 0.25 * float(i)), 98 - 10.0 * float(i % 2)), 0.9, [Color(0.42, 0.88, 1.0), Color(1.0, 0.7, 0.4), Color(0.6, 1.0, 0.7)][i])
	var hp := Rect2(ar2.position + Vector2(8, 6), Vector2(ar2.size.x * 0.5, 8))
	draw_style_box(UiStyle.box(Color(0, 0, 0, 0.5), Color(1.0, 0.4, 0.42, 0.9), 1, 2), hp)
	draw_rect(Rect2(hp.position + Vector2(1, 1), Vector2((hp.size.x - 2) * 0.7, hp.size.y - 2)), Color(1.0, 0.4, 0.42))
	_t("全員で 1 本の体力", Vector2(half + 14, ar2.end.y + 16), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, half - 28.0)
	_t("最後まで残ればクリア", Vector2(half + 14, h - 12), 12, _dim(), HORIZONTAL_ALIGNMENT_CENTER, half - 28.0)


# --- 曲の追加 ---

func _songs(w: float, h: float) -> void:
	var gap := 14.0
	var cw := (w - 24.0 - gap * 2.0) / 3.0
	var items := [["songs フォルダ", ".osz を入れる", Color(1.0, 0.85, 0.3)], ["ドラッグ&ドロップ", "選曲画面に落とす", Color(0.42, 0.88, 1.0)], ["osu! の曲", "設定で、そのまま使う", Color(1.0, 0.55, 0.75)]]
	for i in range(3):
		var x := 12.0 + (cw + gap) * float(i)
		var col: Color = items[i][2]
		_card(Rect2(x, 12, cw, h - 24), col)
		var c := Vector2(x + 38, h * 0.5)
		match i:
			0:   # フォルダ
				draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, 0.25), col, 2, 4), Rect2(c + Vector2(-22, -12), Vector2(44, 30)))
				draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, 0.5), col, 2, 3), Rect2(c + Vector2(-22, -18), Vector2(18, 8)))
			1:   # 書類が窓へ
				draw_style_box(UiStyle.box(Color(1, 1, 1, 0.06), col, 2, 4), Rect2(c + Vector2(-8, -16), Vector2(32, 32)))
				draw_style_box(UiStyle.box(Color(col.r, col.g, col.b, 0.35), col, 2, 3), Rect2(c + Vector2(-26, -22), Vector2(18, 24)))
				draw_polyline(PackedVector2Array([c + Vector2(-8, 2), c + Vector2(2, 2)]), col, 2.0, true)
			2:   # 円盤
				draw_arc(c, 17.0, 0.0, TAU, 28, col, 3.0, true)
				draw_circle(c, 5.0, col)
		_t(items[i][0], Vector2(x + 70, h * 0.5 - 2), 13, col)
		_tw(items[i][1], Vector2(x + 70, h * 0.5 + 18), cw - 76.0, 12, _dim())
