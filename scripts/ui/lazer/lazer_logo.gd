extends Control
## 「Danmaku」のロゴ。すべて描画で作る(画像・フォントなし)。円盤の中が、小さな弾幕の場面になっている:
##   台座 … 光が左上から当たったような、ピンクのグラデーションの円盤。白い太い縁と、下に落ちるやわらかい影。上半分に、うすい艶。
##   上 … 発射口(小さな輪)から、扇形に弾が下へ流れる(文字の帯に近づくと薄れる)。
##   中 … 「Danmaku」の文字(丸い端の太い線。影つき)。
##   下 … 自機(矢じり)と、当たり判定の黄色い点。弾をよけるように、ゆっくり左右へ揺れる。
##   周り … 欠けのある輪(端ほど薄い)がゆっくり回り、その外を、ゲームと同じ形の弾(色の輪 + 白い芯)が、尾を引いて周回する。
## 動きはゆっくりした回転・流れ・揺れと、ごくわずかな拍動だけ(点滅・フラッシュはしない)。押せる(pressed)。マウスが乗ると少し大きくなり、弾が少し速くなる。

signal pressed

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const BULLET_COLORS := [LazerStyle.PINK, LazerStyle.BLUE, LazerStyle.PURPLE, LazerStyle.YELLOW, LazerStyle.GREEN]
const LIGHT := Vector2(-0.6, -0.8)   # 光の来る向き(左上)
const DISC_R := 122.0                # 台座の半径(380 のとき)

var _t := 0.0
var _spin := 0.0     # 周回・弾の流れの進み(マウスが乗ると速くなる)
var _hover := 0.0
var _hover_target := 0.0
var _press := 0.0


func _init(p_size := 380.0) -> void:
	custom_minimum_size = Vector2(p_size, p_size)
	size = Vector2(p_size, p_size)
	pivot_offset = Vector2(p_size, p_size) * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _ready() -> void:
	mouse_entered.connect(func(): _hover_target = 1.0)
	mouse_exited.connect(func(): _hover_target = 0.0; _press = 0.0)
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press = 1.0
			elif _press > 0.0:
				_press = 0.0
				pressed.emit())
	set_process(true)


func _process(delta: float) -> void:
	if not UiStyle.animate:
		return
	_t += delta
	_hover = lerpf(_hover, _hover_target, 1.0 - exp(-delta * 9.0))
	_spin += delta * (1.0 + 0.8 * _hover)
	var s := 1.0 + 0.035 * _hover - 0.03 * _press
	scale = Vector2(s, s)
	queue_redraw()


func _draw() -> void:
	var u := size.x / 380.0   # 380 を基準にした倍率
	var c := size * 0.5
	var breath := 1.0 + 0.008 * sin(_t * 1.6)   # ごくゆっくりした拍動
	var pink := LazerStyle.PINK
	# いちばん外の、細い輪
	draw_arc(c, 186.0 * u, 0.0, TAU, 128, Color(1, 1, 1, 0.10), 1.5 * u, true)
	# 欠けのある輪(6 つの弧。進む向きの先端ほど濃い)
	for i in range(6):
		var a0 := _spin * 0.12 + float(i) * TAU / 6.0
		var span := TAU / 6.0 * 0.66
		for k in range(8):
			var f0 := float(k) / 8.0
			draw_arc(c, 160.0 * u, a0 + span * f0, a0 + span * (f0 + 0.13), 6, Color(pink.r, pink.g, pink.b, 0.12 + 0.5 * f0), 4.0 * u, true)
	# 周回する弾(外は反時計回り・尾つき、内は時計回りの小さな弾)
	for i in range(14):
		var a := -_spin * 0.2 + float(i) * TAU / 14.0
		var col: Color = BULLET_COLORS[i % BULLET_COLORS.size()]
		var r := (173.0 + 4.0 * sin(float(i) * 1.7)) * u
		for j in range(1, 5):   # 尾(進む向きの後ろに、薄くなる影)
			var aj := a + 0.035 * float(j)
			draw_circle(c + Vector2.from_angle(aj) * r, (4.6 - 0.7 * float(j)) * u, Color(col.r, col.g, col.b, 0.22 - 0.045 * float(j)))
		_bullet(c + Vector2.from_angle(a) * r, 6.0 * u, col)
	for i in range(10):
		var a2 := _spin * 0.32 + float(i) * TAU / 10.0
		var col2: Color = BULLET_COLORS[(i * 2 + 1) % BULLET_COLORS.size()]
		_bullet(c + Vector2.from_angle(a2) * 143.0 * u, 3.4 * u, Color(col2.r, col2.g, col2.b, 0.9))
	# 台座: 影 → 白い縁 → グラデーションの円盤
	var rr := DISC_R * u * breath
	for k in range(6):   # やわらかい影(少し下へ)
		draw_circle(c + Vector2(0, 7.0 * u), rr + (14.0 - 2.0 * k) * u, Color(0.05, 0.0, 0.06, 0.06))
	draw_circle(c, rr + 7.0 * u, Color(1, 1, 1, 0.95))
	_disc(c, rr, pink.lightened(0.28), pink.darkened(0.30))
	var word_y := c.y + 4.0 * u   # 文字の帯の中心
	_draw_fan(c, rr, word_y, u)
	_draw_ship(c, rr, u)
	# 内側の縁(細い白い輪)と、上半分の艶
	draw_arc(c, rr - 10.0 * u, 0.0, TAU, 96, Color(1, 1, 1, 0.5), 2.0 * u, true)
	_gloss(c, rr - 4.0 * u)
	# 文字「Danmaku」(影 → 白)
	var xh := 26.0 * u   # 小文字の高さ
	var w := 7.2 * u     # 線の太さ
	var base := word_y + xh * 0.5 + 3.0 * u
	var total := _word(Vector2.ZERO, xh, w, Color(0, 0, 0, 0), true)
	var x0 := c.x - total * 0.5
	_word(Vector2(x0, base + 3.5 * u), xh, w, Color(0.35, 0.02, 0.16, 0.45))
	_word(Vector2(x0, base), xh, w, Color.WHITE)


## 上の発射口から、扇形に下へ流れる弾。円盤の縁と、文字の帯に近づくと薄れる。
func _draw_fan(c: Vector2, rr: float, word_y: float, u: float) -> void:
	var e := c + Vector2(0, -rr * 0.62)
	draw_arc(e, 7.0 * u, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 2.0 * u, true)   # 発射口
	draw_circle(e, 2.6 * u, Color(1, 1, 1, 0.9))
	for j in range(7):
		var dir := Vector2.from_angle(PI * 0.5 + (float(j) - 3.0) * 0.30)
		for k in range(4):
			var d := fposmod(_spin * 34.0 + float(k) * 30.0 + float(j % 2) * 15.0, 120.0) * u + 12.0 * u
			var p := e + dir * d
			var edge := 1.0 - smoothstep(rr - 26.0 * u, rr - 12.0 * u, p.distance_to(c))
			var band := smoothstep(14.0 * u, 30.0 * u, absf(p.y - word_y))
			var a := 0.65 * smoothstep(12.0 * u, 26.0 * u, d) * edge * band
			if a > 0.02:
				draw_circle(p, 4.6 * u, Color(1, 1, 1, 0.16 * a))
				draw_circle(p, 3.0 * u, Color(1, 1, 1, a))


## 下の自機(矢じり)と当たり判定の点。弾をよけるように、ゆっくり左右へ揺れる。
func _draw_ship(c: Vector2, rr: float, u: float) -> void:
	var p := c + Vector2(sin(_t * 0.9) * 14.0 * u, rr * 0.58)
	var s := 15.0 * u
	var tip := p + Vector2(0, -s)
	var pts := PackedVector2Array([tip, p + Vector2(s * 0.78, s * 0.72), p + Vector2(0, s * 0.32), p + Vector2(-s * 0.78, s * 0.72)])
	draw_colored_polygon(PackedVector2Array([pts[0] + Vector2(0, 3 * u), pts[1] + Vector2(0, 3 * u), pts[2] + Vector2(0, 3 * u), pts[3] + Vector2(0, 3 * u)]), Color(0.35, 0.02, 0.16, 0.4))
	draw_colored_polygon(pts, Color.WHITE)
	draw_arc(p + Vector2(0, 2.0 * u), 6.0 * u, 0.0, TAU, 24, Color(LazerStyle.YELLOW.r, LazerStyle.YELLOW.g, LazerStyle.YELLOW.b, 0.9), 1.6 * u, true)
	draw_circle(p + Vector2(0, 2.0 * u), 3.0 * u, LazerStyle.YELLOW)


## ゲームと同じ形の弾(色の輪 + 白い芯 + うすい光)。
func _bullet(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p, r * 1.7, Color(col.r, col.g, col.b, 0.14 * col.a))
	draw_circle(p, r, col)
	draw_circle(p, r * 0.55, Color(1, 1, 1, 0.92 * col.a))


## 光が左上から当たったような円盤(扇形を 1 枚ずつ、縁の色を向きで変えて塗る。中心は 2 色の間)。
func _disc(c: Vector2, r: float, light: Color, dark: Color) -> void:
	var n := 72
	var mid := light.lerp(dark, 0.45)
	var ld := LIGHT.normalized()
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := Vector2.from_angle(a0)
		var d1 := Vector2.from_angle(a1)
		var c0 := dark.lerp(light, (d0.dot(ld) + 1.0) * 0.5)
		var c1 := dark.lerp(light, (d1.dot(ld) + 1.0) * 0.5)
		draw_polygon(PackedVector2Array([c, c + d0 * r, c + d1 * r]), PackedColorArray([mid, c0, c1]))


## 上半分の艶(上ほど明るく、中ほどで消える、横長の帯)。
func _gloss(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 24
	for i in range(n + 1):   # 上の弧(左から右へ)
		var a := PI + PI * float(i) / float(n)
		pts.append(c + Vector2.from_angle(a) * r)
		cols.append(Color(1, 1, 1, 0.0 if i == 0 or i == n else 0.14))
	for i in range(n + 1):   # 下のゆるい弧(右から左へ。中ほどの高さ)
		var a := PI * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * r * 0.86, -r * 0.08 - sin(a) * r * 0.22))
		cols.append(Color(1, 1, 1, 0.0))
	draw_polygon(pts, cols)


# --- 文字(丸い端の太い線で描く、幾何学的な字形) ---

## 「Danmaku」を、o(左端・ベースライン)から描く。全体の幅を返す。measure = true なら描かずに幅だけ。
func _word(o: Vector2, xh: float, w: float, col: Color, measure := false) -> float:
	var cap := xh * 1.4
	var gap := 3.6 * (w / 7.2)
	var x := o.x
	for ch in "Danmaku":
		var adv := 0.0
		match ch:
			"D": adv = _g_d(Vector2(x, o.y), cap, w, col, measure)
			"a": adv = _g_a(Vector2(x, o.y), xh, w, col, measure)
			"n": adv = _g_n(Vector2(x, o.y), xh, w, col, 1, measure)
			"m": adv = _g_n(Vector2(x, o.y), xh, w, col, 2, measure)
			"k": adv = _g_k(Vector2(x, o.y), xh, cap, w, col, measure)
			"u": adv = _g_u(Vector2(x, o.y), xh, w, col, measure)
		x += adv + gap
	return x - gap - o.x


## 線 pts(折れ線)を、太さ w・丸い端と丸い継ぎ目で描く。
func _stroke(pts: PackedVector2Array, w: float, col: Color) -> void:
	draw_polyline(pts, col, w, true)
	for p in pts:
		draw_circle(p, w * 0.5, col)


func _arc_pts(center: Vector2, r: float, a0: float, a1: float, n := 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1):
		pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n))) * r)
	return pts


## 大文字の D(高さ h)。
func _g_d(o: Vector2, h: float, w: float, col: Color, measure: bool) -> float:
	var adv := h * 0.66
	if measure:
		return adv
	var r := h * 0.5 - w * 0.5
	var top := Vector2(o.x + w * 0.5, o.y - h + w * 0.5)
	var bot := Vector2(o.x + w * 0.5, o.y - w * 0.5)
	var k := adv - w - r
	var pts := PackedVector2Array([bot, top, top + Vector2(k, 0)])
	pts.append_array(_arc_pts(top + Vector2(k, r), r, -PI * 0.5, PI * 0.5, 16))
	pts.append(bot)
	_stroke(pts, w, col)
	return adv


## 小文字の a(1 階建て: 丸い胴と、右の縦線)。
func _g_a(o: Vector2, xh: float, w: float, col: Color, measure: bool) -> float:
	var r := xh * 0.5 - w * 0.5   # 胴は x の高さいっぱいの円
	var adv := 2.0 * r + w
	if measure:
		return adv
	var center := Vector2(o.x + w * 0.5 + r, o.y - xh * 0.5)
	var circ := _arc_pts(center, r, 0.0, TAU, 28)
	draw_polyline(circ, col, w, true)
	var sx := center.x + r   # 縦線は胴の右端に重なる
	_stroke(PackedVector2Array([Vector2(sx, o.y - xh + w * 0.5), Vector2(sx, o.y - w * 0.5)]), w, col)
	return adv


## 小文字の n(arches = 1)と m(arches = 2): 左の縦線と、上が丸いアーチ。
func _g_n(o: Vector2, xh: float, w: float, col: Color, arches: int, measure: bool) -> float:
	var r := xh * (0.38 if arches == 1 else 0.30)
	var adv := 2.0 * r * float(arches) + w
	if measure:
		return adv
	var x0 := o.x + w * 0.5
	var cy := o.y - xh + w * 0.5 + r
	_stroke(PackedVector2Array([Vector2(x0, o.y - xh + w * 0.5), Vector2(x0, o.y - w * 0.5)]), w, col)
	for i in range(arches):
		var cx := x0 + r + 2.0 * r * float(i)
		var pts := _arc_pts(Vector2(cx, cy), r, PI, TAU, 14)
		pts.append(Vector2(cx + r, o.y - w * 0.5))
		_stroke(pts, w, col)
	return adv


## 小文字の k: 背の高い縦線と、斜めの 2 本。
func _g_k(o: Vector2, xh: float, cap: float, w: float, col: Color, measure: bool) -> float:
	var adv := xh * 0.74
	if measure:
		return adv
	var x0 := o.x + w * 0.5
	_stroke(PackedVector2Array([Vector2(x0, o.y - cap + w * 0.5), Vector2(x0, o.y - w * 0.5)]), w, col)
	var mid := Vector2(x0 + w * 0.2, o.y - xh * 0.40)
	_stroke(PackedVector2Array([Vector2(o.x + adv - w * 0.5, o.y - xh + w * 0.5), mid, Vector2(o.x + adv - w * 0.4, o.y - w * 0.5)]), w, col)
	return adv


## 小文字の u: 下が丸く、右の縦線はベースラインまで。
func _g_u(o: Vector2, xh: float, w: float, col: Color, measure: bool) -> float:
	var r := xh * 0.38
	var adv := 2.0 * r + w
	if measure:
		return adv
	var x0 := o.x + w * 0.5
	var cy := o.y - w * 0.5 - r
	var pts := PackedVector2Array([Vector2(x0, o.y - xh + w * 0.5)])
	pts.append_array(_arc_pts(Vector2(x0 + r, cy), r, PI, 0.0, 14))
	pts.append(Vector2(x0 + 2.0 * r, o.y - xh + w * 0.5))
	_stroke(pts, w, col)
	_stroke(PackedVector2Array([Vector2(x0 + 2.0 * r, o.y - xh + w * 0.5), Vector2(x0 + 2.0 * r, o.y - w * 0.5)]), w, col)
	return adv
