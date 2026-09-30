extends RefCounted
## スライダー軌道。L/P/B/C をポリライン化し、pixelLength に合わせて切り詰め/延長する。

var points := PackedVector2Array()
var cum := PackedFloat32Array()
var total := 0.0


func setup(type: String, ctrl: PackedVector2Array, pixel_length: float) -> void:
	var poly := PackedVector2Array()
	match type:
		"L":
			poly = ctrl
		"P":
			if ctrl.size() == 3:
				poly = _arc(ctrl[0], ctrl[1], ctrl[2])
				if poly.is_empty():
					poly = ctrl
			else:
				poly = _bezier_chain(ctrl)
		"C":
			poly = _catmull(ctrl)
		_:
			poly = _bezier_chain(ctrl)
	_finalize(poly, pixel_length)


## d(px, 0..total) の位置。範囲外は端にクランプ。
func pos_at_distance(d: float) -> Vector2:
	if points.size() == 1:
		return points[0]
	d = clampf(d, 0.0, total)
	var lo := 0
	var hi := points.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	if seg <= 0.0001:
		return points[lo]
	return points[lo].lerp(points[hi], (d - cum[lo]) / seg)


## progress 0..1(1 スパン内)の位置。
func pos_at(progress: float) -> Vector2:
	return pos_at_distance(progress * total)


func _finalize(poly: PackedVector2Array, pixel_length: float) -> void:
	points = PackedVector2Array()
	cum = PackedFloat32Array()
	if poly.is_empty():
		points.append(Vector2.ZERO)
		cum.append(0.0)
		total = 0.0
		return
	points.append(poly[0])
	cum.append(0.0)
	var acc := 0.0
	for i in range(1, poly.size()):
		var seg := poly[i].distance_to(points[points.size() - 1])
		if seg < 0.0001:
			continue
		var remaining := pixel_length - acc
		if pixel_length > 0.0 and seg >= remaining:
			var dir := (poly[i] - points[points.size() - 1]).normalized()
			points.append(points[points.size() - 1] + dir * remaining)
			acc = pixel_length
			cum.append(acc)
			total = acc
			return
		acc += seg
		points.append(poly[i])
		cum.append(acc)
	# 軌道が pixelLength より短い → 最後の向きで延長
	if pixel_length > acc and points.size() >= 2:
		var dir2 := (points[points.size() - 1] - points[points.size() - 2]).normalized()
		points.append(points[points.size() - 1] + dir2 * (pixel_length - acc))
		acc = pixel_length
		cum.append(acc)
	total = acc


func _arc(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return PackedVector2Array()
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	var center := Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
	var r := a.distance_to(center)
	if r > 2000.0:
		return PackedVector2Array()
	var ta := (a - center).angle()
	var tb := (b - center).angle()
	var tc := (c - center).angle()
	var sweep_b := fposmod(tb - ta, TAU)
	var sweep_c := fposmod(tc - ta, TAU)
	var total_angle: float
	if sweep_b < sweep_c:
		total_angle = sweep_c
	else:
		total_angle = -fposmod(ta - tc, TAU)
	var arc_len := absf(total_angle) * r
	var n := maxi(int(ceil(arc_len / 4.0)), 8)
	var out := PackedVector2Array()
	for i in range(n + 1):
		var ang := ta + total_angle * float(i) / float(n)
		out.append(center + Vector2(cos(ang), sin(ang)) * r)
	return out


func _bezier_chain(ctrl: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var seg := PackedVector2Array()
	for i in range(ctrl.size()):
		seg.append(ctrl[i])
		var split := i < ctrl.size() - 1 and ctrl[i] == ctrl[i + 1]
		if split or i == ctrl.size() - 1:
			if seg.size() >= 2:
				out.append_array(_bezier(seg))
			seg = PackedVector2Array()
	if out.is_empty() and not ctrl.is_empty():
		out = ctrl
	return out


func _bezier(cp: PackedVector2Array) -> PackedVector2Array:
	var approx := 0.0
	for i in range(1, cp.size()):
		approx += cp[i].distance_to(cp[i - 1])
	var n := clampi(int(approx / 4.0), 10, 200)
	var out := PackedVector2Array()
	var tmp := PackedVector2Array()
	for s in range(n + 1):
		var t := float(s) / float(n)
		tmp = cp.duplicate()
		var m := tmp.size()
		while m > 1:
			for k in range(m - 1):
				tmp[k] = tmp[k].lerp(tmp[k + 1], t)
			m -= 1
		out.append(tmp[0])
	return out


func _catmull(ctrl: PackedVector2Array) -> PackedVector2Array:
	if ctrl.size() < 2:
		return ctrl
	var pts := PackedVector2Array()
	pts.append(ctrl[0])
	pts.append_array(ctrl)
	pts.append(ctrl[ctrl.size() - 1])
	var out := PackedVector2Array()
	for i in range(1, pts.size() - 2):
		for s in range(0, 21):
			var t := float(s) / 20.0
			out.append(_catmull_pt(pts[i - 1], pts[i], pts[i + 1], pts[i + 2], t))
	return out


func _catmull_pt(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
