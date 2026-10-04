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
var colf := PackedFloat32Array()   # col と同じ(描画用。GPU へ数の並びのまま送るため、小数で持つ)
var grace := PackedFloat32Array()  # 残り無害距離(px)
var turn := PackedFloat32Array()   # 角速度(rad/s)
var grazed := PackedByteArray()
var kind := PackedByteArray()      # 挙動の種類(BEH_*。0 = なし)
var age := PackedFloat32Array()    # 発射からの秒(挙動のある弾だけ進める)
var pa := PackedFloat32Array()     # 挙動のパラメータ a / b / c
var pb := PackedFloat32Array()
var pc := PackedFloat32Array()
var tscale := PackedFloat32Array() # この弾の時間の倍率(時の淀み・急流の中で変わる。1 = ふつう)
var wtgt := PackedFloat32Array()   # この弾の、時間の倍率の目標(WARP_EVAL ごとに調べる)
var _warp_acc := 0.0
var _ts_active := false            # 倍率が 1 でない弾がある(エリアが消えたあとも、戻る間は true)

# update() の結果
var hit := false
## このステップで、自機の移動経路が弾の当たり判定の中を通った長さ(px)。当たった弾のうち最大のもの。被弾していなければ 0。
## ダメージを「触れていた時間」だけでなく「通った距離」でも測るのに使う(速く動いて抜けても、ダメージが減りすぎないように)。
var hit_dist := 0.0
var graze_count := 0

var bounds := Rect2(-12, -12, 984, 744)

## 時の淀み・時の急流(特殊エリア。弾幕 v2): 弾の位置がこの中にあるとき、その弾の時間が f 倍で進む(動き・曲がり・挙動の時計も)。自機の位置には依存しない。
## 各要素: {f: 倍率, rect: Rect2}(長方形)または {f, c: Vector2, r2: 半径の 2 乗}(円)。空なら何もしない。GameSim が毎ステップ決める。
## 弾ごとの倍率 tscale は、そのときの目標(中なら f・外なら 1)へなめらかに近づく: 入るときは WARP_ENTER(/秒)、出るときは WARP_EXIT(/秒)で、
## エリアが消えても、弾が急に元の速さへ戻らない(急に速くなる弾は避けにくいため。ゆっくり戻すので、見てから避けられる)。
var warp: Array = []
var _wz := PackedFloat32Array()   # warp を数の並びにしたもの(_flatten_warp)
var _wb_x0 := 0.0                 # 全部の淀みをまとめた外枠
var _wb_y0 := 0.0
var _wb_x1 := 0.0
var _wb_y1 := 0.0
const WARP_ENTER := 1.2
const WARP_EXIT := 0.4
const WARP_EVAL := 0.016   # 弾ごとの目標の倍率(どの淀みの中か)を調べる間隔(秒)。毎ステップ調べると重い(弾が多いとフレームが落ちる)。間の刻みは、前に調べた目標を使う(16ms で 4px 程度しか進まず、倍率もなめらかに変わるので、見た目は変わらない)
const WARP_SLOW_TINT := Color(0.6, 0.55, 1.0)    # 遅くなっている弾の光の色(時の淀み)
const WARP_FAST_TINT := Color(1.0, 0.4, 0.35)    # 速くなっている弾の光の色(時の急流)
## 時の淀み・急流の中の弾の光(描画だけ)。重ねて塗る光(加算ではない)なので、弾が密集しても白く飛ばず、エリアの色の淡いもやになる
const WARP_GLOW_A := 0.45    # 光の濃さ(倍率が目標に着いたとき)
const WARP_GLOW_SIZE := 7.0  # 光の直径(弾の半径に対する倍率)
const WARP_BODY_TINT := 0.45 # 本体の色を、淀み(紫)・急流(赤)へ寄せる割合

## 見える範囲(暗闇 MOD。描画だけで、判定には関係しない)。vis_r1 > 0 のとき、vis_center から vis_r0 までは全部見え、
## vis_r1 に向けてなめらかに薄れ、それより遠い弾は見えない。
var vis_center := Vector2.ZERO
var vis_r0 := 0.0
var vis_r1 := 0.0
## キアイ中の拍に合わせた光の強さ 0..1。0 より大きいとき、弾の周りに淡い光(加算合成のハロー)を足す。描画だけで、判定には関係しない
var halo := 0.0
## 目に優しい表示(設定「目に優しい表示」)。1 のとき、弾の色を少し落ち着かせ、白い芯を少し暗く透かし、キアイの光を弱める。描画だけで、判定には関係しない
var soft := 0.0

var _mm_halo: MultiMesh    # 弾の周りの淡い光(キアイの光・時の淀み/急流の光。いちばん下の層)
var _mm_color: MultiMesh
var _mm_core: MultiMesh
var _mm_ring: MultiMesh   # 当たり判定がまだ無い弾(発射直後)は中抜きのリングで描く
var _mats: Array[ShaderMaterial] = []
var _data_img: Image       # 弾の配列を並べた画像(1 チャンネルの小数。並びは下の説明)
var _data_texs: Array[ImageTexture] = []   # 順番に使い回す(DATA_TEX_N 枚)
var _data_k := 0
var _sent := {}            # シェーダーに最後に渡した値(変わったときだけ渡し直す)

## 描画は、弾ごとの計算を GPU で行う: 毎フレーム、弾の配列をそのまま 1 枚の画像にして送り、各層のシェーダーが
## 弾の番号(INSTANCE_ID)から位置・大きさ・色を決める(GDScript で弾ごとに書き込むと、弾が多いとき 1 フレームに数 ms かかるため)。
## 画像の並び(弾の番号 i。CAP = 配列の長さ): 2i, 2i+1 = 位置 / 2CAP + i = 半径 / 3CAP + i = 色の番号 / 4CAP + i = 残り無害距離 / 5CAP + i = 時間の倍率
const DATA_TEX_W := 64
const CAP := 4032          # 送る配列の長さ(DATA_TEX_W の倍数で、MAX_BULLETS 以上)
const DATA_TEX_H := CAP * 6 / DATA_TEX_W
## 送る画像は、毎フレーム別の 1 枚に書く(DATA_TEX_N 枚を順番に)。GPU がまだ前のフレームで使っている画像に書き込むと、
## 描き終わるのを待つことがあり、まれに 20ms ほど止まっていた。
const DATA_TEX_N := 3
const LAYER_BODY := 0
const LAYER_CORE := 1
const LAYER_RING := 2
const LAYER_GLOW := 3


func _init() -> void:
	pos.resize(CAP)
	vel.resize(MAX_BULLETS)
	rad.resize(CAP)
	col.resize(MAX_BULLETS)
	colf.resize(CAP)
	grace.resize(CAP)
	turn.resize(MAX_BULLETS)
	grazed.resize(MAX_BULLETS)
	kind.resize(MAX_BULLETS)
	age.resize(MAX_BULLETS)
	pa.resize(MAX_BULLETS)
	pb.resize(MAX_BULLETS)
	pc.resize(MAX_BULLETS)
	tscale.resize(CAP)
	wtgt.resize(MAX_BULLETS)


## 描画用ノードを作る(テストなど描画不要なときは呼ばない)。
func setup_render() -> void:
	_data_img = Image.create_empty(DATA_TEX_W, DATA_TEX_H, false, Image.FORMAT_RF)
	for k in range(DATA_TEX_N):
		_data_texs.append(ImageTexture.create_from_image(_data_img))
	_mm_halo = _make_layer(_make_halo_texture(), LAYER_GLOW)
	_mm_color = _make_layer(null, LAYER_BODY)
	_mm_core = _make_layer(null, LAYER_CORE)
	_mm_ring = _make_layer(_make_ring_texture(), LAYER_RING)


func _make_layer(tex: Texture2D, layer: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	mm.mesh = quad
	mm.instance_count = MAX_BULLETS
	var ident := PackedFloat32Array()   # 位置・大きさはシェーダーが決めるので、インスタンスの変換は全部そのまま(単位行列)
	ident.resize(MAX_BULLETS * 8)
	for i in range(MAX_BULLETS):
		ident[i * 8] = 1.0
		ident[i * 8 + 5] = 1.0
	mm.buffer = ident
	mm.custom_aabb = AABB(Vector3(-300, -300, 0), Vector3(1560, 1320, 0))   # インスタンスはどれも原点にあるので、描く範囲を自分で決める(画面外として間引かれないように)
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.texture = tex
	var sh := Shader.new()
	sh.code = BULLET_SHADER.replace("BLEND_MODE", "blend_premul_alpha" if layer == LAYER_GLOW else "blend_mix")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("layer", layer)
	mat.set_shader_parameter("data", _data_texs[0])
	mat.set_shader_parameter("cap", CAP)
	var pal := PackedColorArray()
	for c in PALETTE:
		pal.append(c)
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("slow_tint", WARP_SLOW_TINT)
	mat.set_shader_parameter("fast_tint", WARP_FAST_TINT)
	mat.set_shader_parameter("warp_glow_a", WARP_GLOW_A)
	mat.set_shader_parameter("warp_glow_size", WARP_GLOW_SIZE)
	mat.set_shader_parameter("warp_body_tint", WARP_BODY_TINT)
	inst.material = mat
	_mats.append(mat)
	add_child(inst)
	return mm


## 弾の層のシェーダー(本体・芯・リング・光で共通。layer で描くものを変える)。
## 本体と芯は、縁のぼかしを、弾の半径に対する割合ではなく、ほぼ一定のピクセル幅にする
## (以前のテクスチャは縁が半径の 22% で、大きい弾(弾サイズの「大」)は縁が太く、ぼやけて見えた。普通の大きさの弾の縁は、ほぼ同じ)。
const BULLET_SHADER := """
shader_type canvas_item;
render_mode BLEND_MODE;
uniform int layer = 0;   // 0 = 本体 / 1 = 白い芯 / 2 = リング(当たり判定がまだ無い弾) / 3 = 光
uniform sampler2D data : filter_nearest;
uniform int cap = 4032;
uniform vec4 palette[10];
uniform vec4 slow_tint;
uniform vec4 fast_tint;
uniform float warp_glow_a = 0.3;
uniform float warp_glow_size = 5.0;
uniform float warp_body_tint = 0.45;
uniform vec2 vis_center;
uniform float vis_r0 = 0.0;
uniform float vis_r1 = 0.0;
uniform float halo = 0.0;   // キアイの光の強さ(0 なら光らない)
uniform float soft = 0.0;   // 目に優しい表示(0 = ふつう / 1 = 色を落ち着かせ、白い芯と光を弱める)
varying float sz;
varying vec4 vc;

float fetch(int k) {
	return texelFetch(data, ivec2(k & 63, k >> 6), 0).r;
}

void vertex() {
	int i = INSTANCE_ID;
	vec2 p = vec2(fetch(2 * i), fetch(2 * i + 1));
	float r = fetch(2 * cap + i);
	vec4 base = palette[int(fetch(3 * cap + i) + 0.5) % 10];
	bool fresh = fetch(4 * cap + i) > 0.0;   // 発射直後で、当たり判定がまだ無い
	float ts = fetch(5 * cap + i);
	float st = clamp(abs(ts - 1.0) / 0.45, 0.0, 1.0);   // 時の淀み・急流の効き(0..1)
	vec3 tint = ts < 1.0 ? slow_tint.rgb : fast_tint.rgb;
	vec3 c = mix(base.rgb, tint, warp_body_tint * st);
	c = mix(c, vec3(dot(c, vec3(0.299, 0.587, 0.114))), 0.22 * soft) * (1.0 - 0.1 * soft);   // 目に優しい表示: 彩度と明るさを少し落とす
	float va = 1.0;   // 暗闇: 見える範囲の外ほど薄い
	if (vis_r1 > 0.0) {
		va = 1.0 - smoothstep(vis_r0, vis_r1, distance(p, vis_center));
	}
	float s = 0.0;
	if (layer == 0) {
		s = fresh ? 0.0 : r * 2.3;
		vc = vec4(c, va);
	} else if (layer == 1) {
		s = fresh ? 0.0 : r * 1.4 + 2.0;   // 白い芯の縁 = 当たり判定の縁(判定半径 = 0.7r。縁のぼかし分の 2px を足す)
		vc = vec4(vec3(1.0 - 0.1 * soft), (1.0 - 0.2 * soft) * va);   // 目に優しい表示: 芯の白を少し暗く・透かす(縁 = 当たり判定の位置は同じ)
	} else if (layer == 2) {
		s = fresh ? r * 2.3 : 0.0;
		vc = vec4(c, va);
	} else {
		// キアイの光は加算(不透明度 0 の、あらかじめ掛けた色)。時の淀み・急流の光は、重ねて塗る(白く飛ばない)
		float ha = halo * 0.4 * (1.0 - 0.6 * soft);
		vec3 hc = base.rgb;
		float over = 0.0;
		s = r * 7.0;
		float wa = warp_glow_a * st;
		if (wa > ha) {
			ha = wa;
			hc = tint;
			over = 1.0;
			s = r * warp_glow_size;
		}
		ha *= va;
		if (ha <= 0.004) {
			s = 0.0;
		}
		vc = vec4(hc * ha, ha * over);
	}
	if (va < 0.005) {
		s = 0.0;
	}
	sz = s;
	VERTEX = VERTEX * s + p;
}

void fragment() {
	if (layer == 3) {
		COLOR = vc * texture(TEXTURE, UV).a;
	} else if (layer == 2) {
		COLOR = vc * texture(TEXTURE, UV);
	} else {
		COLOR = vc;
		float d = length(UV - vec2(0.5)) * 2.0;
		if (layer == 1) {
			float rh = max(sz * 0.5 - 1.0, 0.5);   // 判定の半径(px)。縁は、そこを中心にした約 1.4px のぼかし(ほぼくっきり)
			COLOR.a *= 1.0 - smoothstep(rh - 0.7, rh + 0.7, d * sz * 0.5);
		} else {
			float w = clamp(2.0 / max(sz * 0.5, 1.0), 0.04, 0.22);   // 縁のぼかしの幅(半径に対する割合)。2px ぶん。小さい弾は従来どおり 22%
			COLOR.a *= 1.0 - smoothstep(1.0 - w, 1.0, d);
			float big = smoothstep(26.0, 38.0, sz);   // 大きい弾の本体に輪郭(本体を暗く・縁を明るく)。直径 26px 以下(普通・小)は 0、38px 以上(大)で 1
			float edge = smoothstep(0.74, 0.9, d);
			vec3 body = COLOR.rgb * 0.78;
			vec3 lit = mix(COLOR.rgb, vec3(1.0), 0.6);
			COLOR.rgb = mix(COLOR.rgb, mix(body, lit, edge), big);
		}
	}
}
"""


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
	colf[count] = color_idx
	grace[count] = grace_px
	turn[count] = turn_rate
	grazed[count] = 0
	tscale[count] = 1.0
	wtgt[count] = 1.0
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
		colf[i] = colf[count]
		grace[i] = grace[count]
		turn[i] = turn[count]
		grazed[i] = grazed[count]
		tscale[i] = tscale[count]
		wtgt[i] = wtgt[count]
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
func update(dt_all: float, ppos: Vector2, player_r: float, check_hit: bool, pprev := Vector2.INF) -> void:
	hit = false
	hit_dist = 0.0
	graze_count = 0
	var b := bounds
	# 自機の移動経路(pprev→ppos)上で判定する: 素早い移動で弾をすり抜けないように
	var seg := Vector2.ZERO if pprev == Vector2.INF else ppos - pprev
	var seg2 := seg.length_squared()
	var swept := seg2 > 4.0
	var warped := not warp.is_empty() or _ts_active
	var any_off := false
	var warp_on := not warp.is_empty()
	var eval_warp := false
	if warp_on:
		_warp_acc += dt_all
		if _warp_acc >= WARP_EVAL:
			_warp_acc = 0.0
			eval_warp = true
			_flatten_warp()
	var wz := _wz   # 淀みの形(数の並び)。弾ごとの判定は、関数を呼ばずにこの場で行う(弾の数 × 調べる回数ぶん呼ばれるため)
	var wn := wz.size()
	var bx0 := b.position.x   # 範囲の判定は、メソッド呼び出しを避けて、比較だけで行う(弾の数 × 刻みの回数ぶん呼ばれる)
	var by0 := b.position.y
	var bx1 := b.end.x
	var by1 := b.end.y
	var i := count - 1
	while i >= 0:
		var dt := dt_all
		if warped:
			var ts := tscale[i]
			var tgt := wtgt[i] if warp_on else 1.0
			if eval_warp:   # 淀みをまとめた外枠の外なら、調べるまでもなく 1(弾の大半)
				var wp := pos[i]
				tgt = 1.0
				if not (wp.x < _wb_x0 or wp.x > _wb_x1 or wp.y < _wb_y0 or wp.y > _wb_y1):
					var lo := 1.0
					var hi := 1.0
					var o := 0
					while o < wn:   # _warp_factor_flat と同じ判定
						var inside: bool
						if wz[o] == 0.0:
							inside = wp.x >= wz[o + 2] and wp.y >= wz[o + 3] and wp.x < wz[o + 4] and wp.y < wz[o + 5]
						else:
							var dx := wp.x - wz[o + 2]
							var dy := wp.y - wz[o + 3]
							inside = dx * dx + dy * dy <= wz[o + 4]
						if inside:
							lo = minf(lo, wz[o + 1])
							hi = maxf(hi, wz[o + 1])
						o += 6
					tgt = lo if lo < 1.0 else hi
				wtgt[i] = tgt
			if ts != tgt:
				ts = move_toward(ts, tgt, (WARP_ENTER if absf(tgt - 1.0) > absf(ts - 1.0) else WARP_EXIT) * dt_all)
				tscale[i] = ts
			if ts != 1.0:
				any_off = true
			dt = dt_all * ts
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
		if p.x < bx0 or p.x >= bx1 or p.y < by0 or p.y >= by1:
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
	_ts_active = any_off


## 淀み・急流の形(warp の辞書)を、弾ごとに調べやすい並び(_wz)と、全部をまとめた外枠(_wb_*)にする(調べるたびに 1 回)。
## 弾ごとに辞書を引くと重い(弾の数 × 形の数 × 調べる回数)ので、数の並びにしてから調べる。
## _wz: 形ごとに 6 個 [種類(0 = 長方形・1 = 円), 倍率, a, b, c, d](長方形: 左・上・右・下 / 円: 中心 x・中心 y・半径の 2 乗・未使用)
func _flatten_warp() -> void:
	_wz.resize(warp.size() * 6)
	_wb_x0 = INF
	_wb_y0 = INF
	_wb_x1 = -INF
	_wb_y1 = -INF
	var o := 0
	for w in warp:
		_wz[o + 1] = float(w.f)
		if w.has("rect"):
			var r: Rect2 = w.rect
			_wz[o] = 0.0
			_wz[o + 2] = r.position.x
			_wz[o + 3] = r.position.y
			_wz[o + 4] = r.end.x
			_wz[o + 5] = r.end.y
			_wb_x0 = minf(_wb_x0, r.position.x)
			_wb_y0 = minf(_wb_y0, r.position.y)
			_wb_x1 = maxf(_wb_x1, r.end.x)
			_wb_y1 = maxf(_wb_y1, r.end.y)
		else:
			var c: Vector2 = w.c
			var r2 := float(w.r2)
			var rr := sqrt(r2)
			_wz[o] = 1.0
			_wz[o + 2] = c.x
			_wz[o + 3] = c.y
			_wz[o + 4] = r2
			_wb_x0 = minf(_wb_x0, c.x - rr)
			_wb_y0 = minf(_wb_y0, c.y - rr)
			_wb_x1 = maxf(_wb_x1, c.x + rr)
			_wb_y1 = maxf(_wb_y1, c.y + rr)
		o += 6


## _warp_factor と同じ結果を、_flatten_warp で作った並びから求める(update の中で使う)。
func _warp_factor_flat(p: Vector2) -> float:
	var lo := 1.0
	var hi := 1.0
	var z := _wz
	var o := 0
	var n := z.size()
	while o < n:
		var inside: bool
		if z[o] == 0.0:
			inside = p.x >= z[o + 2] and p.y >= z[o + 3] and p.x < z[o + 4] and p.y < z[o + 5]
		else:
			var dx := p.x - z[o + 2]
			var dy := p.y - z[o + 3]
			inside = dx * dx + dy * dy <= z[o + 4]
		if inside:
			var f := z[o + 1]
			lo = minf(lo, f)
			hi = maxf(hi, f)
		o += 6
	return lo if lo < 1.0 else hi


## 位置 p の弾の、時間の目標の倍率(淀み・急流の中なら f。重なるときは、遅いものがあれば遅いほう、なければ速いほう)。
func _warp_factor(p: Vector2) -> float:
	var lo := 1.0
	var hi := 1.0
	for w in warp:
		var inside: bool = (w.rect as Rect2).has_point(p) if w.has("rect") else p.distance_squared_to(w.c) <= float(w.r2)
		if inside:
			lo = minf(lo, float(w.f))
			hi = maxf(hi, float(w.f))
	return lo if lo < 1.0 else hi


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


func sync_render() -> void:
	if _mm_color == null:
		return
	var n := count
	if n > 0:   # 弾の配列を、そのまま 1 枚の画像にして送る(並びは DATA_TEX_W の説明のとおり)
		var bytes := pos.to_byte_array()
		bytes.append_array(rad.to_byte_array())
		bytes.append_array(colf.to_byte_array())
		bytes.append_array(grace.to_byte_array())
		bytes.append_array(tscale.to_byte_array())
		_data_img.set_data(DATA_TEX_W, DATA_TEX_H, false, Image.FORMAT_RF, bytes)
		_data_k = (_data_k + 1) % DATA_TEX_N
		var tex := _data_texs[_data_k]
		tex.update(_data_img)
		for m in _mats:
			m.set_shader_parameter("data", tex)
	var halo_v := halo if halo > 0.01 else 0.0
	_send("halo", halo_v)
	_send("soft", soft)
	_send("vis_r1", vis_r1)
	if vis_r1 > 0.0:
		_send("vis_r0", vis_r0)
		_send("vis_center", vis_center)
	_mm_halo.visible_instance_count = n if halo_v > 0.0 or _ts_active else 0
	_mm_color.visible_instance_count = n
	_mm_core.visible_instance_count = n
	_mm_ring.visible_instance_count = n


## シェーダーの値を、変わったときだけ全部の層へ渡す。
func _send(key: String, v: Variant) -> void:
	if _sent.get(key) == v:
		return
	_sent[key] = v
	for m in _mats:
		m.set_shader_parameter(key, v)
