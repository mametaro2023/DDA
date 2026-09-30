extends Node2D
## 弾の SoA 配列 + 手動更新/衝突判定 + MultiMesh 描画。
## 物理エンジンやノード per 弾は使わない(数千発を毎フレーム回すため)。

const MAX_BULLETS := 2500
const HIT_SCALE := 0.7     # 見た目半径に対する当たり判定の倍率
const GRAZE_MARGIN := 20.0 # 見た目の縁からのかすり距離

const PALETTE: Array[Color] = [
	Color(0.35, 0.85, 1.0), Color(1.0, 0.45, 0.75), Color(0.6, 1.0, 0.45),
	Color(0.7, 0.55, 1.0), Color(1.0, 0.9, 0.4),
	# kiai
	Color(1.0, 0.35, 0.3), Color(1.0, 0.6, 0.25), Color(1.0, 0.3, 0.6),
	Color(1.0, 0.85, 0.3), Color(1.0, 0.7, 0.85),
]

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var rad := PackedFloat32Array()
var col := PackedInt32Array()
var grace := PackedFloat32Array()  # 残り無害距離(px)
var turn := PackedFloat32Array()   # 角速度(rad/s)
var grazed := PackedByteArray()

# update() の結果
var hit := false
var graze_count := 0

var bounds := Rect2(-12, -12, 984, 744)

## 見える範囲(暗闇 MOD。描画だけで、判定には関係しない)。vis_r1 > 0 のとき、vis_center から vis_r0 までは全部見え、
## vis_r1 に向けてなめらかに薄れ、それより遠い弾は見えない。
var vis_center := Vector2.ZERO
var vis_r0 := 0.0
var vis_r1 := 0.0
## キアイ中の拍に合わせた光の強さ 0..1。0 より大きいとき、弾の周りに淡い光(加算合成のハロー)を足す。描画だけで、判定には関係しない
var halo := 0.0

var _mm_halo: MultiMesh    # 弾の周りの淡い光(加算合成。いちばん下の層)
var _mm_color: MultiMesh
var _mm_core: MultiMesh
var _mm_ring: MultiMesh   # 当たり判定がまだ無い弾(発射直後)は中抜きのリングで描く
var _buf_halo := PackedFloat32Array()
var _buf_color := PackedFloat32Array()
var _buf_core := PackedFloat32Array()
var _buf_ring := PackedFloat32Array()


func _init() -> void:
	pos.resize(MAX_BULLETS)
	vel.resize(MAX_BULLETS)
	rad.resize(MAX_BULLETS)
	col.resize(MAX_BULLETS)
	grace.resize(MAX_BULLETS)
	turn.resize(MAX_BULLETS)
	grazed.resize(MAX_BULLETS)


## 描画用ノードを作る(テストなど描画不要なときは呼ばない)。
func setup_render() -> void:
	var tex := _make_disc_texture()
	_mm_halo = _make_layer(_make_halo_texture(), CanvasItemMaterial.BLEND_MODE_ADD)
	_mm_color = _make_layer(tex, CanvasItemMaterial.BLEND_MODE_MIX)
	_mm_core = _make_layer(tex, CanvasItemMaterial.BLEND_MODE_MIX)
	_mm_ring = _make_layer(_make_ring_texture(), CanvasItemMaterial.BLEND_MODE_MIX)
	_buf_halo.resize(MAX_BULLETS * 12)
	_buf_color.resize(MAX_BULLETS * 12)
	_buf_core.resize(MAX_BULLETS * 12)
	_buf_ring.resize(MAX_BULLETS * 12)


func _make_layer(tex: Texture2D, blend: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAX_BULLETS
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = blend
	inst.material = mat
	add_child(inst)
	return mm


static func _make_disc_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			var a := 1.0 - smoothstep(0.78, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## 中心が明るく、外へなめらかに消える光の玉(ハロー用)。
static func _make_halo_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := clampf(Vector2(x - c, y - c).length() / (size * 0.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 2.2)))
	return ImageTexture.create_from_image(img)


static func _make_ring_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			# 外縁 0.95、内縁 0.62 の輪(なめらかな縁)
			var a := smoothstep(0.55, 0.66, d) * (1.0 - smoothstep(0.86, 0.98, d))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func clear() -> void:
	count = 0


func add(p: Vector2, v: Vector2, radius: float, color_idx: int, grace_px := 0.0, turn_rate := 0.0) -> void:
	if count >= MAX_BULLETS:
		return
	pos[count] = p
	vel[count] = v
	rad[count] = radius
	col[count] = color_idx
	grace[count] = grace_px
	turn[count] = turn_rate
	grazed[count] = 0
	count += 1


func _remove(i: int) -> void:
	count -= 1
	if i != count:
		pos[i] = pos[count]
		vel[i] = vel[count]
		rad[i] = rad[count]
		col[i] = col[count]
		grace[i] = grace[count]
		turn[i] = turn[count]
		grazed[i] = grazed[count]


## 弾を進め、被弾/かすりを判定する。check_hit=false(無敵中)でも弾は動く。
func update(dt: float, ppos: Vector2, player_r: float, check_hit: bool, pprev := Vector2.INF) -> void:
	hit = false
	graze_count = 0
	var b := bounds
	# 自機の移動経路(pprev→ppos)上で判定する: 素早い移動で弾をすり抜けないように
	var seg := Vector2.ZERO if pprev == Vector2.INF else ppos - pprev
	var seg2 := seg.length_squared()
	var swept := seg2 > 4.0
	var i := count - 1
	while i >= 0:
		var v := vel[i]
		var tr := turn[i]
		if tr != 0.0:
			v = v.rotated(tr * dt)
			vel[i] = v
		var p := pos[i] + v * dt
		if not b.has_point(p):
			_remove(i)
			i -= 1
			continue
		pos[i] = p
		var g := grace[i]
		if g > 0.0:
			grace[i] = g - v.length() * dt
		else:
			var r := rad[i]
			var d2: float
			if swept:
				var u := clampf((p - pprev).dot(seg) / seg2, 0.0, 1.0)
				d2 = p.distance_squared_to(pprev + seg * u)
			else:
				d2 = p.distance_squared_to(ppos)
			var hr := player_r + r * HIT_SCALE
			if check_hit and d2 < hr * hr:
				hit = true
			elif grazed[i] == 0:
				var gr := player_r + r + GRAZE_MARGIN
				if d2 < gr * gr:
					grazed[i] = 1
					graze_count += 1
		i -= 1


## 中心から半径 r 内の弾を消す(被弾後の連鎖被弾防止)。
func clear_radius(center: Vector2, r: float) -> void:
	var r2 := r * r
	var i := count - 1
	while i >= 0:
		if pos[i].distance_squared_to(center) < r2:
			_remove(i)
		i -= 1


## 自機の周りが落ち着いているか(休憩中の一掃・クリアの条件)。次のどれかの弾が 1 つでもあれば false:
##   ・自機の近く(near_r 以内)にある弾
##   ・自機に接近している弾 … 今の向きのまま look_t 秒以内に、自機から approach_r 以内(自機・弾の当たり半径を含む)を通る弾
## 遠くにあって、自機に向かっていない弾は無視する(アリーナ内に残っていてもよい)。旋回する弾は 0.2 秒刻みで先を調べる。
func is_calm(center: Vector2, player_r: float, near_r: float, approach_r: float, look_t: float) -> bool:
	for i in range(count):
		var p := pos[i]
		var r := rad[i] * HIT_SCALE
		var rel := center - p
		var nr := near_r + r
		if rel.length_squared() < nr * nr:
			return false
		var v := vel[i]
		var lim := approach_r + player_r + r
		var tr := turn[i]
		if tr == 0.0:
			var sp2 := v.length_squared()
			if sp2 < 1.0:
				continue
			var t := clampf(rel.dot(v) / sp2, 0.0, look_t)   # いちばん近づく時刻(今から look_t 秒まで)
			if t > 0.0 and (p + v * t).distance_squared_to(center) < lim * lim:
				return false
		else:
			var q := p
			var w := v
			for s in range(int(look_t / 0.2)):
				w = w.rotated(tr * 0.2)
				q += w * 0.2
				if q.distance_squared_to(center) < lim * lim:
					return false
	return true


## 最も近い弾までの距離(見た目の縁基準)。ボット用。
func nearest_gap(p: Vector2) -> float:
	var best := 1e9
	for i in range(count):
		var d := pos[i].distance_to(p) - rad[i]
		if d < best:
			best = d
	return best


## 1 発分のインスタンスデータ(2D 変換 + 色)を書き込む。scale=0 なら見えない。
static func _put(buf: PackedFloat32Array, o: int, x: float, y: float, s: float, c: Color) -> void:
	buf[o] = s
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = x
	buf[o + 4] = 0.0
	buf[o + 5] = s
	buf[o + 6] = 0.0
	buf[o + 7] = y
	buf[o + 8] = c.r
	buf[o + 9] = c.g
	buf[o + 10] = c.b
	buf[o + 11] = c.a


func sync_render() -> void:
	if _mm_color == null:
		return
	var n := count
	for i in range(n):
		var p := pos[i]
		var r := rad[i]
		var c := PALETTE[col[i] % PALETTE.size()]
		if vis_r1 > 0.0:
			var va := 1.0 - smoothstep(vis_r0, vis_r1, p.distance_to(vis_center))
			if va < 0.005:
				_put(_buf_color, i * 12, p.x, p.y, 0.0, c)
				_put(_buf_halo, i * 12, p.x, p.y, 0.0, c)
				_put(_buf_core, i * 12, p.x, p.y, 0.0, c)
				_put(_buf_ring, i * 12, p.x, p.y, 0.0, c)
				continue
			c.a = va
		var o := i * 12
		if grace[i] > 0.0:
			# 発射直後で当たり判定がまだ無い弾: 塗りつぶしを消し、中抜きのリングだけを不透明で描く
			_put(_buf_color, o, p.x, p.y, 0.0, c)
			_put(_buf_core, o, p.x, p.y, 0.0, Color(1, 1, 1, c.a))
			_put(_buf_ring, o, p.x, p.y, r * 2.3, c)
		else:
			_put(_buf_color, o, p.x, p.y, r * 2.3, c)
			_put(_buf_core, o, p.x, p.y, r * 1.2, Color(1, 1, 1, c.a))
			_put(_buf_ring, o, p.x, p.y, 0.0, c)
	if halo > 0.01:
		for i in range(n):
			var hc := PALETTE[col[i] % PALETTE.size()]
			var hp := pos[i]
			var ha := halo * 0.4
			if vis_r1 > 0.0:
				ha *= 1.0 - smoothstep(vis_r0, vis_r1, hp.distance_to(vis_center))
			_put(_buf_halo, i * 12, hp.x, hp.y, rad[i] * 7.0 if ha > 0.004 else 0.0, Color(hc.r, hc.g, hc.b, ha))
		_mm_halo.buffer = _buf_halo
	_mm_halo.visible_instance_count = n if halo > 0.01 else 0
	_mm_color.buffer = _buf_color
	_mm_core.buffer = _buf_core
	_mm_ring.buffer = _buf_ring
	_mm_color.visible_instance_count = n
	_mm_core.visible_instance_count = n
	_mm_ring.visible_instance_count = n
