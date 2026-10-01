extends SceneTree
## 弾幕の「場所の偏り」と「居座り」の測定(開発用)。
##   godot --headless --path . --script tests/analyze_coverage.gd -- [osz] [難易度の一部 ...]
## 1) 弾の通過密度の地図(アリーナを 8×6 に区切り、平均を 100 とした相対値)
## 2) 居座るボット(隅 / 中央下に居続け、弾が近いときだけ避ける)と、普通のボットを走らせ、
##    被弾・移動距離・「ほとんど動かなかった時間の割合」を比べる

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")

const DIRS := [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
const GX := 8
const GY := 6


func _init() -> void:
	var osz := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
	var filters: Array = []
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".osz"):
			osz = a
		else:
			filters.append(a)
	if filters.is_empty():
		filters = ["Insane"]
	var loader := OszLoader.new()
	loader.open(osz)
	for bm in loader.difficulties:
		var ok := false
		for f in filters:
			if bm.version.contains(f):
				ok = true
		if ok:
			_analyze(bm)
	quit()


func _analyze(bm) -> void:
	print("=== %s [%s]" % [bm.title, bm.version])
	var gen := PatternGen.generate(bm)
	print("Lv %.2f  events=%d" % [gen.level, gen.events.size()])
	var homes := {"normal": null, "corner(左下)": Vector2(40, 680), "corner(右上)": Vector2(920, 40), "中央下": Vector2(480, 600)}
	var first := true
	for name in homes:
		var r := _run(bm, gen, homes[name], first)
		first = false
		print("%-12s hits=%3d hit=%5dms  移動 %.0f px/s  ほぼ静止 %2.0f%%  graze=%d" % [name, r.hits, r.hit_ms, r.speed, r.still * 100.0, r.graze])


## 動かない自機を、4×3 の位置に置いて、最後まで走らせたときの被弾時間(ms)。小さい場所は、動かなくても済む安全地帯。
func _stationary(bm, gen: Dictionary) -> void:
	var line_all := []
	var safe := 0
	for gy in range(3):
		var line := ""
		for gx in range(4):
			var pos := Vector2((gx + 0.5) / 4.0 * GameSim.ARENA.x, (gy + 0.5) / 3.0 * GameSim.ARENA.y)
			var ms := _hold(bm, gen, pos)
			line += "%7d" % ms
			if ms < 400:
				safe += 1
		line_all.append(line)
	print("動かない自機の被弾時間 ms(4×3 の位置。400 ms 未満の場所: %d / 12):" % safe)
	for l in line_all:
		print(l)


func _hold(bm, gen: Dictionary, pos: Vector2) -> int:
	var field := BulletField.new()
	var sim := GameSim.new()
	var end_t: float = bm.last_time() / 1000.0 + 2.0
	sim.setup(field, gen, end_t, true, {})
	sim.player_pos = pos
	var now := 0.0
	var steps := 0
	while not sim.finished:
		sim.player_pos = pos
		sim.step(now, 1.0 / 60.0, Vector2.ZERO, false)
		steps += 1
		now += 1.0 / 60.0
		if steps > int((end_t + 10.0) / (1.0 / 60.0)):
			break
	var ms := int(sim.hit_time * 1000.0)
	field.free()
	return ms


func _run(bm, gen: Dictionary, home, want_map: bool) -> Dictionary:
	var field := BulletField.new()
	var sim := GameSim.new()
	var end_t: float = bm.last_time() / 1000.0 + 2.0
	sim.setup(field, gen, end_t, true, {})
	var dt := 1.0 / 60.0
	var now := 0.0
	var steps := 0
	var move := Vector2.ZERO
	var dist := 0.0
	var still := 0
	var last := sim.player_pos
	var grid := PackedFloat64Array()
	grid.resize(GX * GY)
	var samples := 0
	while not sim.finished:
		if steps % 3 == 0:
			move = _bot(sim, field, home)
		sim.step(now, dt, move, false)
		var moved: float = sim.player_pos.distance_to(last)
		dist += moved
		if moved < GameSim.PLAYER_SPEED * dt * 0.15:
			still += 1
		last = sim.player_pos
		if want_map and steps % 6 == 0:
			samples += 1
			for i in range(field.count):
				var p: Vector2 = field.pos[i]
				var gx := clampi(int(p.x / GameSim.ARENA.x * GX), 0, GX - 1)
				var gy := clampi(int(p.y / GameSim.ARENA.y * GY), 0, GY - 1)
				grid[gy * GX + gx] += 1.0
		steps += 1
		now += dt
		if steps > int((end_t + 10.0) / dt):
			break
	if want_map:
		_print_map(grid)
	var out := {"hits": sim.hits, "hit_ms": int(sim.hit_time * 1000.0), "speed": dist / maxf(now, 0.001), "still": float(still) / maxf(steps, 1), "graze": sim.graze}
	field.free()
	return out


func _print_map(grid: PackedFloat64Array) -> void:
	var sum := 0.0
	for v in grid:
		sum += v
	var mean := sum / grid.size()
	print("弾の通過密度(平均=100。行=上から、列=左から):")
	for y in range(GY):
		var line := ""
		for x in range(GX):
			line += "%5d" % int(round(grid[y * GX + x] / mean * 100.0))
		print(line)


## home が null なら、普通のボット(中央下へ緩く寄る)。home があれば、そこへ強く戻りつつ、弾が近いときだけ避ける。
func _bot(sim, field, home) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1e9
	var horizon := 0.18
	var target: Vector2 = GameSim.ARENA * Vector2(0.5, 0.75) if home == null else home
	var w := 0.02 if home == null else 0.12
	for d in DIRS:
		var np: Vector2 = sim.player_pos + d.normalized() * GameSim.PLAYER_SPEED * horizon if d != Vector2.ZERO else sim.player_pos
		np = np.clamp(Vector2(12, 12), GameSim.ARENA - Vector2(12, 12))
		var gap := 80.0
		for i in range(field.count):
			if field.grace[i] > 0.0:
				continue
			var bp: Vector2 = field.pos[i]
			var mid: Vector2 = bp + field.vel[i] * (horizon * 0.5)
			var endp: Vector2 = bp + field.vel[i] * horizon
			var g: float = minf(minf(bp.distance_to(sim.player_pos), mid.distance_to(sim.player_pos.lerp(np, 0.5))),
				endp.distance_to(np)) - field.rad[i]
			if g < gap:
				gap = g
		var sc := gap * 3.0 - np.distance_to(target) * w
		if sc > best_score:
			best_score = sc
			best = d
	return best
