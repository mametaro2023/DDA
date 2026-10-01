extends RefCounted
## Beatmap → 発射イベント列。決定的(乱数を使わない)。
##
## 座標はアリーナ座標(osu 512x384 を 1.875 倍した 960x720)。時刻は秒。
##
## ## DDA 難易度 v4(このゲーム独自。Lv は本家の星と同じ目盛り)
## 難易度は「画面内にある弾の数(密度)」を軸に、弾速・弾サイズを補助項として測る。
##
##   1. 各弾が画面から出るまでの時間を解析的に求め、0.1 秒ごとの画面内の弾数 N(t) を得る(measure)。
##   2. score = 0.5 * 平均(N) + 0.5 * 上位5%点(N)                                    ← 密度
##   3. adj   = score * (弾速 / BASE_SPEED)^SPEED_EXP * (危険半径 / DANGER_REF)^SIZE_EXP  ← 弾速・弾サイズの補正
##   4. adj に長さ(持久力)の補正 length_factor(最初のノーツ〜最後の発射の時間 T)を掛ける(LENGTH_*)
##   5. Lv    = TARGET_TABLE の逆引き(adj → ★換算)- LEVEL_SHIFT(1.0)                 ← 本家の星と同じ目盛り(ただし 1 だけ厳しい: 同じ Lv なら、弾が多い)
##
## 生成の側は、本家 osu! の星評価(基準: star_rating.gd の推定値)に近づけるために、
##   - 目標の Lv は推定★そのもの。TARGET_TABLE(★→弾数)で目標の adj を決め、
##     Lv がそれに合うまで弾数の倍率を自動調整する。弾数そのものは、その瞬間の局所ノーツ密度に比例する。
##   - 弾速は星に応じて ±SPEED_VAR だけ変える(微調整)。速く/大きいほど、同じ Lv に必要な弾数は少なくなる。
##   - 弾数の下限/上限で合わせきれなかった分は、弾サイズ(基準の 0.6〜1.4 倍)で吸収する。
##   - 自機狙い・弾種の変化などの危険要素は、星に応じて解禁する。
##
## イベント: {t, pos, warn, shots, sfx}
## ショット: {n, speed, a0, spread, fan, aim, size, color, turn}
##   fan=false: 全周 n 等分(a0 起点) / fan=true: a0 中心に spread 幅の扇
##   aim=true: a0 は自機方向からの相対角

const Beatmap = preload("res://scripts/osu/beatmap.gd")

const ARENA := Vector2(960, 720)
const SCALE := 1.875
## 弾が消える範囲(bullet_field.gd の bounds と同じ)
const BOUNDS := Rect2(-12, -12, 984, 744)
## 計測時の自機狙いの基準点(自機の初期位置付近)
const AIM_REF := Vector2(480, 520)
const SAMPLE_DT := 0.1

## 基準の弾速(px/s)。星に応じて ±SPEED_VAR だけ変える。
const BASE_SPEED := 150.0
const SPEED_VAR := 0.15
## Lv に対する弾速の効き。発射が同じなら、弾速が 2 倍で画面内の弾数 N は約半分になる(弾が早く出ていく)ので、
## SPEED_EXP = 1 だと弾速は Lv に影響せず、1 を超えたぶんだけ「速いほど難しい」になる(1.25 なら弾速 2 倍で Lv の元の値が約 1.19 倍)。
## 0.5 では速い弾ほど Lv が下がってしまうため 1 を超える値にした(1.5 は大きすぎたので 1.25)(MOD「暴風雨」の弾速上昇で顕在化)。実測が難しいので控えめな値。
const SPEED_EXP := 1.25
## 危険半径 = 弾の当たり判定半径 + 自機の当たり判定半径(bullet_field.gd の HIT_SCALE と game_sim.gd の PLAYER_HIT_R と同じ値)。
## Lv は危険半径の SIZE_EXP 乗に比例する(ボット実験: 弾サイズ 4 倍の幅 ≒ 弾数 2.5 倍の幅で、指数はおよそ 1)。
const HIT_SCALE := 0.7
const PLAYER_HIT_R := 3.5
const DANGER_REF := 8.225   # 弾サイズ 6.75 のときの危険半径
const SIZE_EXP := 1.0
const SIZE_ABSORB_MIN := 0.6
const SIZE_ABSORB_MAX := 1.4
## 星(基準)が変わったとき、これ以上は Lv を追わない
const STAR_MIN := 1.0
const STAR_MAX := 6.6

## 長さ(持久力)の補正: 最初のノーツ〜最後の発射の時間 T(休憩地帯を含む)に応じて Lv を上下させる。
##   length_factor = clamp((T / LENGTH_REF)^LENGTH_EXP, LENGTH_MIN, LENGTH_MAX)   を adj に掛ける
## 基準の長さ(標準的な 1 曲 = 2 分)で 1。5 分なら約 1.15 倍、30 秒なら約 0.81 倍。密度が同じなら、長い譜面ほど難しい。
## 弾の生成(目標の弾数の調整)には入れない: 生成は密度だけで目標に合わせ、長さは Lv の計算でだけ足す。
const LENGTH_REF := 120.0

## 発生源の補正(_make_remap): 一様な分布へ寄せる割合と、発生源を置く範囲の余白
const REMAP_ALPHA := 1.0
const REMAP_EDGE := 0.45         # 発生源を端へ寄せる強さ(0..1)
const CDF_STEPS := 128           # 累積分布の表の分割数
const CDF_BANDWIDTH := 32.0      # 分布のなめらかさ(osu! 座標の px)
const SRC_MARGIN := Vector2(24, 24)

## 危険エリア(盤面の 3×3 のマス)。特定の小節ごとに、いくつかのマスを選ぶ(_make_zones)。
##   間隔(小節数): 約 ZONE_SECONDS_EASY〜ZONE_SECONDS_HARD 秒(★が高いほど短い)ぶんの小節(3〜8 小節)。そのうち最後の 2 小節は、エリアなし(次のエリアの予告だけ出す。予告は 2 小節前から)。
##   最初の弾の発射前(予告も)には出さない。
##   数 1〜8: ★が高いほど多く、その区間のノーツの密度・キアイ・疑似乱数で ±。全マスが危険になることはない(最低 1 マスは安全)。
##   安全に残すマスのひとつは、その区間のノーツの重心のマス(譜面の流れに沿って、安全地帯が動く)。
##   デバフの種類は、★が高いほど増える(slow・fragile → poison → big)。
const ZONE_SECONDS_EASY := 16.0   # 1 回のエリアの周期(秒)の目安。★が低いとき
const ZONE_SECONDS_HARD := 9.0    # ★が高いとき
const ZONE_MIN_MEASURE := 0.8     # 小節の長さの下限(秒)。これより短い(拍子が極端な)ときは、2 小節を 1 つと見なす
## 曲がる弾の角速度(rad/s)の最大(★に応じて増える)
const CURL_RATE := 0.5

## 表示する Lv の厳しさ。同じ弾幕の Lv を、TARGET_TABLE から読んだ値より LEVEL_SHIFT だけ小さく表示する(= 同じ Lv なら、以前より弾が多く、難しい)。
## 生成の目標も、その分だけ上の★の弾数に合わせる(Lv = 推定★ のまま。表示の目盛りだけが厳しくなる)。
const LEVEL_SHIFT := 1.0
const LENGTH_EXP := 0.15
const LENGTH_MIN := 0.8
const LENGTH_MAX := 1.3

## 星 → 目標の難易度スコア(画面内の弾数)。線形補間する。
const TARGET_TABLE := [
	[1.0, 8.0], [1.5, 12.0], [2.1, 28.0], [2.5, 40.0], [3.7, 80.0],
	[4.4, 105.0], [5.2, 135.0], [5.9, 165.0], [6.7, 200.0],
]

## 弾数の規則: 局所ノーツ密度 r(前後 RATE_WINDOW 秒のオブジェクト数 / 窓幅, 個/秒)に比例して増やす。
##   リングの方向数 = round(2 * mul * (RING_A + RING_B * r + RING_C * r^2))    (3..44)
##   スライダー連射の本数 = round(mul * (ARMS_A + ARMS_B * r))   (1..9)
## mul は Lv が目標に合うよう自動調整する(density_mul は目標にかかる)。
const RATE_WINDOW := 1.5
const RING_A := 1.8
const RING_B := 0.4
const RING_C := 0.15
const ARMS_A := 0.8
const ARMS_B := 0.6


static func to_arena(p: Vector2) -> Vector2:
	return p * SCALE


## opts: density_mul(目標の弾数にかかる倍率), size_mul(弾サイズの倍率。実験用)
## 戻り値: events, gizmos, warn_lead, rating{mean,p95,peak,score}, level(Lv), speed, size, stars, target_level
static func generate(bm: Beatmap, opts := {}) -> Dictionary:
	var stars := reference_stars(bm)
	var k := clampf((stars - STAR_MIN) / (STAR_MAX - STAR_MIN), 0.0, 1.0)
	var speed := BASE_SPEED * lerpf(1.0 - SPEED_VAR, 1.0 + SPEED_VAR, k)
	var size := base_size(k) * float(opts.get("size_mul", 1.0))
	# 目標の adj(弾速・弾サイズの補正後スコア)。density_mul が 1 なら目標 Lv = 推定★
	var target_adj := target_score_for(stars + LEVEL_SHIFT) * float(opts.get("density_mul", 1.0))
	var target_level := maxf(stars_for_score(target_adj) - LEVEL_SHIFT, 0.0)
	# 1) 弾数の倍率 mul を自動調整して、adj を目標に合わせる
	var mul := 1.0
	var out := {}
	var rating := {}
	for i in range(6):
		out = _generate(bm, k, mul, speed, size)
		rating = measure(out.events)
		var adj := adjusted_score(rating.score, speed, size)
		if rating.score < 0.5 or absf(adj - target_adj) <= target_adj * 0.05:
			break
		mul = clampf(mul * target_adj / adj, 0.1, 6.0)
	# 2) 弾数の下限/上限で合わせきれなかった分は、弾サイズで吸収する(弾数 N(t) は変わらない)
	var adj_now := adjusted_score(rating.score, speed, size)
	if rating.score >= 0.5 and absf(adj_now - target_adj) > target_adj * 0.03:
		var danger := danger_radius(size) * target_adj / adj_now
		var absorbed := clampf((danger - PLAYER_HIT_R) / HIT_SCALE, size * SIZE_ABSORB_MIN, size * SIZE_ABSORB_MAX)
		if not is_equal_approx(absorbed, size):
			size = absorbed
			out = _generate(bm, k, mul, speed, size)
	out["rating"] = rating
	var br: Array = []
	for b in bm.breaks:
		br.append([b[0] / 1000.0, b[1] / 1000.0])
	out["breaks"] = br
	out["level"] = level_of(rating.score, speed, size, PLAYER_HIT_R, rating.duration)
	out["speed"] = speed
	out["size"] = size
	out["stars"] = stars
	out["target_level"] = target_level
	out["mul"] = mul
	out["zones"] = _make_zones(bm, k)   # 危険エリアの予定(弾幕とは別。難易度の測定には入れない)
	return out


## メニュー用: パターンを作って難易度だけ返す。
static func rate(bm: Beatmap, density_mul := 1.0) -> Dictionary:
	return summary(generate(bm, {"density_mul": density_mul}))


## 生成結果(または Mods.apply の結果)から、難易度の要約 {mean, p95, peak, score, level, speed, size, stars, base_level} を作る。
static func summary(g: Dictionary) -> Dictionary:
	var r: Dictionary = g.rating.duplicate()
	r["level"] = g.level
	r["base_level"] = g.get("base_level", g.level)
	r["speed"] = g.speed
	r["size"] = g.size
	r["stars"] = g.stars
	return r


## 星(0..1 に正規化した k)に応じた基準の弾サイズ。高難度ほど小さく(密度が高いほど見やすいように)。
static func base_size(k: float) -> float:
	return lerpf(7.5, 6.0, k)


## 弾サイズ → 危険半径(当たり判定 + 自機の当たり判定)。
static func danger_radius(size: float, player_r := PLAYER_HIT_R) -> float:
	return HIT_SCALE * size + player_r


## 弾速・弾サイズの補正をかけた難易度スコア adj。
static func adjusted_score(score: float, speed: float, size: float, player_r := PLAYER_HIT_R) -> float:
	return score * pow(speed / BASE_SPEED, SPEED_EXP) * pow(danger_radius(size, player_r) / DANGER_REF, SIZE_EXP)


## 長さ(持久力)の補正の倍率。duration = 最初のノーツ〜最後の発射の秒数(0 以下なら補正なし)。
static func length_factor(duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(pow(duration / LENGTH_REF, LENGTH_EXP), LENGTH_MIN, LENGTH_MAX)


## Lv(本家の星と同じ目盛り)= adj(× 長さの補正)を TARGET_TABLE で逆引きした★換算値から、LEVEL_SHIFT を引いたもの。
static func level_of(score: float, speed: float, size: float, player_r := PLAYER_HIT_R, duration := LENGTH_REF) -> float:
	return maxf(stars_for_score(adjusted_score(score, speed, size, player_r) * length_factor(duration)) - LEVEL_SHIFT, 0.0)


## TARGET_TABLE(★→スコア)の逆引き。表の外は端の傾きで延長する(下側は原点へ向かう)。
static func stars_for_score(s: float) -> float:
	var tbl := TARGET_TABLE
	if s <= tbl[0][1]:
		return tbl[0][0] * maxf(s, 0.0) / tbl[0][1]
	for i in range(1, tbl.size()):
		if s <= tbl[i][1]:
			var a: Array = tbl[i - 1]
			var b: Array = tbl[i]
			return lerpf(a[0], b[0], (s - a[1]) / (b[1] - a[1]))
	var p: Array = tbl[tbl.size() - 2]
	var q: Array = tbl[tbl.size() - 1]
	return q[0] + (s - q[1]) * (q[0] - p[0]) / (q[1] - p[1])


## 基準の星評価(推定)。取れなければ物量密度から代用する。
static func reference_stars(bm: Beatmap) -> float:
	if bm.stars > 0.0:
		return bm.stars
	return 1.0 + clampf((bm.density() - 0.5) / 4.5, 0.0, 1.0) * (STAR_MAX - STAR_MIN)


## 星 → 目標の難易度スコア(TARGET_TABLE を線形補間。表の外側は端の傾きで延長する)。
static func target_score_for(stars: float) -> float:
	var tbl := TARGET_TABLE
	if stars <= tbl[0][0]:
		return tbl[0][1]
	for i in range(1, tbl.size()):
		if stars <= tbl[i][0]:
			var a: Array = tbl[i - 1]
			var b: Array = tbl[i]
			return lerpf(a[1], b[1], (stars - a[0]) / (b[0] - a[0]))
	# 表の最後より上の★は、最後の区間の傾きで延長する(★6.7 で頭打ちにしない。stars_for_score の逆引きと対称)
	var p: Array = tbl[tbl.size() - 2]
	var q: Array = tbl[tbl.size() - 1]
	return q[1] + (stars - q[0]) * (q[1] - p[1]) / (q[0] - p[0])


static func _generate(bm: Beatmap, k: float, mul: float, speed: float, size: float) -> Dictionary:
	var base := {
		"k": k,
		"speed": speed,
		"size": size,
		"variants": k >= 0.3,     # ヒットサウンドによる弾種の変化
		"combo_aim": k >= 0.4,    # new combo の自機狙い
		"aim_trail": k >= 0.5,    # スライダー連射内の自機狙い
		"trail_div": lerpf(0.4, 4.0, k * k),
		"light_gap": lerpf(0.4, 0.13, k),
		"half_gap": lerpf(0.6, 0.2, k),
		"warn_lead": lerpf(0.95, 0.5, k),
	}
	base["rm"] = _make_remap(bm)   # 発生源の位置を、画面全体に散らす(隅・縁も発生源にする)
	var events: Array = []
	var gizmos: Array = []
	var prev_primary := -10.0
	var idx := 0
	var times: Array = []
	for o in bm.hit_objects:
		times.append(o.time / 1000.0)
	for o in bm.hit_objects:
		var t: float = o.time / 1000.0
		# このオブジェクトの弾数(局所ノーツ密度に比例)
		var rate := _local_rate(times, idx)
		var c := base.duplicate()
		c["ring_n"] = clampi(int(round(2.0 * mul * (RING_A + RING_B * rate + RING_C * rate * rate))), 3, 44)
		c["arms"] = clampi(int(round(mul * (ARMS_A + ARMS_B * rate))), 1, 9)
		var kiai := bm.kiai_at(o.time)
		var ci: int = (o.combo_index % 5) + (5 if kiai else 0)
		var a0 := fposmod(idx * 0.7853982 + o.combo_index * 0.4, TAU)
		var pos := to_source(o.pos, c.rm)
		# 連打の間引き
		var gap := t - prev_primary
		var tier := 0
		if gap < c.light_gap:
			tier = 2
		elif gap < c.half_gap:
			tier = 1
		prev_primary = t
		match o.kind:
			Beatmap.KIND_CIRCLE:
				events.append(_ev(t, pos, true, _circle_shots(o.hitsound, o.new_combo, tier, a0, ci, c),
					_circle_sfx(o.hitsound, tier, c)))
			Beatmap.KIND_SLIDER:
				_slider(bm, o, t, pos, tier, a0, ci, c, events, gizmos)
			Beatmap.KIND_SPINNER:
				_spinner(o, t, ci, c, events, gizmos)
		idx += 1
	events.sort_custom(func(a, b): return a.t < b.t)
	gizmos.sort_custom(func(a, b): return a.t < b.t)
	return {
		"events": events,
		"gizmos": gizmos,
		"warn_lead": base.warn_lead,
	}


static func _ev(t: float, pos: Vector2, warn: bool, shots: Array, sfx := "") -> Dictionary:
	return {"t": t, "pos": pos, "warn": warn, "shots": shots, "sfx": sfx}


## 発生源の位置の補正。ノーツの位置は画面の中央に偏る(隅は少ない)ので、譜面全体のノーツ位置の分布を一様に近づけて、
## 画面の隅・縁にも発生源が来るようにする。x と y を別々に、累積分布で一様な位置へ写し、元の位置と REMAP_ALPHA の割合で混ぜる。
static func _make_remap(bm: Beatmap) -> Dictionary:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for o in bm.hit_objects:
		xs.append(o.pos.x)
		ys.append(o.pos.y)
	return {"n": xs.size(), "tx": _cdf_table(xs, -64.0, 576.0), "ty": _cdf_table(ys, -48.0, 432.0)}


## 累積分布の表(lo..hi を CDF_STEPS 等分)。ノーツ位置ごとの階段ではなく、幅 CDF_BANDWIDTH のなだらかな山を足した、連続で滑らかな曲線にする
## (階段のままだと、スライダーの軌道をこの補正で写したとき、折れ線のようにカクカクになる)。
static func _cdf_table(vals: PackedFloat32Array, lo: float, hi: float) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	for i in range(CDF_STEPS + 1):
		var x := lerpf(lo, hi, float(i) / CDF_STEPS)
		var sum := 0.0
		for v in vals:
			sum += 1.0 / (1.0 + exp(-1.702 * (x - v) / CDF_BANDWIDTH))   # 正規分布の累積に近い、なめらかな階段
		t.append(sum / maxf(float(vals.size()), 1.0))
	return t


static func to_source(p_osu: Vector2, rm: Dictionary) -> Vector2:
	var orig := to_arena(p_osu)
	if rm.n < 8:
		return orig
	var eq := Vector2(lerpf(SRC_MARGIN.x, ARENA.x - SRC_MARGIN.x, _edge_push(_cdf(rm.tx, -64.0, 576.0, p_osu.x))),
			lerpf(SRC_MARGIN.y, ARENA.y - SRC_MARGIN.y, _edge_push(_cdf(rm.ty, -48.0, 432.0, p_osu.y))))
	return orig.lerp(eq, REMAP_ALPHA)


## 0..1 の位置を、端へ寄せる。中央から撃つ弾は画面の中央を何度も通るので、発生源を一様にしても、弾の通過は中央に偏る。端の発生源を多くして、通過の密度をならす。
## f(u) = u - a/(2π)·sin(2πu)。傾きは中央で 1+a、端で 1-a(なめらか。中央に折れ目ができない)。
static func _edge_push(u: float) -> float:
	return clampf(u - REMAP_EDGE / TAU * sin(TAU * u), 0.0, 1.0)


## 表を線形補間して、v での累積分布(0..1)を返す。
static func _cdf(table: PackedFloat32Array, lo: float, hi: float, v: float) -> float:
	var f := clampf((v - lo) / (hi - lo), 0.0, 1.0) * CDF_STEPS
	var i := mini(int(f), CDF_STEPS - 1)
	var lo_v: float = table[0]
	var hi_v: float = table[CDF_STEPS]
	var y := lerpf(table[i], table[i + 1], f - i)
	return clampf((y - lo_v) / maxf(hi_v - lo_v, 0.000001), 0.0, 1.0)


## 小節の始まり [[開始秒, 長さ秒], ...](最初のノーツの 1 小節前〜最後のノーツ)。タイミングポイント(赤線)の拍子と BPM から数える。
static func measure_starts(bm: Beatmap) -> Array:
	var pts: Array = bm.timing_points.filter(func(p): return p.uninherited and float(p.beat_length) > 0.0)
	var t_first: float = bm.first_time() / 1000.0
	var t_last: float = bm.last_time() / 1000.0
	if pts.is_empty():
		pts = [{"time": t_first * 1000.0, "beat_length": 500.0, "meter": 4}]
	var out: Array = []
	for i in range(pts.size()):
		var p: Dictionary = pts[i]
		var st: float = float(p.time) / 1000.0
		var len: float = float(p.beat_length) / 1000.0 * float(maxi(int(p.meter), 1))
		while len < ZONE_MIN_MEASURE:
			len *= 2.0
		var nxt: float = float(pts[i + 1].time) / 1000.0 if i + 1 < pts.size() else t_last + len
		var t := st
		while t < nxt - 0.001 and t <= t_last:
			if t + len > t_first - len:
				out.append([t, len])
			t += len
	return out


## 危険エリアの予定(時刻順)。各要素: {t(発動), end(終わり), lead(予告の長さ), cells: [{c: マス番号 0..8, type}]}。決定的(同じ譜面なら同じ)。
static func _make_zones(bm: Beatmap, k: float) -> Array:
	var ms := measure_starts(bm)
	if ms.size() < 3 or bm.hit_objects.is_empty():
		return []
	var kk := clampf((k - 0.1) / 0.9, 0.0, 1.0)
	var period_s := lerpf(ZONE_SECONDS_EASY, ZONE_SECONDS_HARD, kk)
	var max_n := 1 + int(round(7.0 * kk))
	var types: Array = ["slow", "fragile"]
	if kk >= 0.3:
		types.append("poison")
	if kk >= 0.55:
		types.append("big")
	var rm := _make_remap(bm)
	var t_first: float = bm.first_time() / 1000.0
	var t_last: float = bm.last_time() / 1000.0
	var span := maxf(t_last - t_first, 1.0)
	var avg_rate := float(bm.hit_objects.size()) / span
	var seed := (bm.hit_objects.size() * 2654435 + int(t_first * 1000.0)) & 0x7fffffff
	var zones: Array = []
	var i := 2   # 予告は 2 小節前から出すので、3 小節目以降
	while i < ms.size():
		var start: float = ms[i][0]
		if start > t_last:
			break
		var lead := float(ms[i - 2][1]) + float(ms[i - 1][1])   # 予告の長さ = 直前の 2 小節
		if start - lead < t_first - 0.001:   # 最初の弾の発射前には、予告も出さない(イントロをスキップできる間は何も出ない)
			i += 1
			continue
		var period := clampi(int(round(period_s / float(ms[i][1]))), 3, 8)   # この周期の小節数
		var last_idx := mini(i + period - 3, ms.size() - 1)   # 最後の 2 小節は休み(次のエリアの予告だけ出る)
		if last_idx < i:
			last_idx = i
		var end: float = float(ms[last_idx][0]) + float(ms[last_idx][1])
		# この区間のノーツ: 密度と、重心(安全に残すマス)
		var cnt := 0
		var sum := Vector2.ZERO
		var kiai := false
		for o in bm.hit_objects:
			var ot: float = o.time / 1000.0
			if ot >= start and ot < end:
				cnt += 1
				sum += to_source(o.pos, rm)
				kiai = kiai or bm.kiai_at(o.time)
		var rate := float(cnt) / maxf(end - start, 0.5)
		seed = _lcg(seed)
		var noise := float((seed >> 8) % 3) - 1.0   # -1, 0, +1
		var want := 1.0 + 4.5 * kk + (rate / maxf(avg_rate, 0.001) - 1.0) * 1.0 + (0.7 if kiai else 0.0) + noise * 0.8
		var n := clampi(int(round(want)), 1, max_n)
		var safe := -1
		if cnt > 0:
			var c := sum / float(cnt)
			safe = clampi(int(c.y / (ARENA.y / 3.0)), 0, 2) * 3 + clampi(int(c.x / (ARENA.x / 3.0)), 0, 2)
		# 危険にするマスを選ぶ(疑似乱数で並べ替えて、安全なマスを除いた先頭 n 個)
		var order: Array = []
		for c in range(9):
			if c != safe:
				order.append(c)
		for j in range(order.size() - 1, 0, -1):
			seed = _lcg(seed)
			var r := (seed >> 8) % (j + 1)
			var tmp = order[j]
			order[j] = order[r]
			order[r] = tmp
		var cells: Array = []
		for j in range(mini(n, order.size())):
			seed = _lcg(seed)
			cells.append({"c": int(order[j]), "type": types[(seed >> 8) % types.size()]})
		cells.sort_custom(func(a, b): return a.c < b.c)
		zones.append({"t": start, "end": end, "lead": lead, "cells": cells})
		i += period
	return zones


static func _lcg(x: int) -> int:
	return (x * 1103515245 + 12345) & 0x7fffffff


static func _polyline_at(pts: PackedVector2Array, frac: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var target := total * frac
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if acc + seg >= target and seg > 0.0:
			return pts[i - 1].lerp(pts[i], (target - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]


static func _shot(n: int, speed: float, a0: float, ci: int, c: Dictionary,
		spread := TAU, fan := false, aim := false, turn := 0.0, size_mul := 1.0) -> Dictionary:
	return {"n": n, "speed": speed, "a0": a0, "spread": spread, "fan": fan,
		"aim": aim, "size": c.size * size_mul, "color": ci, "turn": turn}


static func _circle_sfx(hs: int, tier: int, c: Dictionary) -> String:
	if tier == 2:
		return "tick"
	if tier == 1 or not c.variants:
		return "pop"
	if hs & Beatmap.HS_FINISH:
		return "boom"
	if hs & Beatmap.HS_CLAP:
		return "clap"
	if hs & Beatmap.HS_WHISTLE:
		return "whistle"
	return "pop"


static func _circle_shots(hs: int, new_combo: bool, tier: int, a0: float, ci: int, c: Dictionary) -> Array:
	var n: int = c.ring_n
	var s: float = c.speed
	var k: float = c.k
	var shots: Array = []
	if tier == 2:
		if c.aim_trail:
			shots.append(_shot(1, s * 1.1, 0.0, ci, c, TAU, true, true))
		else:
			shots.append(_shot(maxi(n / 3, 3), s, a0, ci, c))
		return shots
	if tier == 1:
		shots.append(_shot(maxi(n / 2, 3), s, a0, ci, c))
		return shots
	if not c.variants:
		shots.append(_shot(n, s, a0, ci, c))
	elif hs & Beatmap.HS_FINISH:
		shots.append(_shot(n, s, a0, ci, c))
		shots.append(_shot(n, s * 0.7, a0 + PI / n, ci, c))
	elif hs & Beatmap.HS_CLAP:
		var h := maxi(n / 2, 3)
		var curl := CURL_RATE * k if k >= 0.35 else 0.0   # 曲がる弾(向きは、リングごとに交互。隙間の位置が時間で動き、少しの移動では避けきれない)
		var sgn := 1.0 if int(a0 * 10.0) % 2 == 0 else -1.0
		shots.append(_shot(h, s, a0, ci, c, TAU, false, false, curl * sgn))
		shots.append(_shot(h, s * 0.85, a0 + 0.25, ci, c, TAU, false, false, -curl * sgn))
		shots.append(_shot(h, s * 0.7, a0 + 0.5, ci, c, TAU, false, false, curl * sgn))
	elif hs & Beatmap.HS_WHISTLE:
		shots.append(_shot(3 + int(2.0 * k), s * 1.15, 0.0, ci, c, 0.6, true, true))
		shots.append(_shot(maxi(n / 2, 3), s * 0.8, a0, ci, c))
	else:
		shots.append(_shot(n, s, a0, ci, c))
	if new_combo and c.combo_aim:
		shots.append(_shot(1, s * 1.2, 0.0, ci, c, TAU, true, true))
	return shots


static func _slider(bm: Beatmap, o: Dictionary, t: float, pos: Vector2, tier: int, a0: float,
		ci: int, c: Dictionary, events: Array, gizmos: Array) -> void:
	var s: float = c.speed
	var curve = o.curve
	var span: float = o.span_duration / 1000.0
	var repeats: int = o.repeats
	var end_t: float = o.end_time / 1000.0
	# 軌道(アリーナ座標)
	# 軌道の形はそのまま(曲線のなめらかさを保つ)に、頭の位置の補正ぶんだけ平行移動する。画面からはみ出さないように、移動量を抑える
	var pts := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in curve.points:
		var q := to_arena(p)
		pts.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	var off := to_source(o.pos, c.rm) - to_arena(o.pos)
	off.x = clampf(off.x, SRC_MARGIN.x - lo.x, ARENA.x - SRC_MARGIN.x - hi.x) if hi.x - lo.x < ARENA.x - 2.0 * SRC_MARGIN.x else 0.0
	off.y = clampf(off.y, SRC_MARGIN.y - lo.y, ARENA.y - SRC_MARGIN.y - hi.y) if hi.y - lo.y < ARENA.y - 2.0 * SRC_MARGIN.y else 0.0
	for i in range(pts.size()):
		pts[i] += off
	pos = pts[0]   # 頭の発射位置も、軌道の始点に合わせる
	gizmos.append({"kind": "slider", "t": t, "end": end_t, "points": pts,
		"span": span, "repeats": repeats, "color": ci})
	# 頭
	events.append(_ev(t, pos, true, _circle_shots(o.hitsound, o.new_combo, tier, a0, ci, c),
		_circle_sfx(o.hitsound, tier, c)))
	# 軌道上の連射(回転する複数方向)
	var beat: float = bm.beat_length_at(o.time) / 1000.0
	var div: float = c.trail_div
	var interval := maxf(beat / div, 0.12)
	var m := 1
	var rot := a0
	while true:
		var tau_t := t + m * interval
		if tau_t >= end_t - 0.06:
			break
		var u := (tau_t - t) / span if span > 0.0 else 0.0
		var slide := int(floor(u))
		var frac := u - slide
		if slide % 2 == 1:
			frac = 1.0 - frac
		var p := _polyline_at(pts, frac)
		var shots: Array = []
		shots.append(_shot(c.arms, s * 0.8, rot, ci, c, TAU, false, false, 0.0, 0.85))
		if c.aim_trail and m % 4 == 0:
			shots.append(_shot(1, s * 1.0, 0.0, ci, c, TAU, true, true, 0.0, 0.85))
		events.append(_ev(tau_t, p, false, shots, "tick"))
		rot += 0.5
		m += 1
	# 折り返し点/終点(頭は上で発射済み)
	for j in range(1, repeats + 1):
		var edge_t := t + j * span
		var at_end := (j % 2 == 1)
		var ep := _polyline_at(pts, 1.0 if at_end else 0.0)
		var eh: int = o.edge_sounds[j] if j < o.edge_sounds.size() else 0
		var n: int = c.ring_n
		var edge_shots: Array = []
		var sfx := "pop"
		if eh & Beatmap.HS_FINISH and c.variants:
			edge_shots.append(_shot(n, s * 0.9, rot, ci, c))
			sfx = "boom"
		else:
			edge_shots.append(_shot(maxi(n / 2, 3), s * 0.9, rot, ci, c))
		events.append(_ev(edge_t, ep, false, edge_shots, sfx))


static func _spinner(o: Dictionary, t: float, ci: int, c: Dictionary, events: Array, gizmos: Array) -> void:
	var k: float = c.k
	var center := to_arena(Vector2(256, 192))
	var end_t: float = o.end_time / 1000.0
	gizmos.append({"kind": "spinner", "t": t, "end": end_t, "pos": center, "color": ci})
	events.append(_ev(t, center, true, [], "pop"))
	var arms: int = maxi(c.arms, 2)
	var speed: float = c.speed * 0.85
	var a := 0.0
	var tt := t + 0.3
	var n := 0
	while tt < end_t:
		events.append(_ev(tt, center, false, [_shot(arms, speed, a, ci, c, TAU, false, false, 0.0, 0.9)],
			"tick" if n % 3 == 0 else ""))
		a += 0.42
		tt += lerpf(0.18, 0.1, k)
		n += 1


## ショット内 i 番目の弾の角度。base は狙い角を加算済みの基準角。
static func shot_angle(s: Dictionary, base: float, i: int) -> float:
	var n: int = s.n
	if s.fan:
		if n > 1:
			return base + s.spread * (float(i) / float(n - 1) - 0.5)
		return base
	return base + TAU * float(i) / float(n)


## 直進する弾が範囲外に出るまでの時間(秒)。
static func _exit_time(p: Vector2, d: Vector2, speed: float) -> float:
	var tx := INF
	var ty := INF
	if d.x > 0.000001:
		tx = (BOUNDS.end.x - p.x) / d.x
	elif d.x < -0.000001:
		tx = (BOUNDS.position.x - p.x) / d.x
	if d.y > 0.000001:
		ty = (BOUNDS.end.y - p.y) / d.y
	elif d.y < -0.000001:
		ty = (BOUNDS.position.y - p.y) / d.y
	return maxf(minf(tx, ty), 0.0) / speed


## DDA 難易度 v1: 画面内の弾数 N(t) から {mean, p95, peak, score} を返す(events は時刻順)。
##   score = 0.5 * mean + 0.5 * p95   (最初〜最後の発射の間を 0.1 秒ごとに評価)
static func measure(events: Array) -> Dictionary:
	if events.is_empty():
		return {"mean": 0.0, "p95": 0.0, "peak": 0.0, "score": 0.0, "duration": 0.0}
	# 計測の区間は「最初のノーツ(最初に弾を撃つイベント)」から「最後の発射」まで。
	# 曲頭のイントロ(譜面が置かれていない部分)は含めない。
	var t0 := -1.0
	var t1 := 0.0
	for e in events:
		if not e.shots.is_empty():
			if t0 < 0.0:
				t0 = e.t
			t1 = e.t
	if t0 < 0.0:
		return {"mean": 0.0, "p95": 0.0, "peak": 0.0, "score": 0.0, "duration": 0.0}
	var cells := int((t1 + 20.0) / SAMPLE_DT) + 3
	var diff := PackedInt32Array()
	diff.resize(cells)
	for e in events:
		var p: Vector2 = e.pos
		for s in e.shots:
			var i0 := maxi(int(e.t / SAMPLE_DT), 0)
			var base: float = s.a0
			if s.aim:
				base += (AIM_REF - p).angle()
			for i in range(s.n):
				var life := _exit_time(p, Vector2.from_angle(shot_angle(s, base, i)), s.speed)
				var i1 := mini(int((e.t + life) / SAMPLE_DT) + 1, cells - 1)
				diff[i0] += 1
				diff[i1] -= 1
	var a := maxi(int(t0 / SAMPLE_DT), 0)
	var b := int(t1 / SAMPLE_DT)
	var counts := PackedInt32Array()
	var run := 0
	for i in range(0, b + 1):
		run += diff[i]
		if i >= a:
			counts.append(run)
	var sum := 0
	for v in counts:
		sum += v
	var mean := float(sum) / float(maxi(counts.size(), 1))
	counts.sort()
	var p95 := float(counts[mini(int(counts.size() * 0.95), counts.size() - 1)]) if counts.size() > 0 else 0.0
	var peak := float(counts[counts.size() - 1]) if counts.size() > 0 else 0.0
	return {"mean": mean, "p95": p95, "peak": peak, "score": 0.5 * mean + 0.5 * p95, "duration": t1 - t0}


## idx 番目のオブジェクト周辺(前後 RATE_WINDOW 秒)のノーツ密度(個/秒)。
static func _local_rate(times: Array, idx: int) -> float:
	var t: float = times[idx]
	var count := 1
	var j := idx - 1
	while j >= 0 and t - times[j] <= RATE_WINDOW:
		count += 1
		j -= 1
	j = idx + 1
	while j < times.size() and times[j] - t <= RATE_WINDOW:
		count += 1
		j += 1
	return float(count) / (2.0 * RATE_WINDOW)
