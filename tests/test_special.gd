extends SceneTree
## 発生源の散らし(隅・縁の弾の密度)と、曲がる弾の確認。
## godot --headless --path . --script tests/test_special.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var insane = null
	var hard = null
	for bm in loader.difficulties:
		if bm.version == "Insane":
			insane = bm
		elif bm.version == "byfaR's Hard":
			hard = bm
	var g := PatternGen.generate(insane)
	_check(str(g.events) == str(PatternGen.generate(insane).events), "決定的(同じ入力で同じ弾幕)")
	# 発生源が、画面の中に収まる(余白の中)
	var ok_in := true
	for e in g.events:
		if not Rect2(Vector2.ZERO, PatternGen.ARENA).has_point(e.pos):
			ok_in = false
	_check(ok_in, "発生源は、アリーナの中にある")
	# 曲がる弾: clap のリングは、★に応じて曲がる(向きは交互)
	var curved := 0
	for e in g.events:
		for s in e.shots:
			if absf(float(s.turn)) > 0.01:
				curved += 1
	_check(curved >= 3, "曲がる弾のショットがある(%d 件)" % curved)
	# スライダーの軌道は、発生源の補正を通しても形が変わらない(平行移動だけ。曲線がなめらかなまま)
	var worst := 0.0
	var nsl := 0
	for bm in loader.difficulties:
		var gens := PatternGen.generate(bm)
		var objs: Array = bm.hit_objects.filter(func(o): return o.kind == 1)
		var gz: Array = gens.gizmos.filter(func(x): return x.kind == "slider")
		for i in range(mini(objs.size(), gz.size())):
			var orig: PackedVector2Array = objs[i].curve.points
			var pts: PackedVector2Array = gz[i].points
			if orig.size() != pts.size():
				continue
			var d0: Vector2 = pts[0] - PatternGen.to_arena(orig[0])
			for j in range(pts.size()):
				worst = maxf(worst, (pts[j] - PatternGen.to_arena(orig[j]) - d0).length())
			nsl += 1
	_check(nsl > 20 and worst < 0.01, "スライダー %d 本の軌道が、元の形のまま平行移動されている(形のずれ 最大 %.4f px)" % [nsl, worst])
	# 弾の通過の偏り: 隅・縁が、極端に薄くならない(中央に偏らない)
	for bm in [insane, hard]:
		var gen := PatternGen.generate(bm)
		var grid := _heat(gen.events)
		var mean := 0.0
		for v in grid:
			mean += v
		mean /= grid.size()
		var lo := 1e9
		var hi := 0.0
		for v in grid:
			lo = minf(lo, v / mean)
			hi = maxf(hi, v / mean)
		_check(lo >= 0.55 and hi <= 1.6, "%s: 場所ごとの弾の通過密度が偏りすぎない(平均 1.0 に対し、最小 %.2f・最大 %.2f)" % [bm.version, lo, hi])
	print("test_special: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


## 弾を直進と見なして、0.1 秒ごとの位置を 8×6 に数える。
func _heat(events: Array) -> PackedFloat64Array:
	var grid := PackedFloat64Array()
	grid.resize(48)
	for e in events:
		var p: Vector2 = e.pos
		for s in e.shots:
			var base: float = s.a0
			if s.aim:
				base += (PatternGen.AIM_REF - p).angle()
			for i in range(s.n):
				var v: Vector2 = Vector2.from_angle(PatternGen.shot_angle(s, base, i)) * s.speed
				var life := PatternGen._exit_time(p, v.normalized(), s.speed)
				var t := 0.0
				while t < life:
					var q: Vector2 = p + v * t
					var gx := clampi(int(q.x / PatternGen.ARENA.x * 8), 0, 7)
					var gy := clampi(int(q.y / PatternGen.ARENA.y * 6), 0, 5)
					grid[gy * 8 + gx] += 1.0
					t += 0.1
	return grid
