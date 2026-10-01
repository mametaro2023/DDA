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
const REMAP_EDGE := 0.8           # 1 未満: 発生源を端へ寄せる
const SRC_MARGIN := Vector2(24, 24)

## 画面全体を使う弾幕(壁・収束リング)。★に対応する k が SPECIAL_K_MIN 以上の譜面で、強い拍(new combo)に挟む。
## 間隔は、★が高いほど WALL_GAP_MAX → WALL_GAP_MIN 秒へ詰まる。壁と収束リングは交互。
const SPECIAL_K_MIN := 0.2
const WALL_GAP_MAX := 10.0
const WALL_GAP_MIN := 5.0
const WALL_SPEED := 0.9             # 壁の速さ(基準の弾速に対する倍率)
const WALL_SPACING := 18.0          # 弾の間隔(自機の当たり判定より狭く、すり抜けられない)
const WALL_GAP_W := 150.0           # 隙間の幅
const WALL_GAP_SEPARATION := 260.0  # 前の隙間から、これ以上離す
const DOOR_R := 260.0
const DOOR_SPEED := 0.75
const DOOR_SPACING := 20.0
const DOOR_GAP_ANG := 0.7           # 収束リングの隙間の角度(rad)

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
	var wall_t := -100.0       # 最後に壁を出した時刻
	var door_t := -100.0       # 最後に収束リングを出した時刻
	var wall_n := 0
	var wall_gaps := [-1000.0, -1000.0]   # 前の壁の隙間の位置(横向き・縦向きの別。次は、そこから離す)
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
		# 強い拍(new combo)で、画面全体を使う弾幕(壁 / 収束リング)を挟む。隙間は、譜面の流れ(数ノーツ先の位置)に置く
		if o.new_combo and o.kind != Beatmap.KIND_SPINNER and k >= SPECIAL_K_MIN:
			var nxt: Vector2 = to_source(bm.hit_objects[mini(idx + 3, bm.hit_objects.size() - 1)].pos, c.rm)
			var gap_s := lerpf(WALL_GAP_MAX, WALL_GAP_MIN, clampf((k - SPECIAL_K_MIN) / (1.0 - SPECIAL_K_MIN), 0.0, 1.0))
			if t - maxf(wall_t, door_t) >= gap_s:
				if wall_n % 2 == 0:
					var ax := (wall_n / 2) % 2   # 左右からの壁と、上下からの壁は、交互(隙間の位置の軸が違う)
					wall_gaps[ax] = _wall(t, wall_n / 2, nxt, wall_gaps[ax], ci, c, events, gizmos)
					wall_t = t
				else:
					_door_ring(t, pos, nxt, ci, c, events)
					door_t = t
				wall_n += 1
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


## 位置と速度を最初から決めた弾の集まり(壁・収束リング)。list = [[位置, 速度ベクトル], ...]
static func _list_shot(list: Array, speed: float, ci: int, c: Dictionary, size_mul := 1.0) -> Dictionary:
	return {"n": list.size(), "speed": speed, "a0": 0.0, "spread": 0.0, "fan": false, "aim": false,
		"size": c.size * size_mul, "color": ci, "turn": 0.0, "list": list}


## 発生源の位置の補正。ノーツの位置は画面の中央に偏る(隅は少ない)ので、譜面全体のノーツ位置の分布を一様に近づけて、
## 画面の隅・縁にも発生源が来るようにする。x と y を別々に、累積分布で一様な位置へ写し、元の位置と REMAP_ALPHA の割合で混ぜる。
static func _make_remap(bm: Beatmap) -> Dictionary:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for o in bm.hit_objects:
		xs.append(o.pos.x)
		ys.append(o.pos.y)
	xs.sort()
	ys.sort()
	return {"xs": xs, "ys": ys}


static func to_source(p_osu: Vector2, rm: Dictionary) -> Vector2:
	var orig := to_arena(p_osu)
	if rm.xs.size() < 8:
		return orig
	var eq := Vector2(lerpf(SRC_MARGIN.x, ARENA.x - SRC_MARGIN.x, _edge_push(_cdf(rm.xs, p_osu.x))), lerpf(SRC_MARGIN.y, ARENA.y - SRC_MARGIN.y, _edge_push(_cdf(rm.ys, p_osu.y))))
	return orig.lerp(eq, REMAP_ALPHA)


## 0..1 の位置を、端へ寄せる(REMAP_EDGE < 1)。中央から撃つ弾は画面の中央を何度も通るので、発生源を一様にしても、弾の通過は中央に偏る。端の発生源を多くして、通過の密度をならす。
static func _edge_push(u: float) -> float:
	var d := 2.0 * u - 1.0
	return 0.5 + 0.5 * signf(d) * pow(absf(d), REMAP_EDGE)


static func _cdf(sorted: PackedFloat32Array, v: float) -> float:
	return 0.5 * float(sorted.bsearch(v, true) + sorted.bsearch(v, false)) / float(sorted.size())


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


## 壁: 画面の端から、隙間を 1 つ空けた弾の列が、画面を横切る(縦または横。端はめぐり順)。隙間は nxt(譜面の流れ)の位置に置き、前の隙間(prev_gap)からは離す。
## 戻り値は、この壁の隙間の位置(次の壁が離れるため)。予兆: 端に、隙間つきの線(ギズモ)と、隙間の位置の輪。
static func _wall(t: float, n: int, nxt: Vector2, prev_gap: float, ci: int, c: Dictionary, events: Array, gizmos: Array) -> float:
	var edge := n % 4   # 0: 左から  1: 上から  2: 右から  3: 下から
	var horizontal := (edge % 2 == 0)   # 左右から来る壁は、縦に並んだ弾の列
	var along := nxt.y if horizontal else nxt.x
	var lo := 120.0
	var hi := (ARENA.y if horizontal else ARENA.x) - 120.0
	if absf(along - prev_gap) < WALL_GAP_SEPARATION:   # 同じ場所なら、反対側へ
		along = along + (WALL_GAP_SEPARATION if along < (lo + hi) * 0.5 else -WALL_GAP_SEPARATION)
	along = clampf(along, lo, hi)
	var spd: float = c.speed * WALL_SPEED
	var dir: Vector2 = [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)][edge]
	var list: Array = []
	var length := ARENA.y if horizontal else ARENA.x
	var p := 0.0
	while p <= length:
		if absf(p - along) > WALL_GAP_W * 0.5:
			var sp: Vector2
			match edge:
				0: sp = Vector2(-4.0, p)
				1: sp = Vector2(p, -4.0)
				2: sp = Vector2(ARENA.x + 4.0, p)
				_: sp = Vector2(p, ARENA.y + 4.0)
			list.append([sp, dir * spd])
		p += WALL_SPACING
	var mark: Vector2
	match edge:
		0: mark = Vector2(30.0, along)
		1: mark = Vector2(along, 30.0)
		2: mark = Vector2(ARENA.x - 30.0, along)
		_: mark = Vector2(along, ARENA.y - 30.0)
	events.append(_ev(t, mark, true, [_list_shot(list, spd, ci, c, 0.9)], "boom"))
	gizmos.append({"kind": "wall", "t": t, "end": t, "edge": edge, "gap": along, "gap_w": WALL_GAP_W, "color": ci})
	return along


## 収束リング: center を中心に、半径 DOOR_R の円周から中へ向かう弾の輪。隙間(DOOR_GAP_ANG の幅)を nxt の向きに空ける
## (中にいる人は、隙間から外へ出る。画面の外へはみ出した弾は、すぐ消える)。
static func _door_ring(t: float, center: Vector2, nxt: Vector2, ci: int, c: Dictionary, events: Array) -> void:
	var spd: float = c.speed * DOOR_SPEED
	var toward := (nxt - center).angle() if nxt.distance_to(center) > 30.0 else fposmod(center.x * 0.013, TAU)
	var n := int(round(TAU * DOOR_R / DOOR_SPACING))
	var list: Array = []
	for i in range(n):
		var a := TAU * float(i) / float(n)
		if absf(wrapf(a - toward, -PI, PI)) < DOOR_GAP_ANG * 0.5:
			continue
		var sp := center + Vector2.from_angle(a) * DOOR_R
		if not BOUNDS.has_point(sp):
			continue
		list.append([sp, -Vector2.from_angle(a) * spd])
	if list.is_empty():
		return
	events.append(_ev(t, center, true, [_list_shot(list, spd, ci, c, 0.9)], "boom"))


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
	var pts := PackedVector2Array()
	for p in curve.points:
		pts.append(to_source(p, c.rm))
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
			if s.has("list"):   # 壁・収束リング: 位置と速度が決まっている(画面の外で始まる弾は、入ってから数える)
				for b in s.list:
					var bv: Vector2 = b[1]
					var life2 := _exit_time(b[0], bv.normalized(), bv.length())
					var i1b := mini(int((e.t + life2) / SAMPLE_DT) + 1, cells - 1)
					diff[i0] += 1
					diff[i1b] -= 1
				continue
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
