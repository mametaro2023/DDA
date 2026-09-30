extends RefCounted
## osu!standard の星評価の近似(エイム/スピードのストレイン方式)。
## 公式値そのものではなく、譜面ごとの難易度の相対関係を再現するための推定。
## DDA の難易度そのものには使わず、「本家の星に近づける」ための基準(pattern_gen.gd)としてだけ使う。

const Beatmap = preload("res://scripts/osu/beatmap.gd")

const STRAIN_STEP := 400.0
const DECAY_WEIGHT := 0.9
const SPEED_DECAY := 0.3
const AIM_DECAY := 0.15
const SPEED_WEIGHT := 1400.0
const AIM_WEIGHT := 26.25
const SCALE := 0.0675
## 校正済みの最終補正: star = STAR_A * raw + STAR_B
## (サンプル譜面セット 320118 の公式値 14 件に最小二乗で合わせた。平均誤差 0.14★)
const STAR_A := 0.9354
const STAR_B := 0.5507


static func estimate(bm: Beatmap) -> float:
	var objs: Array = bm.hit_objects
	if objs.size() < 2:
		return 0.0
	var radius := 32.0 * (1.0 - 0.7 * (bm.cs - 5.0) / 5.0)
	var scaling := 52.0 / radius
	if radius < 30.0:
		scaling *= 1.0 + minf(30.0 - radius, 5.0) / 50.0

	var aim_peaks: Array = []
	var speed_peaks: Array = []
	var aim_strain := 0.0
	var speed_strain := 0.0
	var aim_peak := 0.0
	var speed_peak := 0.0
	var section_end: float = ceil(objs[0].time / STRAIN_STEP) * STRAIN_STEP
	var prev: Dictionary = objs[0]
	var prev_end := _end_pos(prev)

	for i in range(1, objs.size()):
		var cur: Dictionary = objs[i]
		var delta: float = maxf(cur.time - prev.time, 50.0)
		# セクション境界をまたいだらピークを確定
		while cur.time > section_end:
			aim_peaks.append(aim_peak)
			speed_peaks.append(speed_peak)
			var gap: float = (section_end - prev.time) / 1000.0
			aim_peak = aim_strain * pow(AIM_DECAY, gap)
			speed_peak = speed_strain * pow(SPEED_DECAY, gap)
			section_end += STRAIN_STEP
		var dist := 0.0
		if cur.kind != Beatmap.KIND_SPINNER and prev.kind != Beatmap.KIND_SPINNER:
			dist = prev_end.distance_to(cur.pos) * scaling
		var aim_v := 0.0
		var speed_v := 0.0
		if cur.kind != Beatmap.KIND_SPINNER:
			aim_v = pow(dist, 0.99) / delta * AIM_WEIGHT
			speed_v = _spacing_weight(dist) / delta * SPEED_WEIGHT
		var dt_s := delta / 1000.0
		aim_strain = aim_strain * pow(AIM_DECAY, dt_s) + aim_v
		speed_strain = speed_strain * pow(SPEED_DECAY, dt_s) + speed_v
		aim_peak = maxf(aim_peak, aim_strain)
		speed_peak = maxf(speed_peak, speed_strain)
		prev = cur
		prev_end = _end_pos(cur)
	aim_peaks.append(aim_peak)
	speed_peaks.append(speed_peak)

	var aim := sqrt(_weighted_sum(aim_peaks)) * SCALE
	var spd := sqrt(_weighted_sum(speed_peaks)) * SCALE
	var raw := aim + spd + absf(spd - aim) * 0.5
	return STAR_A * raw + STAR_B


static func _weighted_sum(peaks: Array) -> float:
	var sorted := peaks.duplicate()
	sorted.sort()
	sorted.reverse()
	var w := 1.0
	var sum := 0.0
	for p in sorted:
		sum += p * w
		w *= DECAY_WEIGHT
	return sum


static func _spacing_weight(d: float) -> float:
	if d > 125.0:
		return 2.5
	if d > 110.0:
		return 1.6 + 0.9 * (d - 110.0) / 15.0
	if d > 90.0:
		return 1.2 + 0.4 * (d - 90.0) / 20.0
	if d > 45.0:
		return 0.95 + 0.25 * (d - 45.0) / 45.0
	return 0.95


static func _end_pos(o: Dictionary) -> Vector2:
	if o.kind == Beatmap.KIND_SLIDER:
		return o.curve.pos_at(1.0 if o.repeats % 2 == 1 else 0.0)
	return o.pos
