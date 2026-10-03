extends RefCounted
## 弾幕 v2(MOD「弾幕 v2」)。譜面を解析(chart_profile.gd)して、区間ごとに「型(モチーフ)」を選び、その譜面自身の動き
## (ノーツ間の向き・距離・リズム・スライダーの形)から、弾の配置と向きを決める。決定的(乱数を使わない)。
##
## v1(pattern_gen.gd)との違い:
##   - 発生源を画面全体へ均さない(ほぼノーツの位置のまま。端への補正は弱め)。譜面の空間的な特徴が残る
##   - リングの向き・扇の向き・渦の回転が、ノーツの向き・向きの変化に結びつく(v1 は idx × π/4 の固定の刻み)
##   - 弾に挙動がある(加減速・停止→再発進・分裂。bullet_field.gd の BEH_*)
##
## 弾の数は、v1 と同じく PatternGen.generate が mul を自動調整して、Lv が譜面の★に合うようにする(generate の gen_fn)。
## モチーフごとの本数は、v1 のリングの本数 N(= ring_n。局所ノーツ密度に比例)に係数を掛けたもの。
##
## イベント・shot の形は v1 と同じ。任意のキーを足している: shot.off = 発射位置のずれ / shot.beh = 弾の挙動 {k, a, b, c}

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const ChartProfile = preload("res://scripts/game/chart_profile.gd")
const ZoneGenV2 = preload("res://scripts/game/zone_gen_v2.gd")

const M_RING := 0       # v1 に近いリング(向きだけ、ノーツの動きに合わせる)
const M_SPIRAL := 1     # 連打: 区間の重心から回る渦
const M_CROSSFIRE := 2  # ジャンプ: 次のノーツへ向かう扇(加速弾)
const M_CURTAIN := 3    # スライダー: 軌道に垂直に出る幕
const M_BLOOM := 4      # 疎・フィニッシュ: 止まって再発進する輪 / 分裂する大きな弾
const M_WALL := 5       # 往復する動き: 隙間が次のノーツの位置に来る、弾の列
const MOTIF_N := 6
const MOTIF_NAMES := ["ring", "spiral", "crossfire", "curtain", "bloom", "wall"]

const ARENA := PatternGen.ARENA
const V2_SIZE_MUL := 0.95        # 基準の弾サイズ(v1 の同じ★のときの大きさ)に掛ける倍率。小さいぶん、同じ Lv になるよう弾数が自動で増える
const V2_REMAP := 0.35          # 発生源を、全面に均した位置へ寄せる割合(v1 は 1.0)
const SIGNATURE_BONUS := 0.2    # 譜面の看板のモチーフに足す点
const REPEAT_PENALTY := 0.35    # 直前の区間と同じモチーフから引く点
const NOISE := 0.12             # 同点の崩し(決定的な疑似乱数)

# モチーフごとの本数の係数(N に掛ける)
const SPIRAL_ARMS := 0.45
const CROSS_FAN := 0.5
const CURTAIN_SIDE := 0.25
const BLOOM_RING := 0.8
const WALL_SPACING := 18.0      # 列の弾の間隔(px)。弾の当たり判定より小さくして、隙間なく並べる
const WALL_HALF := 320.0        # 列の幅の半分(隙間の中心から。盤面の外へははみ出さない)
const WALL_SPEED := 0.75        # 列の弾速(基準の弾速に対する倍率)

# 弾サイズの 3 段階(基準の弾サイズに対する倍率。連続的には変えない)。小 = 下地(連打の渦・幕・連射・スピナー)/ 普通 / 大 = 山場(フィニッシュ・分裂の親・スピナーの終わり)
# 弾ごとの大きさは Lv に入る(PatternGen.measure の size_ref)。小さい弾は、見えなくならない下限(MIN_SIZE。BULLET_SIZE_MUL をかける前)で止める
const SIZE_SMALL := 0.65
const SIZE_LARGE := 2.2
const MIN_SIZE := 4.0


## 弾幕を作る(PatternGen.generate と同じ結果の形。★に合わせた弾数の調整・Lv の計算つき)。
## 結果に "style" = "v2" と、"v2" = {signature, sections: [{t0, t1, motif}]}(調整・テスト用)を足す。
static func generate(bm: Beatmap, opts := {}) -> Dictionary:
	var prof := ChartProfile.analyze(bm)
	var asg := assign_motifs(bm, prof)
	var o := opts.duplicate()
	o["gen_fn"] = _generate.bind(prof, asg)
	o["style"] = "v2"
	o["size_mul"] = float(opts.get("size_mul", 1.0)) * V2_SIZE_MUL
	o["size_weight"] = true   # 弾ごとの大きさ(3 段階)を Lv に入れる
	var out := PatternGen.generate(bm, o)
	var secs: Array = []
	for j in range(prof.sections.size()):
		secs.append({"t0": prof.sections[j].t0, "t1": prof.sections[j].t1, "motif": asg.motifs[j]})
	out["v2"] = {"signature": asg.signature, "sections": secs, "spins": out.get("spins", [])}
	# 特殊エリア(v1 の 3×3 のマスの危険エリアに代わる。弾幕とは別で、難易度の測定には入れない)
	var names: Array = []
	for m in asg.motifs:
		names.append(MOTIF_NAMES[m])
	var kk := clampf((float(out.stars) - PatternGen.STAR_MIN) / (PatternGen.STAR_MAX - PatternGen.STAR_MIN), 0.0, 1.0)
	out["zones"] = ZoneGenV2.make(bm, prof, names, kk, out.breaks)
	return out


## 区間ごとのモチーフの割り当て。{motifs: [区間ごとの M_*], signature: 看板の M_*}
static func assign_motifs(bm: Beatmap, prof: Dictionary) -> Dictionary:
	var secs: Array = prof.sections
	var seed := (bm.md5.hash() + bm.hit_objects.size() * 2654435) & 0x7fffffff
	# 看板: 区間のノーツ数で重みをつけた親和度の合計が最大のモチーフ(リング以外)
	var total: Array = []
	total.resize(MOTIF_N)
	total.fill(0.0)
	for s in secs:
		if s.n == 0:
			continue
		var a := _affinity(s)
		for m in range(MOTIF_N):
			total[m] += a[m] * float(s.n)
	var signature := M_SPIRAL
	var best := -INF
	for m in range(1, MOTIF_N):
		if total[m] > best + 0.000001:
			best = total[m]
			signature = m
	var motifs: Array = []
	var prev := -1
	for j in range(secs.size()):
		var s: Dictionary = secs[j]
		if s.n == 0:
			motifs.append(prev if prev >= 0 else M_RING)
			continue
		var a := _affinity(s)
		a[signature] += SIGNATURE_BONUS
		if prev >= 0:
			a[prev] -= REPEAT_PENALTY
		var pick := M_RING
		var pv := -INF
		for m in range(MOTIF_N):
			var v: float = a[m] + _noise(seed, j, m) * NOISE * 2.0
			if v > pv:
				pv = v
				pick = m
		motifs.append(pick)
		prev = pick
	return {"motifs": motifs, "signature": signature}


## 区間(または譜面全体)の特徴 → モチーフごとの親和度。
static func _affinity(f: Dictionary) -> Array:
	var sh: Array = f.share
	var alt: float = f.alt
	var a: Array = []
	a.resize(MOTIF_N)
	a[M_RING] = 0.30 + 0.45 * sh[ChartProfile.CLS_STEP]
	a[M_SPIRAL] = 2.0 * sh[ChartProfile.CLS_STREAM]
	a[M_CROSSFIRE] = 1.8 * sh[ChartProfile.CLS_JUMP] + clampf(float(f.mean_dist) / 400.0, 0.0, 0.4)
	a[M_CURTAIN] = 2.2 * sh[ChartProfile.CLS_SLIDER]
	a[M_BLOOM] = 1.4 * sh[ChartProfile.CLS_SPARSE] + 1.0 * float(f.finish) + 0.5 * float(f.kiai) + 0.2 * sh[ChartProfile.CLS_STEP]
	a[M_WALL] = 1.6 * alt * (0.5 + minf(float(f.mean_dist) / 200.0, 1.0))
	return a


static func _noise(seed: int, j: int, m: int) -> float:
	var x := PatternGen._lcg(seed + j * 7919 + m * 104729)
	x = PatternGen._lcg(x)
	return float((x >> 8) % 1000) / 1000.0 - 0.5   # -0.5..0.5


# --- 発生源・向き ---

## ノーツ(osu 座標)→ 発射位置(アリーナ座標)。ほぼノーツの位置のまま、端への補正を弱くかける。
static func _src(p_osu: Vector2, rm: Dictionary) -> Vector2:
	var orig := PatternGen.to_arena(p_osu)
	if rm.n >= 8:
		var eq := Vector2(lerpf(PatternGen.SRC_MARGIN.x, ARENA.x - PatternGen.SRC_MARGIN.x, PatternGen._edge_push(PatternGen._cdf(rm.tx, -64.0, 576.0, p_osu.x))),
				lerpf(PatternGen.SRC_MARGIN.y, ARENA.y - PatternGen.SRC_MARGIN.y, PatternGen._edge_push(PatternGen._cdf(rm.ty, -48.0, 432.0, p_osu.y))))
		orig = orig.lerp(eq, V2_REMAP)
	return Vector2(clampf(orig.x, PatternGen.SRC_MARGIN.x, ARENA.x - PatternGen.SRC_MARGIN.x),
			clampf(orig.y, PatternGen.SRC_MARGIN.y, ARENA.y - PatternGen.SRC_MARGIN.y))


## このノーツへ入ってくる向き(前のノーツ → このノーツ)。なければ、次のノーツへの向き、それもなければ 0。
static func _flow_in(objs: Array, idx: int) -> float:
	var d: float = objs[idx].dir
	if not is_nan(d):
		return d
	if idx + 1 < objs.size() and not is_nan(objs[idx + 1].dir):
		return objs[idx + 1].dir
	return 0.0


## このノーツから、次のノーツへ向かう向き(発射位置の補正後の座標で)。なければ、入ってくる向き。
static func _flow_out(objs: Array, idx: int, rm: Dictionary) -> float:
	if idx + 1 < objs.size():
		var a := _src(objs[idx].epos, rm)
		var b := _src(objs[idx + 1].pos, rm)
		if a.distance_to(b) > 8.0:
			return (b - a).angle()
	return _flow_in(objs, idx)


# --- shot の組み立て ---

static func _s(c: Dictionary, n: int, speed: float, a0: float, ci: int, spread := TAU, fan := false, aim := false,
		size_mul := 1.0, beh := {}, off = null) -> Dictionary:
	var sh := PatternGen._shot(n, speed, a0, ci, c, spread, fan, aim, 0.0, size_mul)
	if size_mul < 1.0:
		sh["size"] = maxf(float(sh.size), minf(MIN_SIZE, float(c.size) * 0.9))   # 基準の弾サイズが小さい譜面でも、小さい弾が普通の弾より大きくならない
	if not beh.is_empty():
		sh["beh"] = beh
	if off != null:
		sh["off"] = off
	return sh


static func _accel(a: float, vt: float) -> Dictionary:
	return {"k": BulletField.BEH_ACCEL, "a": a, "b": vt, "c": 0.0}


static func _stopgo(stop_t: float, wait: float, rot: float) -> Dictionary:
	return {"k": BulletField.BEH_STOPGO, "a": stop_t, "b": wait, "c": rot}


static func _split(split_t: float, n: int, speed_mul: float) -> Dictionary:
	return {"k": BulletField.BEH_SPLIT, "a": split_t, "b": float(n), "c": speed_mul}


# --- 生成 ---

static func _generate(bm: Beatmap, k: float, mul: float, speed: float, size: float, prof: Dictionary, asg: Dictionary) -> Dictionary:
	var base := {
		"k": k,
		"speed": speed,
		"size": size,
		"variants": k >= 0.3,
		"combo_aim": k >= 0.4,
		"aim_trail": k >= 0.5,
		"trail_div": lerpf(0.4, 4.0, k * k),
		"light_gap": lerpf(0.4, 0.13, k),
		"half_gap": lerpf(0.6, 0.2, k),
		"warn_lead": lerpf(0.95, 0.5, k),
	}
	base["rm"] = PatternGen._make_remap(bm)
	var objs: Array = prof.objs
	var secs: Array = prof.sections
	var events: Array = []
	var gizmos: Array = []
	var times: Array = []
	for f in objs:
		times.append(f.t)
	var rate_ref := 0.0   # 譜面全体の、局所ノーツ密度の平均(個/秒)
	for i in range(times.size()):
		rate_ref += PatternGen._local_rate(times, i)
	rate_ref /= maxf(float(times.size()), 1.0)
	var st := {"phase": 0.0, "wall_t": -10.0, "wall_n": 0, "prev_primary": -10.0, "last_spin": -1, "spins": [],
			"seed": (bm.md5.hash() + bm.hit_objects.size() * 2654435) & 0x7fffffff}
	var sec_i := 0
	for idx in range(objs.size()):
		var f: Dictionary = objs[idx]
		var o: Dictionary = bm.hit_objects[idx]
		while sec_i < secs.size() - 1 and idx >= int(secs[sec_i].b):
			sec_i += 1
		var sec: Dictionary = secs[sec_i]
		var motif: int = asg.motifs[sec_i]
		var rate := PatternGen._local_rate(times, idx)
		if o.kind == Beatmap.KIND_SPINNER:   # スピナーは 1 個だけで周りにノーツがなく、局所密度が低く出る。譜面全体の標準の密度を下限にする(でないと、腕が 2 本になって簡単すぎる)
			rate = maxf(rate, rate_ref * SPIN_RATE_MUL)
		var c := base.duplicate()
		c["ring_n"] = clampi(int(round(2.0 * mul * (PatternGen.RING_A + PatternGen.RING_B * rate + PatternGen.RING_C * rate * rate))), 3, 44)
		c["arms"] = clampi(int(round(mul * (PatternGen.ARMS_A + PatternGen.ARMS_B * rate))), 1, 9)
		c["mul"] = mul
		var kiai := bm.kiai_at(o.time)
		var ci: int = (o.combo_index % 5) + (5 if kiai else 0)
		var gap: float = f.t - st.prev_primary
		var tier := 0
		if gap < c.light_gap:
			tier = 2
		elif gap < c.half_gap:
			tier = 1
		st.prev_primary = f.t
		match o.kind:
			Beatmap.KIND_CIRCLE:
				var h := _head(motif, o, f, objs, idx, sec, sec_i, c, st, tier, ci, true)
				events.append(PatternGen._ev(f.t, h.pos, true, h.shots, h.sfx))
			Beatmap.KIND_SLIDER:
				_slider(bm, o, f, objs, idx, sec, sec_i, motif, tier, ci, c, st, events, gizmos)
			Beatmap.KIND_SPINNER:
				_spinner(f, idx, ci, c, st, events, gizmos)
	events.sort_custom(func(a, b): return a.t < b.t)
	gizmos.sort_custom(func(a, b): return a.t < b.t)
	return {"events": events, "gizmos": gizmos, "warn_lead": base.warn_lead, "spins": st.spins}


## ノーツの発射(頭)。{pos, shots, sfx}。can_wall = false(スライダーの頭)のときは、壁は出さない(発射位置が軌道の始点でなくなるため)。
static func _head(motif: int, o: Dictionary, f: Dictionary, objs: Array, idx: int, sec: Dictionary, sec_i: int,
		c: Dictionary, st: Dictionary, tier: int, ci: int, can_wall: bool, pos_override = null) -> Dictionary:
	var rm: Dictionary = c.rm
	var s: float = c.speed
	var k: float = c.k
	var n: int = c.ring_n
	var pos: Vector2 = pos_override if pos_override != null else _src(f.pos, rm)
	var sfx := PatternGen._circle_sfx(o.hitsound, tier, c)
	var shots: Array = []
	var combo_aim := true
	match motif:
		M_SPIRAL:
			var arms := clampi(int(round(float(n) * SPIRAL_ARMS)), 2, 8)
			var step := clampf(float(sec.turn_mean) * 0.6, -0.55, 0.55)
			if absf(step) < 0.12:
				step = 0.2 * (1.0 if sec_i % 2 == 0 else -1.0)
			st.phase = fposmod(float(st.phase) + step, TAU)
			# 区間ごとに 3 通り(★が低いうちは、素直な渦だけ): 等速 / 加速(遅く出て速くなる)/ 減速(速く出て遅くなり、腕が束になる)
			var sp := s * 0.95
			var beh := {}
			if k >= 0.25:
				if sec_i % 3 == 1:
					sp = s * 0.6
					beh = _accel(s * 0.8, s * 1.35)
				elif sec_i % 3 == 2:
					sp = s * 1.3
					beh = _accel(-s * 0.9, s * 0.55)
			shots.append(_s(c, arms, sp, st.phase, ci, TAU, false, false, SIZE_SMALL, beh))
			if pos_override == null:
				pos = ((sec.center as Vector2) * PatternGen.SCALE).lerp(pos, 0.3).clamp(PatternGen.SRC_MARGIN, ARENA - PatternGen.SRC_MARGIN)
		M_CROSSFIRE:
			var dir := _flow_out(objs, idx, rm)
			var fan := clampi(int(round(float(n) * CROSS_FAN)), 3, 12)
			var spread := lerpf(0.9, 1.4, k)
			shots.append(_s(c, fan, s * 0.55, dir, ci, spread, true, false, 1.0, _accel(s * 0.95, s * 1.5)))
			if idx % 2 == 1:
				shots.append(_s(c, maxi(fan / 3, 2), s * 0.9, dir + PI, ci, 0.6, true))
		M_CURTAIN:
			var dir := _flow_in(objs, idx)
			var side := clampi(int(round(float(n) * CURTAIN_SIDE)), 2, 6)
			shots.append(_s(c, side, s * 0.9, dir + PI * 0.5, ci, 0.7, true))
			shots.append(_s(c, side, s * 0.9, dir - PI * 0.5, ci, 0.7, true))
		M_BLOOM:
			var a0 := fposmod(_flow_in(objs, idx) + float(idx) * 0.3, TAU)
			var finish: bool = (int(o.hitsound) & Beatmap.HS_FINISH) != 0
			if finish or (idx % 3 == 0 and bool(sec.kiai)):
				var pn := clampi(int(round(float(n) / 3.0)), 3, 10)
				shots.append(_s(c, pn, s * 0.6, a0, ci, TAU, false, false, SIZE_LARGE, _split(0.9, 4, 0.7)))
			else:
				var rn := clampi(int(round(float(n) * BLOOM_RING)), 4, 36)
				var sgn := 1.0 if idx % 2 == 0 else -1.0
				shots.append(_s(c, rn, s * 0.9, a0, ci, TAU, false, false, 1.0, _stopgo(0.8, lerpf(0.55, 0.35, k), sgn * 0.45)))
			sfx = "boom" if finish and c.variants else "pop"
		M_WALL:
			var w: Dictionary = _wall(f, objs, idx, c, st, ci) if (can_wall and pos_override == null) else {}
			if not w.is_empty():
				return {"pos": w.pos, "shots": w.shots, "sfx": "whistle"}
			# 壁を出さない間は、自機狙いの扇で支える
			if k >= 0.3:
				shots.append(_s(c, 3, s, 0.0, ci, 0.5, true, true))
			else:
				shots.append(_s(c, maxi(n / 3, 3), s, fposmod(_flow_in(objs, idx), TAU), ci))
			combo_aim = false
		_:
			var a0 := fposmod(_flow_in(objs, idx) + (PI / float(n) if idx % 2 == 1 else 0.0), TAU)
			shots = PatternGen._circle_shots(o.hitsound, o.new_combo, tier, a0, ci, c)
			combo_aim = false   # _circle_shots が、新しいコンボの自機狙いまで入れている
	# フィニッシュの音には、大きな遅い弾を 1 つ添える(山場。向きは次のノーツへ。BLOOM は分裂する大きな弾が、リングは v1 の二重のリングが、その役)
	if (motif == M_SPIRAL or motif == M_CROSSFIRE or motif == M_CURTAIN or motif == M_WALL) \
			and c.variants and (int(o.hitsound) & Beatmap.HS_FINISH) != 0:
		shots.append(_s(c, 1, s * 0.45, _flow_out(objs, idx, rm), ci, TAU, false, false, SIZE_LARGE))
	if combo_aim and o.new_combo and c.combo_aim:
		shots.append(_s(c, 1, s * 1.2, 0.0, ci, TAU, true, true))
	return {"pos": pos, "shots": shots, "sfx": sfx}


## 壁(隙間のある、弾の列)。隙間の位置は、次のノーツの位置。前の壁から間があいているときだけ出す(出さなければ空)。
## 3 回に 1 回は、横から来る(左右交互)。発射位置は隙間の位置(予告の輪が、通る場所に出る)。
static func _wall(f: Dictionary, objs: Array, idx: int, c: Dictionary, st: Dictionary, ci: int) -> Dictionary:
	var k: float = c.k
	var min_gap := lerpf(1.1, 0.55, k) / sqrt(clampf(float(c.mul), 0.4, 3.0))
	if f.t - float(st.wall_t) < min_gap:
		return {}
	st.wall_t = f.t
	var rm: Dictionary = c.rm
	var nxt: Dictionary = objs[mini(idx + 1, objs.size() - 1)]
	var gp := _src(nxt.pos, rm)
	var ws: float = float(c.speed) * WALL_SPEED
	var gap_w := lerpf(170.0, 110.0, k)
	var wn: int = st.wall_n
	st.wall_n = wn + 1
	var shots: Array = []
	var pos: Vector2
	if wn % 3 != 2:   # 上から下へ
		var gx := clampf(gp.x, gap_w * 0.5 + 24.0, ARENA.x - gap_w * 0.5 - 24.0)
		pos = Vector2(gx, 28.0)
		var x := maxf(gx - WALL_HALF, WALL_SPACING * 0.5)
		while x <= minf(gx + WALL_HALF, ARENA.x - WALL_SPACING * 0.5):
			if absf(x - gx) >= gap_w * 0.5:
				shots.append(_s(c, 1, ws, PI * 0.5, ci, TAU, false, false, 1.0, {}, Vector2(x - gx, 0.0)))
			x += WALL_SPACING
	else:   # 横から(左右交互)
		var from_left := (wn / 3) % 2 == 0
		var gy := clampf(gp.y, gap_w * 0.5 + 24.0, ARENA.y - gap_w * 0.5 - 24.0)
		pos = Vector2(28.0 if from_left else ARENA.x - 28.0, gy)
		var y := maxf(gy - WALL_HALF * 0.75, WALL_SPACING * 0.5)
		while y <= minf(gy + WALL_HALF * 0.75, ARENA.y - WALL_SPACING * 0.5):
			if absf(y - gy) >= gap_w * 0.5:
				shots.append(_s(c, 1, ws, 0.0 if from_left else PI, ci, TAU, false, false, 1.0, {}, Vector2(0.0, y - gy)))
			y += WALL_SPACING
	for sh in shots:
		sh["keep_n"] = true   # MOD の弾数の倍率で本数が変わると、列が崩れる(Mods.apply が飛ばす)
	return {"pos": pos, "shots": shots}


# --- スピナー ---
## v1 のスピナーは、中央から等速の渦を出すだけで、端にいればほぼ当たらなかった。v2 は、型を選ぶ(1〜3 秒ほどの短い間に収まる、1 つの型+終わりの山場):
##   LATTICE  … 回る向きが逆の 2 組の腕を重ねる。レーンが固定されず、菱形の隙間を縫う
##   CONVERGE … 中央からの渦と、縁から中央へ向かう弾(加速弾)を同時に出す。「端にいれば安全」が成り立たない
##   ORBIT    … 発射点が中央のまわりを回る。レーンの位置が時間とともにずれる(★が中程度以上、1.5 秒以上)
##   SWING    … 回転の速さと向きが途中で変わり、減速弾で弾が束になる(★が高い、1.5 秒以上)
## どの型も、★が中程度以上なら自機狙いを混ぜ、終わりに大きな弾の輪を出す(1 秒以上)。
const SP_LATTICE := 0
const SP_CONVERGE := 1
const SP_ORBIT := 2
const SP_SWING := 3
const SPIN_NAMES := ["lattice", "converge", "orbit", "swing"]
const SPIN_STEP := 0.42          # 1 回の発射ごとに回る角(rad)
const SPIN_RATE_MUL := 1.5       # スピナーの弾数の基準にする密度 = 譜面全体の平均の局所密度 × この値
const CONVERGE_RIM := Vector2(430.0, 320.0)   # 縁から出る弾の出る楕円の半径(盤面の内側。出た位置の近くに自機がいれば、猶予がつく)


static func _pick_spin(k: float, dur: float, seed: int, idx: int, last: int) -> int:
	var pool: Array = [SP_LATTICE, SP_CONVERGE]
	if dur >= 1.5:
		if k >= 0.45:
			pool.append(SP_ORBIT)
		if k >= 0.65:
			pool.append(SP_SWING)
	var x := PatternGen._lcg(PatternGen._lcg(seed + idx * 6151))
	var i := int((x >> 8) % pool.size())
	if pool[i] == last and pool.size() > 1:
		i = (i + 1) % pool.size()
	return pool[i]


static func _spinner(f: Dictionary, idx: int, ci: int, c: Dictionary, st: Dictionary, events: Array, gizmos: Array) -> void:
	var k: float = c.k
	var s: float = c.speed
	var center := PatternGen.to_arena(Vector2(256, 192))
	var t: float = f.t
	var end_t: float = f.end
	var dur := end_t - t
	gizmos.append({"kind": "spinner", "t": t, "end": end_t, "pos": center, "color": ci})
	events.append(PatternGen._ev(t, center, true, [], "pop"))
	var kind := _pick_spin(k, dur, int(st.seed), idx, int(st.last_spin))
	st.last_spin = kind
	st.spins.append({"t": t, "end": end_t, "kind": kind})   # 調整・テスト用: 選んだ型
	var arms := clampi(int(round(float(c.arms) * lerpf(1.0, 1.8, k))), 2, 9)   # ★が高いほど、腕が多い(★が低い譜面で、スピナーだけ濃くならないように)
	var each := clampi(int(round(float(c.arms) * lerpf(0.7, 1.3, k))), 2, 7)   # 2 組を重ねるときの、1 組あたりの腕
	var step := lerpf(0.18, 0.08, k)   # 短い間に盤面全体へ広げるので、★が高いと通常のノーツより細かく撃つ
	var sgn := 1.0 if ((int(st.seed) >> 4) + idx) % 2 == 0 else -1.0
	var split_d := lerpf(120.0, 260.0, k)   # LATTICE: 2 つの発射点の、中央からの左右の距離
	var orbit_r := lerpf(160.0, 280.0, k)
	var orbit_w := clampf(TAU * 0.75 / maxf(dur, 1.0), 1.5, 4.5) * sgn
	var swing_amp := SPIN_STEP / step * dur / PI   # SWING: 前へ進み、途中で折り返す回転の振れ幅(rad)
	var inward := clampi(int(round(1.0 + 5.0 * k)), 2, 6)   # CONVERGE: 縁から出る弾の数
	var tt := t + 0.3
	var n := 0
	while tt < end_t:
		var tau := tt - t
		var pos := center
		var a := SPIN_STEP * float(n) * sgn
		var shots: Array = []
		match kind:
			SP_LATTICE:   # 左右の 2 つの発射点から、逆向きに回る腕を出す(盤面の広い範囲で、腕が交差する)
				shots.append(_s(c, each, s * 0.85, a, ci, TAU, false, false, 1.0, {}, Vector2(-split_d, 0.0)))
				shots.append(_s(c, each, s * 0.85, -a + PI / float(each), ci, TAU, false, false, 1.0, {}, Vector2(split_d, 0.0)))
			SP_CONVERGE:
				shots.append(_s(c, arms, s * 0.85, a, ci, TAU, false, false, 1.0))
				var ph := float(n) * 0.37 * sgn
				for j in range(inward):
					var th := ph + TAU * float(j) / float(inward)
					var off := Vector2(cos(th) * CONVERGE_RIM.x, sin(th) * CONVERGE_RIM.y)
					var sh := _s(c, 1, s * 0.55, (-off).angle() + 0.3 * sgn, ci, TAU, false, false, 1.0, _accel(s * 0.7, s * 1.05), off)
					sh["keep_n"] = true   # 本数を変えると、反対向きの弾が出てしまう(Mods.apply が飛ばす)
					shots.append(sh)
			SP_ORBIT:
				var ang := orbit_w * tau + float(st.seed % 628) * 0.01
				pos = (center + Vector2.from_angle(ang) * orbit_r).clamp(PatternGen.SRC_MARGIN, ARENA - PatternGen.SRC_MARGIN)
				shots.append(_s(c, arms, s * 0.85, a, ci, TAU, false, false, 1.0))
			SP_SWING:
				var sw := swing_amp * sin(PI * tau / maxf(dur, 0.1)) * sgn
				if n % 2 == 0:
					shots.append(_s(c, arms, s * 1.3, sw, ci, TAU, false, false, 1.0, _accel(-s * 0.9, s * 0.55)))
				else:
					shots.append(_s(c, arms, s * 0.7, sw + PI / float(arms), ci, TAU, false, false, 1.0))
		if k >= 0.5 and n % 3 == 2:   # 端に居続けられないように、自機狙いを混ぜる
			shots.append(_s(c, 1, s * 1.1, 0.0, ci, TAU, true, true))
		events.append(PatternGen._ev(tt, pos, false, shots, "tick" if n % 3 == 0 else ""))
		n += 1
		tt += step
	# 終わりの山場: 大きな弾の輪(1 秒以上のスピナーだけ)
	if dur >= 1.0:
		var fn := clampi(int(round(float(c.ring_n) / 3.0)), 4, 10)
		events.append(PatternGen._ev(maxf(end_t - 0.05, t + 0.5), center, false,
				[_s(c, fn, s * 0.5, SPIN_STEP * float(n) * sgn, ci, TAU, false, false, SIZE_LARGE)], "boom" if c.variants else "pop"))


# --- スライダー ---

static func _tangent_at(pts: PackedVector2Array, frac: float, forward: bool) -> float:
	if pts.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var target := total * clampf(frac, 0.0, 1.0)
	var acc := 0.0
	var ang := (pts[1] - pts[0]).angle()
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if seg > 0.0:
			ang = (pts[i] - pts[i - 1]).angle()
		if acc + seg >= target and seg > 0.0:
			break
		acc += seg
	return ang if forward else ang + PI


static func _slider(bm: Beatmap, o: Dictionary, f: Dictionary, objs: Array, idx: int, sec: Dictionary, sec_i: int,
		motif: int, tier: int, ci: int, c: Dictionary, st: Dictionary, events: Array, gizmos: Array) -> void:
	var s: float = c.speed
	var k: float = c.k
	var rm: Dictionary = c.rm
	var t: float = f.t
	var curve = o.curve
	var span: float = o.span_duration / 1000.0
	var repeats: int = o.repeats
	var end_t: float = o.end_time / 1000.0
	# 軌道(アリーナ座標)。形はそのまま、頭の位置の補正ぶんだけ平行移動する(画面からはみ出さないように抑える)
	var pts := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in curve.points:
		var q := PatternGen.to_arena(p)
		pts.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	var off := _src(o.pos, rm) - PatternGen.to_arena(o.pos)
	var m_x := PatternGen.SRC_MARGIN.x
	var m_y := PatternGen.SRC_MARGIN.y
	off.x = clampf(off.x, m_x - lo.x, ARENA.x - m_x - hi.x) if hi.x - lo.x < ARENA.x - 2.0 * m_x else 0.0
	off.y = clampf(off.y, m_y - lo.y, ARENA.y - m_y - hi.y) if hi.y - lo.y < ARENA.y - 2.0 * m_y else 0.0
	for i in range(pts.size()):
		pts[i] += off
	var pos := pts[0]
	gizmos.append({"kind": "slider", "t": t, "end": end_t, "points": pts, "span": span, "repeats": repeats, "color": ci})
	# 頭
	var h := _head(motif, o, f, objs, idx, sec, sec_i, c, st, tier, ci, false, pos)
	events.append(PatternGen._ev(t, pos, true, h.shots, h.sfx))
	# 軌道上の連射
	var beat: float = bm.beat_length_at(o.time) / 1000.0
	var curtain := motif == M_CURTAIN
	var interval := maxf(beat / (lerpf(2.0, 4.0, k) if curtain else float(c.trail_div)), 0.12 if not curtain else 0.1)
	var side := clampi(int(round(float(c.arms) * 0.6)), 1, 4)
	# 幕が盤面の縁で 1 回跳ね返る(奇数番の区間とキアイ。★が低いうちは、素直な幕だけ)
	var bounce := {}
	if curtain and k >= 0.35 and (sec_i % 2 == 1 or bool(sec.kiai)):
		bounce = {"k": BulletField.BEH_BOUNCE, "a": 1.0, "b": 0.0, "c": 0.0}
	var m := 1
	var rot := fposmod(float(st.phase), TAU) if motif == M_SPIRAL else fposmod(_flow_in(objs, idx), TAU)
	while true:
		var tau_t := t + m * interval
		if tau_t >= end_t - 0.06:
			break
		var u := (tau_t - t) / span if span > 0.0 else 0.0
		var slide := int(floor(u))
		var frac := u - slide
		var forward := slide % 2 == 0
		if not forward:
			frac = 1.0 - frac
		var p := PatternGen._polyline_at(pts, frac)
		var shots: Array = []
		if curtain:
			var tg := _tangent_at(pts, frac, forward)
			shots.append(_s(c, side, s * 0.8, tg + PI * 0.5, ci, 0.3 if side > 1 else TAU, side > 1, false, SIZE_SMALL, bounce))
			shots.append(_s(c, side, s * 0.8, tg - PI * 0.5, ci, 0.3 if side > 1 else TAU, side > 1, false, SIZE_SMALL, bounce))
		else:
			shots.append(_s(c, c.arms, s * 0.8, rot, ci, TAU, false, false, SIZE_SMALL))
			rot += 0.5
		if c.aim_trail and m % 4 == 0:
			shots.append(_s(c, 1, s, 0.0, ci, TAU, true, true))
		events.append(PatternGen._ev(tau_t, p, false, shots, "tick"))
		m += 1
	# 折り返し点/終点(頭は上で発射済み)
	for j in range(1, repeats + 1):
		var edge_t := t + j * span
		var at_end := (j % 2 == 1)
		var ep := PatternGen._polyline_at(pts, 1.0 if at_end else 0.0)
		var eh: int = o.edge_sounds[j] if j < o.edge_sounds.size() else 0
		var n: int = c.ring_n
		var edge_shots: Array = []
		var sfx := "pop"
		if eh & Beatmap.HS_FINISH and c.variants:
			edge_shots.append(_s(c, n, s * 0.9, rot, ci))
			sfx = "boom"
		else:
			edge_shots.append(_s(c, maxi(n / 2, 3), s * 0.9, rot, ci))
		events.append(PatternGen._ev(edge_t, ep, false, edge_shots, sfx))
