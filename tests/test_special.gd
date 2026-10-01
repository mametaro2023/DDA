extends SceneTree
## 画面全体を使う弾幕(壁・収束リング)と、発生源の散らし(隅・縁の密度)の確認。
## godot --headless --path . --script tests/test_special.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const Mods = preload("res://scripts/mods.gd")

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
	var easy = null
	var insane = null
	for bm in loader.difficulties:
		if bm.version == "Irre's Beginner":
			easy = bm
		elif bm.version == "Insane":
			insane = bm
	var g0 := PatternGen.generate(easy)
	_check(not g0.gizmos.any(func(x): return x.kind == "wall") and not _has_list(g0.events), "入門の譜面には、壁・収束リングを入れない(Lv %.2f)" % g0.level)
	var g := PatternGen.generate(insane)
	var g2 := PatternGen.generate(insane)
	_check(str(g.events) == str(g2.events), "壁・収束リングを含めて、決定的(同じ入力で同じ弾幕)")
	var walls: Array = g.gizmos.filter(func(x): return x.kind == "wall")
	var lists := 0
	for e in g.events:
		for s in e.shots:
			if s.has("list"):
				lists += 1
	_check(walls.size() >= 1 and lists >= walls.size() + 1, "壁 %d 本・収束リングを含めて %d 件の「位置が決まった弾」がある" % [walls.size(), lists])
	# 壁: すき間があり、前の壁の隙間から離れている。弾が画面の中から始まる
	var ok_gap := true
	for i in range(2, walls.size()):   # 2 本前(同じ向き)の壁の隙間から離れている
		if absf(float(walls[i].gap) - float(walls[i - 2].gap)) < 100.0:
			ok_gap = false
	_check(ok_gap, "壁の隙間は、同じ向きの前の壁の隙間から離れている")
	var ok_in := true
	for e in g.events:
		for s in e.shots:
			if s.has("list"):
				for b in s.list:
					if not PatternGen.BOUNDS.has_point(b[0]):
						ok_in = false
	_check(ok_in, "壁・収束リングの弾は、画面の中から始まる(外から始まると、すぐ消える)")
	# 壁の弾は隙間が空いている(隙間の中に弾がない)
	var w0 = walls[0]
	var horiz: bool = int(w0.edge) % 2 == 0
	var gap_clear := true
	for e in g.events:
		if absf(float(e.t) - float(w0.t)) < 0.001:
			for s in e.shots:
				if s.has("list"):
					for b in s.list:
						var along: float = b[0].y if horiz else b[0].x
						if absf(along - float(w0.gap)) <= float(w0.gap_w) * 0.5:
							gap_clear = false
	_check(gap_clear, "壁の隙間(幅 %.0f)には、弾がない" % float(w0.gap_w))
	# MOD を適用しても、壁は残り、速さだけ変わる
	var storm := Mods.apply(g, Mods.params(["storm"]))
	var kept := _has_list(storm.events)
	_check(kept and storm.level != g.level, "MOD(暴風雨)を適用しても壁・収束リングは残る(Lv %.2f → %.2f)" % [g.level, storm.level])
	# 弾の通過の偏り: 隅・縁が、極端に薄くならない
	for bm in [insane, loader.difficulties[3]]:
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


func _has_list(events: Array) -> bool:
	for e in events:
		for s in e.shots:
			if s.has("list"):
				return true
	return false


## 弾を直進と見なして、0.1 秒ごとの位置を 8×6 に数える(平均 = 全体の平均)。
func _heat(events: Array) -> PackedFloat64Array:
	var grid := PackedFloat64Array()
	grid.resize(48)
	for e in events:
		var p: Vector2 = e.pos
		for s in e.shots:
			var bullets: Array = []
			if s.has("list"):
				bullets = s.list
			else:
				var base: float = s.a0
				if s.aim:
					base += (PatternGen.AIM_REF - p).angle()
				for i in range(s.n):
					bullets.append([p, Vector2.from_angle(PatternGen.shot_angle(s, base, i)) * s.speed])
			for b in bullets:
				var life := PatternGen._exit_time(b[0], b[1].normalized(), b[1].length())
				var t := 0.0
				while t < life:
					var q: Vector2 = b[0] + b[1] * t
					var gx := clampi(int(q.x / PatternGen.ARENA.x * 8), 0, 7)
					var gy := clampi(int(q.y / PatternGen.ARENA.y * 6), 0, 5)
					grid[gy * 8 + gx] += 1.0
					t += 0.1
	return grid
