extends Node2D
## 撃破 MOD: フィールド上部の、ボスの体力ゲージと、登場の WARNING。game_screen が毎フレーム tick を呼ぶ(画面座標で描く)。
##
## 時間の流れ(boss.appear_t = ボスが盤面の上の外から降りてき始める時刻):
##   appear_t − 1.2 〜 + 1.4   WARNING: フィールド中央に暗い帯・流れる警告の縞・「WARNING」。なめらかに出入りする(点滅なし)
##   appear_t − 0.3 〜        ゲージの枠が上から降りてきて現れ、続いて HP が左から満ちていく(チャージ)
## 戦闘中:
##   命中 … 先端が光り、火花が散る。減った分は白い残像が少し遅れて縮む
##   75% / 50% / 25% の節目 … 目印のひし形が弾けて輪が広がり、ゲージに光が走る
##   25% 以下 … ゲージの下の光が、ゆっくり脈打つ
##   撃破 … ゲージが白く光ってから、破片になって砕け散る

signal warned          # WARNING が出始めた(重い音を鳴らす)
signal phase_crossed   # 節目を越えた

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const X := 216.0
const Y := 32.0
const W := 848.0
const H := 16.0
const SL := 12.0
const PHASES := [0.75, 0.5, 0.25]
const COL_FULL := Color(1.0, 0.24, 0.36)    # 残りが多いとき(深紅)
const COL_LOW := Color(1.0, 0.62, 0.18)     # 残りが少ないとき(灼けた橙)
const BANNER_Y := 300.0                      # WARNING の帯の中心(画面座標)
const ARENA_X0 := 160.0
const ARENA_W := 960.0

var boss
var now := 0.0

var _drop := 0.0         # 枠の現れ具合 0..1
var _charge := 0.0       # 登場時の HP の満ち具合 0..1
var _charge_tick := 0.0
var _disp := 1.0         # 表示中の HP の割合(なめらかに追従)
var _ghost := 1.0        # 残像
var _ghost_hold := 0.0
var _hit := 0.0          # 命中の光 0..1
var _last_hits := 0
var _flow := 0.0         # 流れる光の位置
var _phase_done := {}
var _phase_fx: Array = []   # {f, t}
var _sweep := -1.0          # 節目で、ゲージに走る光の位置(0..1。-1 = なし)
var _sparks: Array = []     # {p, v, life, max, col}
var _break_t := -1.0        # 撃破からの秒(-1 = まだ)
var _shards: Array = []     # {p, v, rot, w, life}
var _warned := false
var _rng := RandomNumberGenerator.new()
var _font: Font


func _ready() -> void:
	_font = UiStyle.bold()
	_rng.seed = 7


func tick(delta: float, t_now: float) -> void:
	now = t_now
	if boss == null:
		return
	var appear: float = boss.appear_t
	if not _warned and now >= appear - 1.2 and now < appear + 1.0:
		_warned = true
		warned.emit()
	_drop = move_toward(_drop, 1.0 if now >= appear - 0.3 else 0.0, delta * 2.4)
	if _drop >= 1.0 and _charge < 1.0:
		_charge = move_toward(_charge, 1.0, delta / 1.2)
		_charge_tick += delta
		if _charge_tick >= 0.06 and UiStyle.animate:   # 満ちていく間、音程の上がる小さな音
			_charge_tick = 0.0
			UiSfx.play("count", 0.8 + 0.9 * _charge, 0.7)
		if _charge >= 1.0:
			UiSfx.play("confirm", 0.8)
	var frac: float = boss.hp / maxf(boss.max_hp, 1.0)
	_disp += (frac - _disp) * (1.0 - exp(-delta * 14.0))
	var tip := Vector2(X + W * _shown() + SL * 0.5, Y + H * 0.5)
	if boss.hits_total != _last_hits:
		var n: int = boss.hits_total - _last_hits
		_last_hits = boss.hits_total
		_hit = 1.0
		_ghost_hold = 0.45
		for k in range(mini(n, 3)):
			var life := _rng.randf_range(0.25, 0.5)
			_sparks.append({"p": tip, "v": Vector2.from_angle(_rng.randf_range(-PI * 0.9, PI * 0.1)) * _rng.randf_range(70.0, 190.0),
				"life": life, "max": life, "col": Color(1.0, _rng.randf_range(0.7, 0.95), 0.6)})
	_hit = maxf(_hit - delta * 4.0, 0.0)
	_ghost_hold -= delta
	if _ghost_hold <= 0.0:
		_ghost = move_toward(_ghost, _disp, delta * 0.35)
	_ghost = maxf(_ghost, _disp)
	_flow = fmod(_flow + delta * 220.0, W + 160.0)
	for ph in PHASES:
		if frac <= ph and not _phase_done.has(ph) and _charge >= 1.0:
			_phase_done[ph] = true
			_phase_fx.append({"f": ph, "t": 0.0})
			_sweep = 0.0
			phase_crossed.emit()
	for fx in _phase_fx:
		fx.t += delta
	_phase_fx = _phase_fx.filter(func(fx): return fx.t < 0.9)
	if _sweep >= 0.0:
		_sweep += delta / 0.5
		if _sweep > 1.0:
			_sweep = -1.0
	var i := _sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _sparks[i]
		s.life -= delta
		if s.life <= 0.0:
			_sparks.remove_at(i)
		else:
			s.p += s.v * delta
			s.v = s.v * maxf(1.0 - 2.6 * delta, 0.0) + Vector2(0, 260.0) * delta
		i -= 1
	if boss.defeated and _break_t < 0.0:
		_break_t = 0.0
		_make_shards()
	if _break_t >= 0.0:
		_break_t += delta
		for sh in _shards:
			if _break_t > 0.18:   # 白く光ってから、砕ける
				sh.p += sh.v * delta
				sh.v += Vector2(0, 520.0) * delta
				sh.rot += sh.spin * delta
	queue_redraw()


## いま塗っている割合(登場のチャージ中は、満ちていく途中)。
func _shown() -> float:
	return clampf(_disp, 0.0, 1.0) * (1.0 - pow(1.0 - _charge, 3.0))


func _make_shards() -> void:
	var x := 0.0
	while x < W:
		var w := _rng.randf_range(18.0, 46.0)
		_shards.append({"p": Vector2(X + x + w * 0.5 + SL * 0.5, Y + H * 0.5), "w": minf(w, W - x),
			"v": Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(-260.0, -60.0)), "rot": 0.0, "spin": _rng.randf_range(-5.0, 5.0)})
		x += w


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
	var y := Y - 34.0 * (1.0 - e)
	var f := _shown()
	var col := COL_LOW.lerp(COL_FULL, clampf(_disp, 0.0, 1.0))
	var low := 1.0 - smoothstep(0.2, 0.3, _disp)
	# 見出し: 左に「BOSS」と飾り、右に残りの割合
	draw_colored_polygon(PackedVector2Array([Vector2(X + SL + 2, y - 15), Vector2(X + SL + 8, y - 21), Vector2(X + SL + 14, y - 15), Vector2(X + SL + 8, y - 9)]), Color(col.r, col.g, col.b, a))
	draw_string(_font, Vector2(X + SL + 20, y - 9), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.92 * a))
	var pct := "%.1f%%" % (_disp * 100.0 * (1.0 - pow(1.0 - _charge, 3.0)))
	draw_string(_font, Vector2(X + SL + W - 200.0, y - 8), pct, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 17, Color(col.r, col.g, col.b, a).lerp(Color.WHITE, 0.35))
	# 下の光(残りが少ないと、ゆっくり脈打つ)
	var glow_a := (0.16 + 0.22 * low * (0.5 + 0.5 * sin(now * 3.2))) * a
	draw_polygon(PackedVector2Array([Vector2(X, y + H), Vector2(X + W * f, y + H), Vector2(X + W * f, y + H + 14), Vector2(X, y + H + 14)]),
		PackedColorArray([Color(col.r, col.g, col.b, glow_a), Color(col.r, col.g, col.b, glow_a), Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)]))
	# ケースと溝(5% ごとの細い目盛り)
	draw_colored_polygon(_slant(X - 4, y - 4, W + 8, H + 8), Color(0.03, 0.01, 0.03, 0.8 * a))
	draw_colored_polygon(_slant(X, y, W, H), Color(0, 0, 0, 0.55 * a))
	for k in range(1, 20):
		var tx := X + W * k / 20.0
		draw_line(Vector2(tx + SL, y + 1), Vector2(tx, y + H - 1), Color(1, 1, 1, 0.07 * a), 1.0)
	# 残像(減った分の白)
	if _ghost > f + 0.0005 and _charge >= 1.0:   # 登場のチャージ中は出さない
		draw_polygon(_band(X + W * f, y, W * (_ghost - f), 0.0, 1.0), PackedColorArray([Color(1, 1, 1, 0.55 * a), Color(1, 1, 1, 0.3 * a), Color(1, 1, 1, 0.3 * a), Color(1, 1, 1, 0.55 * a)]))
	if f > 0.001:
		var fw := W * f
		var hit := _hit
		var c_l := Color(col.r * 0.38, col.g * 0.3, col.b * 0.36, a)
		var c_r := col.lerp(Color.WHITE, 0.12 + 0.3 * hit)
		c_r.a = a
		draw_polygon(_band(X, y, fw, 0.0, 0.5), PackedColorArray([c_l.lerp(Color.WHITE, 0.12), c_r.lerp(Color.WHITE, 0.3), c_r, c_l]))
		draw_polygon(_band(X, y, fw, 0.5, 1.0), PackedColorArray([c_l, c_r, Color(c_r.r * 0.65, c_r.g * 0.6, c_r.b * 0.6, a), Color(c_l.r * 0.7, c_l.g * 0.7, c_l.b * 0.7, a)]))
		# 光沢と、流れる光の帯
		draw_polygon(_band(X, y, fw, 0.0, 0.38), PackedColorArray([Color(1, 1, 1, 0.3 * a), Color(1, 1, 1, 0.3 * a), Color(1, 1, 1, 0.03 * a), Color(1, 1, 1, 0.03 * a)]))
		var cx := _flow - 80.0
		for side in range(2):
			var x0 := clampf(cx + (-40.0 if side == 0 else 0.0), 0.0, fw)
			var x1 := clampf(cx + (0.0 if side == 0 else 40.0), 0.0, fw)
			if x1 - x0 > 0.5:
				var lo := Color(1, 1, 1, 0.0)
				var hi := Color(1, 1, 1, 0.22 * a)
				draw_polygon(_band(X + x0, y, x1 - x0, 0.0, 1.0), PackedColorArray([lo if side == 0 else hi, hi if side == 0 else lo, hi if side == 0 else lo, lo if side == 0 else hi]))
		# 節目で走る光
		if _sweep >= 0.0:
			var sx := clampf(W * _sweep, 0.0, fw)
			var sa := sin(PI * _sweep) * 0.6 * a
			draw_polygon(_band(X + maxf(sx - 60.0, 0.0), y, minf(60.0, sx), 0.0, 1.0), PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, sa), Color(1, 1, 1, sa), Color(1, 1, 1, 0.0)]))
		# 先端: 光と線(命中で大きく明るく)
		var tip := Vector2(X + fw + SL * 0.5, y + H * 0.5)
		draw_circle(tip, 10.0 + 8.0 * hit, Color(col.r, col.g, col.b, (0.18 + 0.3 * hit) * a))
		draw_circle(tip, 4.0 + 3.0 * hit, Color(1, 1, 1, (0.35 + 0.5 * hit) * a))
		draw_line(Vector2(X + fw + SL + 1, y - 3), Vector2(X + fw + 1, y + H + 3), Color(1, 1, 1, 0.95 * a), 2.0, true)
	# 縁
	var o := _slant(X, y, W, H)
	o.append(o[0])
	draw_polyline(o, Color(col.r, col.g, col.b, 0.75 * a).lerp(Color.WHITE, 0.3), 1.2, true)
	var o2 := _slant(X - 4, y - 4, W + 8, H + 8)
	o2.append(o2[0])
	draw_polyline(o2, Color(col.r, col.g, col.b, 0.3 * a), 1.0, true)
	# 節目の目印(ひし形。越えたら暗くなり、越えた瞬間に弾けて輪が広がる)
	for ph in PHASES:
		var px: float = X + W * ph + SL * 0.5
		var done := _phase_done.has(ph)
		var mc := Color(1, 1, 1, (0.3 if done else 0.85) * a)
		var py := y + H + 7.0
		draw_colored_polygon(PackedVector2Array([Vector2(px, py - 4), Vector2(px + 4, py), Vector2(px, py + 4), Vector2(px - 4, py)]), mc)
	for fx in _phase_fx:
		var k: float = fx.t / 0.9
		var px: float = X + W * float(fx.f) + SL * 0.5
		var ee := 1.0 - pow(1.0 - k, 3.0)
		draw_arc(Vector2(px, y + H * 0.5), 8.0 + 46.0 * ee, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - k) * a), 2.0, true)
		draw_line(Vector2(px, y - 10.0 - 12.0 * ee), Vector2(px, y + H + 10.0 + 12.0 * ee), Color(col.r, col.g, col.b, (1.0 - k) * a).lerp(Color.WHITE, 0.5), 2.0, true)
	for s in _sparks:
		var k: float = s.life / s.max
		var sc: Color = s.col
		draw_line(s.p, s.p - s.v * 0.035, Color(sc.r, sc.g, sc.b, k * 0.7), 1.4, true)
		draw_circle(s.p, 1.2 + 1.0 * k, Color(sc.r, sc.g, sc.b, k))


## WARNING の帯(フィールド中央)。
func _draw_banner() -> void:
	var tb: float = now - (float(boss.appear_t) - 1.2)
	if tb < 0.0 or tb > 2.6:
		return
	var env := smoothstep(0.0, 0.35, tb) * (1.0 - smoothstep(2.1, 2.6, tb))
	if env < 0.004:
		return
	var hgt := 128.0
	var open := 1.0 - pow(1.0 - clampf(tb / 0.4, 0.0, 1.0), 3.0)   # 帯は、中央から上下に開く
	var hh := hgt * 0.5 * open
	draw_rect(Rect2(ARENA_X0, BANNER_Y - hh, ARENA_W, hh * 2.0), Color(0.18, 0.0, 0.03, 0.62 * env))
	# 上下の警告の縞(赤と黒の斜線。上は右へ、下は左へ流れる)
	for row in range(2):
		var sy := BANNER_Y - hh if row == 0 else BANNER_Y + hh - 12.0
		var dir := 1.0 if row == 0 else -1.0
		draw_rect(Rect2(ARENA_X0, sy, ARENA_W, 12.0), Color(0.08, 0.0, 0.0, 0.8 * env))
		var off := fposmod(tb * 70.0 * dir, 28.0)
		var x := ARENA_X0 - 28.0 + off
		while x < ARENA_X0 + ARENA_W:
			var xa := maxf(x, ARENA_X0)
			var xb := minf(x + 14.0, ARENA_X0 + ARENA_W)
			if xb - xa > 1.0:
				draw_colored_polygon(PackedVector2Array([Vector2(xa + 6, sy), Vector2(minf(xb + 6, ARENA_X0 + ARENA_W), sy), Vector2(xb, sy + 12), Vector2(xa, sy + 12)]), Color(1.0, 0.22, 0.26, 0.85 * env))
			x += 28.0
	# 文字(少し大きいところから収まる。にじみの影を重ねる)
	var s := lerpf(1.18, 1.0, 1.0 - pow(1.0 - clampf(tb / 0.5, 0.0, 1.0), 3.0))
	var fs := int(round(60.0 * s))
	var tc := Color(1.0, 0.32, 0.36, env)
	for k in range(3):
		var g := 2.0 + 2.0 * k
		draw_string(_font, Vector2(ARENA_X0, BANNER_Y + 18.0 + g * 0.3), "WARNING", HORIZONTAL_ALIGNMENT_CENTER, ARENA_W, fs, Color(1.0, 0.1, 0.15, 0.12 * env))
	draw_string(_font, Vector2(ARENA_X0, BANNER_Y + 18.0), "WARNING", HORIZONTAL_ALIGNMENT_CENTER, ARENA_W, fs, tc)
	draw_string(_font, Vector2(ARENA_X0, BANNER_Y + 44.0), "A  BOSS  IS  APPROACHING", HORIZONTAL_ALIGNMENT_CENTER, ARENA_W, 13, Color(1, 0.85, 0.85, 0.75 * env))


## 撃破: 白く光ってから、ゲージが破片になって散る。
func _draw_break() -> void:
	var t := _break_t
	if t < 0.18:   # 白い閃光(ゲージの形のまま)
		var k := t / 0.18
		draw_colored_polygon(_slant(X - 4, Y - 4, W + 8, H + 8), Color(1, 1, 1, 0.9 * (1.0 - 0.3 * k)))
		draw_string(_font, Vector2(X + SL + 20, Y - 9), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.92))
		return
	var a := clampf(1.0 - (t - 0.18) / 1.1, 0.0, 1.0)
	if a <= 0.0:
		return
	for sh in _shards:
		var w: float = sh.w
		var pts := PackedVector2Array()
		for v in [Vector2(-w * 0.5 + SL * 0.5, -H * 0.5), Vector2(w * 0.5 + SL * 0.5, -H * 0.5), Vector2(w * 0.5 - SL * 0.5, H * 0.5), Vector2(-w * 0.5 - SL * 0.5, H * 0.5)]:
			pts.append(sh.p + (v as Vector2).rotated(sh.rot))
		draw_colored_polygon(pts, Color(1.0, 0.55, 0.45, 0.75 * a))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.9 * a), 1.0, true)
	draw_string(_font, Vector2(X, Y + 4), "DEFEATED", HORIZONTAL_ALIGNMENT_CENTER, W + SL, 26, Color(1.0, 0.88, 0.4, a))


## 斜めに切った四角(左上 → 右上 → 右下 → 左下。上辺が右に SL だけ張り出す)。
func _slant(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x + SL, y), Vector2(x + SL + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


## 斜めの四角の、高さ f0〜f1 の帯(高さは H)。
func _band(x: float, y: float, w: float, f0: float, f1: float) -> PackedVector2Array:
	var y0 := y + H * f0
	var y1 := y + H * f1
	var o0 := SL * (1.0 - f0)
	var o1 := SL * (1.0 - f1)
	return PackedVector2Array([Vector2(x + o0, y0), Vector2(x + o0 + w, y0), Vector2(x + o1 + w, y1), Vector2(x + o1, y1)])
