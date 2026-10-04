extends RefCounted
## 特殊エリアの予定(MOD「弾幕 v2」)。決定的(乱数を使わない。同じ譜面なら同じ)。弾幕 v1 の「小節ごとに 3×3 のマスから選ぶ」(PatternGen._make_zones)とは別物。
##
## 考え方: エリアは「いまの弾幕のうち、どこに立つか」を、フレーズごとに問い直すもの。
##   フレーズ … 譜面の区間(chart_profile.gd の sections)を、約 PERIOD_EASY〜PERIOD_HARD 秒(★が高いほど短い)になるまでまとめたもの。1 フレーズに特殊エリアを 1 つ(または 1 組)出す。
##              最初の弾の前には出さない。休憩地帯とも重ねない。予告は、発動の 2 小節前(★が高いと 1 小節前)から。次のフレーズの予告は、前のエリアが終わってから出る。
##   形     … 区間の型(弾幕 v2 のモチーフ)で選ぶ: 渦=中央の円 / ジャンプ=半面 / スライダー=流れる向きに動く帯 / 疎・フィニッシュ=角・円 / 往復=帯 / ふつう=角・半面・円。
##   系統   … 試練(自機が不利)/ 恩恵(自機が有利)/ 対(半面を 2 つに割って、片方が試練・片方が恩恵)。★が低いほど恩恵が多く、高いほど対・試練が多い。キアイは対が増え、疎な区間は恩恵(癒し)が増える。
##   種類   … モチーフごとに、試練・恩恵の種類が決まる(PREF)。鈍足・脆弱・毒・流れ・時の急流(試練)/ 癒し・精密・稼ぎ・時の淀み(恩恵)。
##              流れは ★ 度合い 0.15 以上、毒は 0.3 以上、時の急流は 0.4 以上、精密は 0.2 以上。流れの向きは、フレーズのノーツの流れる向き(45° 刻み)。
## 盤面の中央に居続けるのが有利にならないよう、形は中央の円・半面・帯・角(中央を通る帯もある)から選ぶ。安全な場所は常にある(試練のエリアは、動ける範囲の半分以下)。
##
## zones の要素: {t(発動), end(終わり), lead(予告の長さ), cells: [](v1 の形式との互換のために空), areas: [{shape, type}], fam: "trial"/"boon"/"pair", motif: 名前}

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const ChartProfile = preload("res://scripts/game/chart_profile.gd")
const ZoneArea = preload("res://scripts/game/zone_area.gd")

const PERIOD_EASY := 14.0    # 1 フレーズの長さ(秒)の目安。★が低いとき
const PERIOD_HARD := 8.0     # ★が高いとき
const LEAD_MIN := 1.4        # 予告の長さの下限(秒。小節が短いときは、小節を足して届かせる)
const LEAD_CAP := 0.5        # 予告の長さの上限(フレーズの長さに対する割合)
const POISON_K := 0.3        # 毒が出る★の度合い
const PRECISE_K := 0.2       # 精密が出る★の度合い
const FLOW_K := 0.15         # 流れが出る★の度合い
const HASTE_K := 0.4         # 時の急流が出る★の度合い

## モチーフごとの好み: trial / boon = 試練・恩恵の種類、shapes = 形(disc 中央の円 / half 半面 / corner 角 / band 帯 / sweep 流れる帯)
const PREF := {
	"ring": {"trial": "slow", "boon": "bonus", "shapes": ["corner", "half", "disc"]},
	"spiral": {"trial": "fragile", "boon": "warp", "shapes": ["disc", "half"]},
	"crossfire": {"trial": "haste", "boon": "precise", "shapes": ["half", "half"]},
	"curtain": {"trial": "flow", "boon": "bonus", "shapes": ["sweep"]},
	"bloom": {"trial": "poison", "boon": "heal", "shapes": ["corner", "disc"]},
	"wall": {"trial": "fragile", "boon": "precise", "shapes": ["band", "half"]},
}


## prof = ChartProfile.analyze(bm)、motifs = 区間ごとのモチーフの名前(prof.sections と同じ順)、k = ★の度合い 0..1、breaks = 休憩地帯 [[始まり, 終わり], ...](秒)。
static func make(bm: Beatmap, prof: Dictionary, motifs: Array, k: float, breaks: Array) -> Array:
	var secs: Array = prof.sections
	var objs: Array = prof.objs
	var ms := PatternGen.measure_starts(bm)
	if secs.size() < 2 or objs.is_empty() or ms.size() < 3 or motifs.size() != secs.size():
		return []
	var kk := clampf((k - 0.1) / 0.9, 0.0, 1.0)
	var period := lerpf(PERIOD_EASY, PERIOD_HARD, kk)
	var t_first: float = bm.first_time() / 1000.0
	var seed := (bm.md5.hash() + bm.hit_objects.size() * 2654435 + 977) & 0x7fffffff
	var brs: Array = breaks.duplicate()
	brs.sort_custom(func(a, b): return a[0] < b[0])
	# 1) フレーズ → 発動の時刻と予告
	var plan: Array = []
	for ph in _phrases(secs, period):
		var mi := _measure_index(ms, float(ph.t0))
		if mi < 1:
			continue
		var cap := period * LEAD_CAP
		var lead := float(ms[mi - 1][1])
		var n := 1
		var want := 2 if kk < 0.6 else 1
		while n < 3 and mi - n - 1 >= 0 and (n < want or lead < LEAD_MIN) and lead + float(ms[mi - n - 1][1]) <= cap:
			lead += float(ms[mi - n - 1][1])
			n += 1
		if float(ph.t0) - lead < t_first - 0.001:   # 最初の弾の発射前には、予告も出さない
			continue
		plan.append({"ph": ph, "t": float(ph.t0), "lead": lead, "mlen": float(ms[mi][1])})
	# 2) 終わり(次の予告が始まるまで。最後は、フレーズの終わりまで)・休憩との調整・形と種類
	var zones: Array = []
	var prev := {"sig": "", "trial": "", "boon": ""}
	for i in range(plan.size()):
		var pl: Dictionary = plan[i]
		var start: float = pl.t
		var end: float = float(pl.ph.t1)
		if i + 1 < plan.size():
			end = minf(maxf(start + float(pl.mlen), float(plan[i + 1].t) - float(plan[i + 1].lead)), float(plan[i + 1].t))
		var skip := false
		for b in brs:   # 休憩と重なるとき: 発動してから休憩に入るなら、休憩の始まりで終える。予告・発動の時点が休憩と重なるなら、置かない
			if float(b[1]) <= start - float(pl.lead) or float(b[0]) >= end:
				continue
			if float(b[0]) > start:
				end = minf(end, float(b[0]))
			else:
				skip = true
			break
		if skip or end - start < float(pl.mlen) - 0.001:
			continue
		var z := _make_zone(pl, start, end, secs, objs, motifs, kk, seed, i, prev)
		prev = {"sig": z.sig, "trial": z.tt, "boon": z.bt}
		for key in ["sig", "tt", "bt"]:
			z.erase(key)
		zones.append(z)
	return zones


## 区間を、period 秒以上になるまでまとめたフレーズ [{j0, j1(含まない), t0, t1}]。キアイの切り替わりでは、ある程度の長さがあれば区切る。
static func _phrases(secs: Array, period: float) -> Array:
	var out: Array = []
	var a := 0
	var t0: float = secs[0].t0
	for j in range(secs.size()):
		var t1: float = secs[j].t1
		var last := j == secs.size() - 1
		var kiai_cut: bool = (not last) and bool(secs[j + 1].kiai) != bool(secs[j].kiai) and t1 - t0 >= period * 0.5
		if last or t1 - t0 >= period or kiai_cut:
			if last and t1 - t0 < period * 0.5 and not out.is_empty():   # 最後の短い端は、前のフレーズに足す
				out[out.size() - 1].j1 = j + 1
				out[out.size() - 1].t1 = t1
			else:
				out.append({"j0": a, "j1": j + 1, "t0": t0, "t1": t1})
			if not last:
				a = j + 1
				t0 = secs[j + 1].t0
	return out


## 時刻 t(以下)で、いちばん遅く始まる小節の番号。
static func _measure_index(ms: Array, t: float) -> int:
	var idx := 0
	for i in range(ms.size()):
		if float(ms[i][0]) <= t + 0.002:
			idx = i
		else:
			break
	return idx


static func _rng(seed: int, i: int, salt: int) -> float:
	var x := PatternGen._lcg(seed + i * 7919 + salt * 104729)
	x = PatternGen._lcg(x)
	return float((x >> 8) % 1000) / 1000.0   # 0..0.999


static func _make_zone(pl: Dictionary, start: float, end: float, secs: Array, objs: Array, motifs: Array, kk: float, seed: int, i: int, prev: Dictionary) -> Dictionary:
	var ph: Dictionary = pl.ph
	# フレーズの性格: 主なモチーフ(ノーツ数で数える)・疎の割合・キアイ・ノーツの流れる向き
	var cnt := {}
	var n_all := 0.0
	var sparse := 0.0
	for j in range(int(ph.j0), int(ph.j1)):
		var n := float(secs[j].n)
		cnt[motifs[j]] = float(cnt.get(motifs[j], 0.0)) + n
		sparse += float((secs[j].share as Array)[ChartProfile.CLS_SPARSE]) * n
		n_all += n
	var motif := str(motifs[int(ph.j0)])
	var best := -1.0
	for m in PREF:   # 同数なら、PREF の並びの先のもの
		if float(cnt.get(m, 0.0)) > best:
			best = float(cnt.get(m, 0.0))
			motif = m
	var sparse_share := sparse / maxf(n_all, 1.0)
	var kiai: bool = bool(secs[int(ph.j0)].kiai)
	var flow := Vector2.ZERO
	var flow_n := 0
	for q in range(int(secs[int(ph.j0)].a), int(secs[int(ph.j1) - 1].b)):
		var d: float = objs[q].dir
		if not is_nan(d):
			flow += Vector2.from_angle(d)
			flow_n += 1
	# 流れのエリアの押す向き: ノーツの流れる向き(45° 刻み)。向きがばらばらなら、譜面から作った疑似乱数で決める
	var push := Vector2.from_angle(roundf((flow.angle() if flow.length() > 0.15 * float(flow_n) else TAU * _rng(seed, i, 8)) / (PI * 0.25)) * PI * 0.25)
	var pref: Dictionary = PREF[motif]
	# 系統: ★が低いほど恩恵、高いほど対・試練。疎な区間は恩恵、キアイは対が増える
	var w_boon := lerpf(0.55, 0.15, kk) + (0.3 if sparse_share >= 0.5 else 0.0) - (0.15 if kiai else 0.0)
	var w_pair := lerpf(0.10, 0.40, kk) + (0.25 if kiai else 0.0)
	var r_fam := _rng(seed, i, 1)
	var fam := "trial"
	if r_fam < w_boon:
		fam = "boon"
	elif r_fam < w_boon + w_pair:
		fam = "pair"
	# 種類: モチーフの好みを基本にする。単調にならないよう、直前のエリアと同じ種類は避け、ときどき別の種類にする(★で解禁される種類だけ)
	var trial_pool: Array = ["slow", "fragile"]
	if kk >= FLOW_K:
		trial_pool.append("flow")
	if kk >= POISON_K:
		trial_pool.append("poison")
	if kk >= HASTE_K:
		trial_pool.append("haste")
	var boon_pool: Array = ["bonus", "heal", "warp"]
	if kk >= PRECISE_K:
		boon_pool.append("precise")
	var trial: String = pref.trial
	if not trial_pool.has(trial):
		trial = "fragile" if trial == "poison" else "slow"
	if kiai and kk >= POISON_K and trial == "slow":
		trial = "poison"
	var boon: String = pref.boon
	if not boon_pool.has(boon):
		boon = "bonus"
	if sparse_share >= 0.5:
		boon = "heal"
	elif kiai and boon == "heal":
		boon = "bonus"
	trial = _vary(trial, trial_pool, str(prev.trial), _rng(seed, i, 4), _rng(seed, i, 5))
	if sparse_share < 0.5:   # 疎な区間の癒しは、動かさない(休める所の目印)
		boon = _vary(boon, boon_pool, str(prev.boon), _rng(seed, i, 6), _rng(seed, i, 7))
	# 形
	var shapes: Array = pref.shapes
	var r_shape := _rng(seed, i, 2)
	var shape_name: String = shapes[int(r_shape * shapes.size()) % shapes.size()]
	var r_pos := _rng(seed, i, 3)
	var areas: Array = []
	var sig := ""
	for attempt in range(2):
		areas.clear()
		if fam == "pair":
			var halves := _halves(r_pos, flow)
			areas.append(_area(halves[0], trial, push))
			areas.append(_area(halves[1], boon, push))
			sig = "pair/%d" % int(halves[2])
		else:
			areas.append(_area(_shape(shape_name, kk, r_pos, flow), trial if fam == "trial" else boon, push))
			sig = "%s/%s/%d" % [fam, shape_name, int(r_pos * 4.0)]
		if sig != str(prev.sig):
			break
		r_pos = fposmod(r_pos + 0.37, 1.0)   # 直前と同じ形・位置なら、位置を変えて作り直す
	return {"t": start, "end": end, "lead": float(pl.lead), "cells": [], "areas": areas, "fam": fam, "motif": motif, "sig": sig,
		"tt": trial if fam != "boon" else str(prev.trial), "bt": boon if fam != "trial" else str(prev.boon)}


## 種類を選ぶ。base(好み)を基本に、直前と同じなら、別の種類へ。そうでなくても、約 1/4 の確率で別の種類へ(r1)。別の種類は pool から r2 で選ぶ。
static func _vary(base: String, pool: Array, prev_type: String, r1: float, r2: float) -> String:
	if base != prev_type and r1 >= 0.25:
		return base
	var alts: Array = pool.filter(func(t): return t != base and t != prev_type)
	if alts.is_empty():
		alts = pool.filter(func(t): return t != prev_type)
	if alts.is_empty():
		return base
	return alts[int(r2 * alts.size()) % alts.size()]


## エリア 1 つぶん。流れ(flow)は、押す向き dir を持つ。
static func _area(shape: Dictionary, type: String, push: Vector2) -> Dictionary:
	var a := {"shape": shape, "type": type}
	if type == "flow":
		a["dir"] = push
	return a


## 形を作る。r = 位置の選び方(0..1)、flow = ノーツの流れる向き(帯が流れる向き)。
static func _shape(kind: String, kk: float, r: float, flow: Vector2) -> Dictionary:
	var side := int(r * 4.0) % 4
	match kind:
		"disc":
			return ZoneArea.disc(0.5, 0.5, lerpf(0.22, 0.34, kk))
		"half":
			var w := lerpf(0.42, 0.5, kk)
			match side:
				0:
					return ZoneArea.rect(0.0, 0.0, w, 1.0)
				1:
					return ZoneArea.rect(1.0 - w, 0.0, 1.0, 1.0)
				2:
					return ZoneArea.rect(0.0, 0.0, 1.0, w)
			return ZoneArea.rect(0.0, 1.0 - w, 1.0, 1.0)
		"corner":
			var s := lerpf(0.34, 0.5, kk)
			var x0 := 0.0 if side % 2 == 0 else 1.0 - s
			var y0 := 0.0 if side < 2 else 1.0 - s
			return ZoneArea.rect(x0, y0, x0 + s, y0 + s)
		"band":
			var bw := lerpf(0.26, 0.34, kk)
			var pos: float = [0.0, (1.0 - bw) * 0.5, 1.0 - bw][int(r * 7.0) % 3]   # 端・中央・反対の端
			if side % 2 == 0:
				return ZoneArea.rect(0.0, pos, 1.0, pos + bw)
			return ZoneArea.rect(pos, 0.0, pos + bw, 1.0)
	# sweep: 流れる向きへ、帯が盤面を横切る(発動から終わりまでで、端から端へ)
	var wd := lerpf(0.26, 0.34, kk)
	var span := 1.0 - wd
	if absf(flow.x) >= absf(flow.y):
		if flow.x >= 0.0:
			return ZoneArea.rect(0.0, 0.0, wd, 1.0, Vector2(span, 0.0))
		return ZoneArea.rect(1.0 - wd, 0.0, 1.0, 1.0, Vector2(-span, 0.0))
	if flow.y >= 0.0:
		return ZoneArea.rect(0.0, 0.0, 1.0, wd, Vector2(0.0, span))
	return ZoneArea.rect(0.0, 1.0 - wd, 1.0, 1.0, Vector2(0.0, -span))


## 盤面を半分に割った 2 つの半面 [試練の側, 恩恵の側, 向きの番号]。ノーツが流れる向きに沿って、割る向きを選ぶ。
static func _halves(r: float, flow: Vector2) -> Array:
	var horiz := absf(flow.x) >= absf(flow.y)   # 横に流れるなら、左右に割る(渡るのが動き)
	var first := int(r * 2.0) % 2
	var a: Dictionary
	var b: Dictionary
	if horiz:
		a = ZoneArea.rect(0.0, 0.0, 0.5, 1.0)
		b = ZoneArea.rect(0.5, 0.0, 1.0, 1.0)
	else:
		a = ZoneArea.rect(0.0, 0.0, 1.0, 0.5)
		b = ZoneArea.rect(0.0, 0.5, 1.0, 1.0)
	if first == 0:
		return [a, b, (0 if horiz else 2)]
	return [b, a, (1 if horiz else 3)]
