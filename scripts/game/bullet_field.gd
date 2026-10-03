extends Node2D
## 弾の SoA 配列 + 手動更新/衝突判定 + MultiMesh 描画。
## 物理エンジンやノード per 弾は使わない(数千発を毎フレーム回すため)。

const MAX_BULLETS := 4000   # 弾幕 v2 の AR 連動の弾速(遅い弾は長く残る)で、画面内の弾数が増えるため 2500 から引き上げ
const HIT_SCALE := 0.7     # 見た目半径に対する当たり判定の倍率
const GRAZE_MARGIN := 20.0 # 見た目の縁からのかすり距離

## 弾の挙動(弾幕 v2。kind = 0 の弾は、今までどおり直進(+ turn)だけ)。パラメータ a / b / c は kind ごとに意味が違う:
##   BEH_ACCEL  : a = 加速度(px/s²。負なら減速) / b = 目標の速さ(px/s。ここで止まる)
##   BEH_STOPGO : a = 止まり始める時刻(発射からの秒) / b = 止まっている秒 / c = 再発進のときに速度を回す角(rad)。止まる前後は、短く減速・加速する
##   BEH_SPLIT  : a = 分裂する時刻(秒) / b = 子弾の数 / c = 子弾の速さの倍率(親の速さに対する)。子弾は全周に等分で出て、親は消える
##   BEH_BOUNCE : a = 残りの反射回数(盤面の縁で跳ね返る。0 になったら、そのまま出ていく)
## どれも、自機の位置には依存しない(協力で全員が同じ弾を見るため)。
const BEH_NONE := 0
const BEH_ACCEL := 1
const BEH_STOPGO := 2
const BEH_SPLIT := 3
const BEH_BOUNCE := 4
const BRAKE_T := 0.2      # STOPGO: 止まる前に減速する秒
const RESTART_T := 0.3    # STOPGO: 再発進で加速する秒
const SPLIT_SIZE := 0.5   # 子弾の大きさ(親に対する倍率。親は大きい弾なので、子は普通の大きさになる)
const BOUNCE_RECT := Rect2(0.0, 0.0, 960.0, 720.0)

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
var kind := PackedByteArray()      # 挙動の種類(BEH_*。0 = なし)
var age := PackedFloat32Array()    # 発射からの秒(挙動のある弾だけ進める)
var pa := PackedFloat32Array()     # 挙動のパラメータ a / b / c
var pb := PackedFloat32Array()
var pc := PackedFloat32Array()

# update() の結果
var hit := false
## このステップで、自機の移動経路が弾の当たり判定の中を通った長さ(px)。当たった弾のうち最大のもの。被弾していなければ 0。
## ダメージを「触れていた時間」だけでなく「通った距離」でも測るのに使う(速く動いて抜けても、ダメージが減りすぎないように)。
var hit_dist := 0.0
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
	kind.resize(MAX_BULLETS)
	age.resize(MAX_BULLETS)
	pa.resize(MAX_BULLETS)
	pb.resize(MAX_BULLETS)
	pc.resize(MAX_BULLETS)


## 描画用ノードを作る(テストなど描画不要なときは呼ばない)。
func setup_render() -> void:
	_mm_halo = _make_layer(_make_halo_texture(), CanvasItemMaterial.BLEND_MODE_ADD)
	var body_mat := _make_disc_material(1.0, 0.0)
	var core_mat := _make_disc_material(0.0, 1.0)
	_mm_color = _make_layer(null, CanvasItemMaterial.BLEND_MODE_MIX, body_mat)
	_mm_core = _make_layer(null, CanvasItemMaterial.BLEND_MODE_MIX, core_mat)
	_mm_ring = _make_layer(_make_ring_texture(), CanvasItemMaterial.BLEND_MODE_MIX)
	_buf_halo.resize(MAX_BULLETS * 12)
	_buf_color.resize(MAX_BULLETS * 12)
	_buf_core.resize(MAX_BULLETS * 12)
	_buf_ring.resize(MAX_BULLETS * 12)


func _make_layer(tex: Texture2D, blend: int, mat_override: Material = null) -> MultiMesh:
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
	inst.material = mat_override if mat_override != null else mat
	add_child(inst)
	return mm


## 弾の円盤(本体と芯)のシェーダー。縁のぼかしを、弾の半径に対する割合ではなく、ほぼ一定のピクセル幅にする
## (以前のテクスチャは縁が半径の 22% で、大きい弾(弾サイズの「大」)は縁が太く、ぼやけて見えた。普通の大きさの弾の縁は、ほぼ同じ)。
const DISC_SHADER := """
shader_type canvas_item;
uniform float rim = 0.0;   // 1 = 大きい弾の本体に、輪郭(本体を暗く・縁を明るく)をつける(本体の層だけ。芯の層は 0)
uniform float core = 0.0;   // 1 = 白い芯の層: 縁が、当たり判定の縁(半径 = 判定半径)。層の大きさは、判定の直径 + 2px
varying float sz;
void vertex() {
	sz = length(MODEL_MATRIX[0].xy);   // 弾の直径(px)。QuadMesh の大きさが 1 なので、インスタンスの拡大率がそのまま直径
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	if (core > 0.5) {
		float rh = max(sz * 0.5 - 1.0, 0.5);   // 判定の半径(px)。縁は、そこを中心にした約 1.4px のぼかし(ほぼくっきり)
		COLOR.a *= 1.0 - smoothstep(rh - 0.7, rh + 0.7, d * sz * 0.5);
	} else {
		float w = clamp(2.0 / max(sz * 0.5, 1.0), 0.04, 0.22);   // 縁のぼかしの幅(半径に対する割合)。2px ぶん。小さい弾は従来どおり 22%
		COLOR.a *= 1.0 - smoothstep(1.0 - w, 1.0, d);
		float big = smoothstep(26.0, 38.0, sz) * rim;   // 直径 26px 以下(普通・小)は 0、38px 以上(大)で 1
		float edge = smoothstep(0.74, 0.9, d);
		vec3 body = COLOR.rgb * 0.78;
		vec3 lit = mix(COLOR.rgb, vec3(1.0), 0.6);
		COLOR.rgb = mix(COLOR.rgb, mix(body, lit, edge), big);
	}
}
"""

static func _make_disc_material(rim: float, core: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = DISC_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("rim", rim)
	mat.set_shader_parameter("core", core)
	return mat



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


## beh_kind != 0 のときは、挙動(BEH_*)と、そのパラメータ a / b / c、発射からの経過 age0(発射が遅れたぶん)を持つ。
func add(p: Vector2, v: Vector2, radius: float, color_idx: int, grace_px := 0.0, turn_rate := 0.0,
		beh_kind := 0, beh_a := 0.0, beh_b := 0.0, beh_c := 0.0, age0 := 0.0) -> void:
	if count >= MAX_BULLETS:
		return
	pos[count] = p
	vel[count] = v
	rad[count] = radius
	col[count] = color_idx
	grace[count] = grace_px
	turn[count] = turn_rate
	grazed[count] = 0
	kind[count] = beh_kind
	if beh_kind != 0:
		age[count] = age0
		pa[count] = beh_a
		pb[count] = beh_b
		pc[count] = beh_c
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
		kind[i] = kind[count]
		age[i] = age[count]
		pa[i] = pa[count]
		pb[i] = pb[count]
		pc[i] = pc[count]


## 挙動のある弾 i の、このステップの進み方。vel[i] を更新して、この弾が動く速度(止まっている間は 0 倍)を返す。
## 分裂したとき(弾 i は消え、子弾が足される)は、Vector2.INF を返す。呼ぶ側は i の弾を消えたものとして扱う。
func _behave(i: int, dt: float) -> Vector2:
	var t0 := age[i]
	var t1 := t0 + dt
	age[i] = t1
	var v := vel[i]
	match kind[i]:
		BEH_ACCEL:
			var sp := v.length()
			if sp > 0.000001:
				var tgt := pb[i]
				var a := pa[i]
				var nsp := minf(sp + a * dt, tgt) if a > 0.0 else maxf(sp + a * dt, tgt)
				v = v * (nsp / sp)
				vel[i] = v
		BEH_STOPGO:
			var stop_t := pa[i]
			var go_t := stop_t + pb[i]
			if t0 < go_t and t1 >= go_t:
				v = v.rotated(pc[i])   # 再発進の向き
				vel[i] = v
			var f := 1.0
			if t1 >= stop_t - BRAKE_T and t1 < go_t:
				f = 1.0 - smoothstep(stop_t - BRAKE_T, stop_t, t1)
			elif t1 >= go_t and t1 < go_t + RESTART_T:
				f = smoothstep(go_t, go_t + RESTART_T, t1)
			return v * f
		BEH_SPLIT:
			if t1 >= pa[i]:
				var n := int(pb[i])
				var sp := v.length() * pc[i]
				var a0 := v.angle()
				var p := pos[i]
				var r := rad[i] * SPLIT_SIZE
				var c := col[i]
				for j in range(n):
					add(p, Vector2.from_angle(a0 + TAU * float(j) / float(n)) * sp, r, c)
				return Vector2.INF
		BEH_BOUNCE:
			pass   # 反射は、動かしたあとの位置で見る(update)
	return v


## 反射する弾 i(位置 p は動かしたあと)を、盤面の縁で跳ね返す。跳ね返したら true。
func _bounce(i: int, p: Vector2, v: Vector2) -> bool:
	if pa[i] < 0.5:
		return false
	var r := BOUNCE_RECT
	var hit_x := (p.x < r.position.x and v.x < 0.0) or (p.x > r.end.x and v.x > 0.0)
	var hit_y := (p.y < r.position.y and v.y < 0.0) or (p.y > r.end.y and v.y > 0.0)
	if not hit_x and not hit_y:
		return false
	if hit_x:
		v.x = -v.x
		p.x = clampf(p.x, r.position.x, r.end.x)
	if hit_y:
		v.y = -v.y
		p.y = clampf(p.y, r.position.y, r.end.y)
	vel[i] = v
	pos[i] = p
	pa[i] -= 1.0
	return true


## 弾を進め、被弾/かすりを判定する。check_hit=false(無敵中)でも弾は動く。
func update(dt: float, ppos: Vector2, player_r: float, check_hit: bool, pprev := Vector2.INF) -> void:
	hit = false
	hit_dist = 0.0
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
		var kd := kind[i]
		if kd != 0:   # 挙動のある弾(弾幕 v2)。v は、このステップで実際に動く速度になる
			v = _behave(i, dt)
			if v == Vector2.INF:   # 分裂した(親は消える。子弾は末尾に足されていて、このステップでは動かさない)
				_remove(i)
				i -= 1
				continue
		var p := pos[i] + v * dt
		if kd == BEH_BOUNCE and _bounce(i, p, v):
			p = pos[i]
			v = vel[i]
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
				hit_dist = maxf(hit_dist, _path_inside(p, hr, pprev, seg, seg2, swept))
			elif grazed[i] == 0:
				var gr := player_r + r + GRAZE_MARGIN
				if d2 < gr * gr:
					grazed[i] = 1
					graze_count += 1
		i -= 1


## 自機の経路(pprev から seg だけ動いた線分)のうち、中心 p・半径 hr の円の中を通った長さ。ほとんど動いていないとき(swept でない)は、動いた長さ。
static func _path_inside(p: Vector2, hr: float, pprev: Vector2, seg: Vector2, seg2: float, swept: bool) -> float:
	var seg_len := sqrt(seg2)
	if not swept:
		return seg_len
	var u := (p - pprev).dot(seg) / seg2   # 線分の上の、いちばん近い点の位置(0..1 の外もありうる)
	var dl2 := p.distance_squared_to(pprev + seg * u)
	var half := sqrt(maxf(hr * hr - dl2, 0.0)) / seg_len   # 円の中を通る範囲の半分(線分の長さを 1 とした割合)
	return maxf(minf(1.0, u + half) - maxf(0.0, u - half), 0.0) * seg_len


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
			_put(_buf_core, o, p.x, p.y, r * HIT_SCALE * 2.0 + 2.0, Color(1, 1, 1, c.a))   # 白い芯の縁 = 当たり判定の縁(自機の白い円と同じ規則。縁のぼかし分の 2px を足す)
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
