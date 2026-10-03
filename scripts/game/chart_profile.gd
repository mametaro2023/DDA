extends RefCounted
## 譜面の解析(弾幕 v2 の素材)。決定的(乱数を使わない)。座標は osu 座標(512×384)のまま。
##
## analyze(bm) → {objs, sections, map}
##   objs[i]     … 各オブジェクトの特徴: {i, t, end, pos, epos, gap, beats, dist, dir, cls, kind}
##                 gap = 前のオブジェクトの終わりからの秒 / beats = それを拍で数えたもの / dist = 前の終点からの距離(px)
##                 dir = 前の終点 → このオブジェクトの向き(rad。最初のオブジェクトは NAN) / cls = CLS_*
##   sections[j] … 区間(小節をまとめたもの): 時刻の範囲 t0..t1、含むオブジェクトの番号 a..b(b は含まない)、特徴
##   map         … 譜面全体の特徴(指紋)

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

## オブジェクトの種類。STREAM = 速い連打 / JUMP = 大きく動く / SLIDER / SPINNER / SPARSE = 間隔が長い / STEP = ふつう
const CLS_STREAM := 0
const CLS_JUMP := 1
const CLS_SLIDER := 2
const CLS_SPINNER := 3
const CLS_SPARSE := 4
const CLS_STEP := 5
const CLS_N := 6
const CLS_NAMES := ["stream", "jump", "slider", "spinner", "sparse", "step"]

## 分類のしきい値
const STREAM_BEATS := 0.55    # 前から、この拍数以下の間隔で続くものは連打
const STREAM_JUMP_DIST := 200.0   # 連打でも、これ以上大きく動くものは、ジャンプ
const JUMP_DIST := 150.0      # これ以上動くものは、ジャンプ
const SPARSE_BEATS := 1.4     # 前から、この拍数以上あいたものは疎

## 区間の長さ: 2 秒以上になるまで小節を足す(最低 2 小節、最大 4 小節)。キアイの切り替わりでも切る
const MIN_SECTION := 2.0
const MIN_MEASURES := 2
const MAX_MEASURES := 4

## 往復と見なす向きの変化(rad)
const ALT_ANGLE := 2.4


static func analyze(bm: Beatmap) -> Dictionary:
	var objs := _objects(bm)
	var sections := _sections(bm, objs)
	for s in sections:
		_section_features(bm, objs, s)
	return {"objs": objs, "sections": sections, "map": _map_features(bm, objs, sections)}


static func _objects(bm: Beatmap) -> Array:
	var out: Array = []
	var prev_end := 0.0
	var prev_epos := Vector2(256, 192)
	for i in range(bm.hit_objects.size()):
		var o: Dictionary = bm.hit_objects[i]
		var t: float = o.time / 1000.0
		var end: float = o.end_time / 1000.0
		var pos: Vector2 = o.pos
		var epos := pos
		if o.kind == Beatmap.KIND_SLIDER:
			var pts: PackedVector2Array = o.curve.points
			if pts.size() > 0:
				epos = pts[pts.size() - 1] if int(o.repeats) % 2 == 1 else pts[0]
		var f := {"i": i, "t": t, "end": end, "pos": pos, "epos": epos, "kind": o.kind,
			"gap": 0.0, "beats": 99.0, "dist": 0.0, "dir": NAN, "cls": CLS_STEP}
		if i > 0:
			var gap := maxf(t - prev_end, 0.0)
			var beat: float = bm.beat_length_at(o.time) / 1000.0
			f.gap = gap
			f.beats = gap / maxf(beat, 0.05)
			var dv := pos - prev_epos
			f.dist = dv.length()
			if f.dist > 1.0:
				f.dir = dv.angle()
		f.cls = _classify(f)
		out.append(f)
		prev_end = end
		prev_epos = epos
	return out


static func _classify(f: Dictionary) -> int:
	match int(f.kind):
		Beatmap.KIND_SLIDER:
			return CLS_SLIDER
		Beatmap.KIND_SPINNER:
			return CLS_SPINNER
	if f.beats <= STREAM_BEATS:
		return CLS_JUMP if f.dist >= STREAM_JUMP_DIST else CLS_STREAM
	if f.dist >= JUMP_DIST:
		return CLS_JUMP
	if f.beats >= SPARSE_BEATS:
		return CLS_SPARSE
	return CLS_STEP


## 区間: 小節(PatternGen.measure_starts)を、2 秒以上・2〜4 小節にまとめる。最初のノーツから最後のノーツまで。
static func _sections(bm: Beatmap, objs: Array) -> Array:
	var out: Array = []
	if objs.is_empty():
		return out
	var t_first: float = objs[0].t
	var t_last: float = objs[objs.size() - 1].end
	var ms := PatternGen.measure_starts(bm)
	var i := 0
	while i < ms.size() and float(ms[i][0]) + float(ms[i][1]) <= t_first:
		i += 1
	var cur := t_first
	while i < ms.size() and cur <= t_last:
		var j := i
		var end: float = float(ms[i][0]) + float(ms[i][1])
		var cnt := 1
		var k0 := bm.kiai_at(int(float(ms[i][0]) * 1000.0))
		while cnt < MAX_MEASURES and j + 1 < ms.size():
			if end - cur >= MIN_SECTION and cnt >= MIN_MEASURES:
				break
			if bm.kiai_at(int(float(ms[j + 1][0]) * 1000.0)) != k0:
				break
			j += 1
			end = float(ms[j][0]) + float(ms[j][1])
			cnt += 1
		out.append({"t0": cur, "t1": end})
		cur = end
		i = j + 1
	if out.is_empty() or cur <= t_last:
		out.append({"t0": cur, "t1": t_last + 0.001})
	else:
		out[out.size() - 1].t1 = maxf(float(out[out.size() - 1].t1), t_last + 0.001)
	# 区間に入るオブジェクトの範囲 a..b
	var a := 0
	for s in out:
		while a < objs.size() and objs[a].t < s.t0 - 0.0005:
			a += 1
		var b := a
		while b < objs.size() and objs[b].t < s.t1 - 0.0005:
			b += 1
		s["a"] = a
		s["b"] = b
		a = b
	return out


static func _angle_diff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)


static func _section_features(bm: Beatmap, objs: Array, s: Dictionary) -> void:
	var n: int = s.b - s.a
	var share: Array = []
	share.resize(CLS_N)
	share.fill(0.0)
	var sum_dist := 0.0
	var dist_n := 0
	var c := Vector2.ZERO
	var finish := 0
	var dirs: Array = []
	var slider_len := 0.0
	var sliders := 0
	for k in range(s.a, s.b):
		var f: Dictionary = objs[k]
		share[f.cls] += 1.0
		c += f.pos
		if k > 0 and f.dist > 1.0:
			sum_dist += f.dist
			dist_n += 1
		if not is_nan(f.dir):
			dirs.append(f.dir)
		var o: Dictionary = bm.hit_objects[k]
		if int(o.hitsound) & Beatmap.HS_FINISH:
			finish += 1
		if f.kind == Beatmap.KIND_SLIDER:
			slider_len += float(o.curve.total)
			sliders += 1
	var nn := maxf(float(n), 1.0)
	for j in range(CLS_N):
		share[j] /= nn
	var center := c / nn if n > 0 else Vector2(256, 192)
	var spread := 0.0
	for k in range(s.a, s.b):
		spread += (objs[k].pos as Vector2).distance_squared_to(center)
	spread = sqrt(spread / nn)
	# 向きの揃い具合(合成ベクトルの長さ 0..1)・向きの回転(1 ノーツあたりの平均、符号つき)・往復の割合
	var rx := 0.0
	var ry := 0.0
	for d in dirs:
		rx += cos(d)
		ry += sin(d)
	var coherence := Vector2(rx, ry).length() / maxf(float(dirs.size()), 1.0)
	var turn_sum := 0.0
	var alt := 0
	for k in range(1, dirs.size()):
		var dd := _angle_diff(dirs[k - 1], dirs[k])
		turn_sum += dd
		if absf(dd) > ALT_ANGLE:
			alt += 1
	var pairs := maxf(float(dirs.size() - 1), 1.0)
	s["n"] = n
	s["rate"] = float(n) / maxf(float(s.t1) - float(s.t0), 0.5)
	s["share"] = share
	s["mean_dist"] = sum_dist / maxf(float(dist_n), 1.0)
	s["center"] = center
	s["spread"] = spread
	s["coherence"] = coherence
	s["turn_mean"] = turn_sum / pairs
	s["alt"] = float(alt) / pairs
	s["finish"] = float(finish) / nn
	s["slider_len"] = slider_len / maxf(float(sliders), 1.0)
	s["kiai"] = bm.kiai_at(int(float(s.t0) * 1000.0))


static func _map_features(bm: Beatmap, objs: Array, sections: Array) -> Dictionary:
	var n := objs.size()
	var share: Array = []
	share.resize(CLS_N)
	share.fill(0.0)
	var sum_dist := 0.0
	var finish := 0
	var kiai := 0
	var c := Vector2.ZERO
	var curv := 0.0
	var sliders := 0
	for f in objs:
		share[f.cls] += 1.0
		sum_dist += f.dist
		c += f.pos
		var o: Dictionary = bm.hit_objects[f.i]
		if int(o.hitsound) & Beatmap.HS_FINISH:
			finish += 1
		if bm.kiai_at(int(o.time)):
			kiai += 1
		if f.kind == Beatmap.KIND_SLIDER:
			curv += _curviness(o.curve.points)
			sliders += 1
	var nn := maxf(float(n), 1.0)
	for j in range(CLS_N):
		share[j] /= nn
	var center := c / nn if n > 0 else Vector2(256, 192)
	var spread := 0.0
	for f in objs:
		spread += (f.pos as Vector2).distance_squared_to(center)
	spread = sqrt(spread / nn)
	var alt := 0.0
	var alt_w := 0.0
	for s in sections:
		alt += float(s.alt) * float(s.n)
		alt_w += float(s.n)
	return {
		"n": n,
		"sections": sections.size(),
		"share": share,
		"mean_dist": sum_dist / nn,
		"center": center,
		"spread": spread,
		"alt": alt / maxf(alt_w, 1.0),
		"finish": float(finish) / nn,
		"kiai": float(kiai) / nn,
		"curviness": curv / maxf(float(sliders), 1.0),
	}


## スライダーの曲がり具合: 折れ線の向きの変化の合計(rad)÷ 長さ(100 px あたり)。
static func _curviness(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 0.0
	var total := 0.0
	var len := 0.0
	var prev := (pts[1] - pts[0]).angle()
	len += pts[0].distance_to(pts[1])
	for i in range(2, pts.size()):
		var a := (pts[i] - pts[i - 1]).angle()
		total += absf(_angle_diff(prev, a))
		len += pts[i].distance_to(pts[i - 1])
		prev = a
	return total / maxf(len / 100.0, 0.5)
