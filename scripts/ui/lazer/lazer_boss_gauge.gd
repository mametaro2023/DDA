extends "res://scripts/ui/boss_gauge.gd"
## lazer 風のボスのゲージと WARNING。時間の流れ・当たり・節目・撃破の判定(tick)は classic(boss_gauge.gd)のものをそのまま使い、描き方だけを変える。
## 位置と大きさ(X / Y / W / H)も同じ(自機が近づくと薄くなる範囲が、classic と同じになる)。
##   ゲージ … 丸い端の細いバー(体力バーと同じ形)。左に「BOSS」の札、右に残りの割合。節目(75 / 50 / 25%)は細い縦線
##   残りが少ない … 色が赤から橙へ移り、下の光が強くなる(脈打たない)
##   WARNING … フィールド中央の暗い帯と、上下の細い赤い線。両側から「›››」が中央へ流れ込む。文字は字間を広げて
##   撃破 … 白く光らせず、ゲージが金色の粒になって散り、「DEFEATED」が浮かぶ

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")

const C_FULL := Color(1.0, 0.33, 0.45)    # 残りが多いとき(ピンクがかった赤)
const C_LOW := Color(1.0, 0.62, 0.25)     # 残りが少ないとき(橙)


func _ready() -> void:
	super._ready()
	_font = LazerStyle.font_bold()


func _draw() -> void:
	if boss == null:
		return
	_draw_banner()
	if _drop <= 0.001:
		return
	if _break_t >= 0.0:
		_draw_break()
		return
	var e := 1.0 - pow(1.0 - _drop, 3.0)
	var a := e
	var y := Y - 30.0 * (1.0 - e)
	var f := _shown()
	var col := C_LOW.lerp(C_FULL, smoothstep(0.15, 0.6, _disp))
	var low := 1.0 - smoothstep(0.2, 0.3, _disp)
	var h := 10.0
	var by := y + (H - h) * 0.5
	# 見出し: 左に「BOSS」の札、右に残りの割合
	var tag_w := _font.get_string_size("BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
	draw_style_box(LazerStyle.box(Color(col.r, col.g, col.b, 0.9 * a), Color(0, 0, 0, 0), 0, 999), Rect2(X, y - 24.0, tag_w, 18.0))
	draw_string(_font, Vector2(X + 8.0, y - 10.5), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.18, 0.03, 0.06, a))
	var pct_v := _disp * 100.0 * (1.0 - pow(1.0 - _charge, 3.0))
	var big := "%d" % int(floor(pct_v))
	var small := ".%d%%" % (int(floor(pct_v * 10.0)) % 10)
	var sw := _font.get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(_font, Vector2(X + W - sw, y - 9.0), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6 * a))
	draw_string(_font, Vector2(X + W - sw - 200.0, y - 9.0), big, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 18, Color(1, 1, 1, 0.95 * a))
	# 溝(丸い端)
	draw_style_box(LazerStyle.box(Color(0.03, 0.025, 0.06, 0.7 * a), Color(1, 1, 1, 0.16 * a), 1, 9), Rect2(X - 3.0, by - 3.0, W + 6.0, h + 6.0))
	# 下の光(残りが少ないほど強い。脈打たない)
	if f > 0.001:
		var ga := (0.12 + 0.2 * low) * a
		draw_polygon(PackedVector2Array([Vector2(X, by + h + 3.0), Vector2(X + W * f, by + h + 3.0), Vector2(X + W * f, by + h + 15.0), Vector2(X, by + h + 15.0)]),
			PackedColorArray([Color(col.r, col.g, col.b, ga), Color(col.r, col.g, col.b, ga), Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))
	# 残像(減った分の白。ゆっくり縮む)
	if _ghost > f + 0.0005 and _charge >= 1.0:
		var gx := X + W * f
		var gw := W * (_ghost - f)
		draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.36 * a), Color(0, 0, 0, 0), 0, 5), Rect2(gx - 5.0, by, gw + 5.0, h))
	if f > 0.001:
		var fw := maxf(W * f, h)
		var fc := col.lerp(Color.WHITE, 0.25 * _hit)
		draw_style_box(LazerStyle.box(Color(fc.r, fc.g, fc.b, a), Color(0, 0, 0, 0), 0, 5), Rect2(X, by, fw, h))
		draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.24 * a), Color(0, 0, 0, 0), 0, 2), Rect2(X + 3.0, by + 1.5, maxf(fw - 6.0, 0.0), 2.5))   # 上面の艶
		# 流れる光(ゆっくり右へ)
		var cx := _flow - 80.0
		var x0 := clampf(cx - 50.0, 0.0, fw - 4.0)
		var x1 := clampf(cx + 50.0, 0.0, fw - 4.0)
		if x1 - x0 > 1.0:
			var lo := Color(1, 1, 1, 0.0)
			var hi := Color(1, 1, 1, 0.16 * a)
			var mid := (x0 + x1) * 0.5
			draw_polygon(PackedVector2Array([Vector2(X + x0, by + 1), Vector2(X + mid, by + 1), Vector2(X + mid, by + h - 1), Vector2(X + x0, by + h - 1)]), PackedColorArray([lo, hi, hi, lo]))
			draw_polygon(PackedVector2Array([Vector2(X + mid, by + 1), Vector2(X + x1, by + 1), Vector2(X + x1, by + h - 1), Vector2(X + mid, by + h - 1)]), PackedColorArray([hi, lo, lo, hi]))
		# 節目で走る光
		if _sweep >= 0.0:
			var sx := clampf(W * _sweep, 0.0, fw)
			var sa := sin(PI * _sweep) * 0.5 * a
			draw_polygon(PackedVector2Array([Vector2(X + maxf(sx - 70.0, 0.0), by), Vector2(X + sx, by), Vector2(X + sx, by + h), Vector2(X + maxf(sx - 70.0, 0.0), by + h)]),
				PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, sa), Color(1, 1, 1, sa), Color(1, 1, 1, 0.0)]))
		# 先端: やわらかい光(命中で少し大きく)
		var tip := Vector2(X + fw, by + h * 0.5)
		draw_circle(tip, 8.0 + 6.0 * _hit, Color(col.r, col.g, col.b, (0.16 + 0.24 * _hit) * a))
		draw_circle(tip, 2.5 + 1.5 * _hit, Color(1, 1, 1, (0.6 + 0.35 * _hit) * a))
	# 節目(細い縦線。越えたら暗くなり、越えた瞬間に輪が広がる)
	for ph in PHASES:
		var px: float = X + W * ph
		var done := _phase_done.has(ph)
		draw_line(Vector2(px, by - 5.0), Vector2(px, by + h + 5.0), Color(1, 1, 1, (0.22 if done else 0.7) * a), 2.0, true)
	for fx in _phase_fx:
		var k: float = fx.t / 0.9
		var px: float = X + W * float(fx.f)
		var ee := 1.0 - pow(1.0 - k, 3.0)
		draw_arc(Vector2(px, by + h * 0.5), 6.0 + 40.0 * ee, 0.0, TAU, 36, Color(1, 1, 1, 0.7 * (1.0 - k) * a), 2.0, true)
	for s in _sparks:
		var k: float = s.life / s.max
		var sc: Color = s.col
		draw_line(s.p, s.p - s.v * 0.03, Color(sc.r, sc.g, sc.b, k * 0.6), 1.4, true)
		draw_circle(s.p, 1.0 + 1.0 * k, Color(sc.r, sc.g, sc.b, k))


## WARNING の帯(フィールド中央): 中央から上下に開く暗い帯・上下の細い赤い線・両側から中央へ流れる「›」の列・字間の広い文字。
func _draw_banner() -> void:
	var tb: float = now - (float(boss.appear_t) - 1.2)
	if tb < 0.0 or tb > 2.6:
		return
	var env := smoothstep(0.0, 0.35, tb) * (1.0 - smoothstep(2.1, 2.6, tb))
	if env < 0.004:
		return
	var red := LazerStyle.RED.lerp(Color(1.0, 0.35, 0.42), 0.4)
	var open := 1.0 - pow(1.0 - clampf(tb / 0.4, 0.0, 1.0), 3.0)
	var hh := 62.0 * open
	draw_rect(Rect2(ARENA_X0, BANNER_Y - hh, ARENA_W, hh * 2.0), Color(0.07, 0.01, 0.04, 0.78 * env))
	for sy in [BANNER_Y - hh, BANNER_Y + hh - 2.0]:
		draw_rect(Rect2(ARENA_X0, sy, ARENA_W, 2.0), Color(red.r, red.g, red.b, 0.85 * env))
	# 両側から中央へ流れ込む「›」の列(中央の文字の手前で消える)
	var cx := ARENA_X0 + ARENA_W * 0.5
	for side in [-1.0, 1.0]:
		for i in range(9):
			var d := fposmod(tb * 90.0 + float(i) * 40.0, 360.0)   # 中央へ近づく距離
			var x: float = cx + side * (560.0 - d)
			var fade := smoothstep(0.0, 60.0, d) * (1.0 - smoothstep(250.0, 330.0, d))
			if fade <= 0.01 or absf(x - cx) > ARENA_W * 0.5 - 8.0:
				continue
			var ca := Color(red.r, red.g, red.b, 0.55 * fade * env)
			var s := 9.0
			draw_polyline(PackedVector2Array([Vector2(x + side * s * 0.6, BANNER_Y - s), Vector2(x - side * s * 0.6, BANNER_Y), Vector2(x + side * s * 0.6, BANNER_Y + s)]), ca, 3.0, true)
	# 文字(少し大きいところから収まる)
	var sc := lerpf(1.12, 1.0, 1.0 - pow(1.0 - clampf(tb / 0.5, 0.0, 1.0), 3.0))
	_spaced(Vector2(cx, BANNER_Y + 14.0), "WARNING", int(round(46.0 * sc)), 10.0 * sc, Color(red.r, red.g, red.b, env).lerp(Color.WHITE, 0.12))
	_spaced(Vector2(cx, BANNER_Y + 40.0), "BOSS APPROACHING", 12, 5.0, Color(1, 0.88, 0.9, 0.7 * env))


## 字間を広げた 1 行を、center を中心に描く(y はベースライン)。
func _spaced(center: Vector2, text: String, fs: int, gap: float, col: Color) -> void:
	var widths: Array = []
	var total := 0.0
	for i in range(text.length()):
		var w := _font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(w)
		total += w + (gap if i < text.length() - 1 else 0.0)
	var x := center.x - total * 0.5
	for i in range(text.length()):
		draw_string(_font, Vector2(x, center.y), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += float(widths[i]) + gap


## 撃破: 白く光らせず、ゲージが金色の粒になって散り、「DEFEATED」が少し上へ浮かびながら現れて消える。
func _draw_break() -> void:
	var t := _break_t
	var gold := LazerStyle.YELLOW
	var a := clampf(1.0 - (t - 0.18) / 1.1, 0.0, 1.0)
	if t < 0.18:   # 砕ける前: ゲージの形のまま、金色に変わる
		var k := t / 0.18
		var c := C_FULL.lerp(gold, k)
		draw_style_box(LazerStyle.box(Color(c.r, c.g, c.b, 1.0), Color(0, 0, 0, 0), 0, 5), Rect2(X, Y + (H - 10.0) * 0.5, W, 10.0))
	elif a > 0.0:
		for sh in _shards:
			var w: float = sh.w
			var r := Rect2(sh.p - Vector2(w * 0.5, 5.0), Vector2(w, 10.0))
			draw_set_transform(sh.p, sh.rot, Vector2.ONE)
			draw_style_box(LazerStyle.box(Color(gold.r, gold.g, gold.b, 0.8 * a), Color(0, 0, 0, 0), 0, 5), Rect2(r.position - sh.p, r.size))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ta := smoothstep(0.1, 0.35, t) * (1.0 - smoothstep(1.2, 1.6, t))
	if ta > 0.0:
		var rise := 8.0 * (1.0 - smoothstep(0.1, 0.6, t))
		_spaced(Vector2(X + W * 0.5, Y + 16.0 + rise), "DEFEATED", 22, 8.0, Color(gold.r, gold.g, gold.b, ta))
