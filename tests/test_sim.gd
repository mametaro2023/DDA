extends SceneTree
## godot --headless --path . --script tests/test_sim.gd -- [osz] [diff-substring ...]
## 各難易度を簡易ボットで最後まで走らせ、弾数・被弾・処理時間を報告する。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Mods = preload("res://scripts/mods.gd")

const DIRS := [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]

var _fail := 0
var _mod_ids: Array = []
var _mods := {}
var _dt := 1.0 / 60.0   # 引数 1khz で 1 ms 刻み(実ゲームの判定刻みと同じ)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var osz := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
	var filters: Array = []
	for a in args:
		if a.ends_with(".osz"):
			osz = a
		elif a == "1khz":
			_dt = 0.001   # 1 ms 刻み(実ゲームの判定刻み)
		elif not Mods.find(a).is_empty():
			_mod_ids.append(a)   # MOD(hell / storm / giant / rush)を付けて走らせる
		else:
			filters.append(a)
	_mods = Mods.params(_mod_ids)
	var loader := OszLoader.new()
	_check(loader.open(osz), "open " + loader.error)
	for bm in loader.difficulties:
		if not filters.is_empty():
			var ok := false
			for f in filters:
				if bm.version.contains(f):
					ok = true
			if not ok:
				continue
		_run(bm)
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)


func _run(bm) -> void:
	var t_gen := Time.get_ticks_usec()
	var gen := PatternGen.generate(bm)
	var gen_ms := (Time.get_ticks_usec() - t_gen) / 1000.0
	# 決定性
	var gen2 := PatternGen.generate(bm)
	_check(gen.events.size() == gen2.events.size() and str(gen.events.back()) == str(gen2.events.back()), "non-deterministic")
	var field := BulletField.new()
	var sim := GameSim.new()
	var end_t: float = bm.last_time() / 1000.0 + 2.0
	sim.setup(field, Mods.apply(gen, _mods), end_t, true, _mods)  # 練習モードで被弾数を数える(1ミス即終了だと以降が測れない)
	var dt := _dt
	var bot_every := maxi(int(round(0.05 / dt)), 1)   # ボットの判断は 0.05 秒ごと
	var now := 0.0
	var max_bullets := 0
	var sum_bullets := 0
	var steps := 0
	var move := Vector2.ZERO
	var t_run := Time.get_ticks_usec()
	while not sim.finished:
		if steps % bot_every == 0:
			move = _bot(sim, field)
		sim.step(now, dt, move, false)
		max_bullets = maxi(max_bullets, field.count)
		sum_bullets += field.count
		steps += 1
		now += dt
		if steps > int((end_t + 10.0) / dt):
			_check(false, "did not finish")
			break
	var run_ms := (Time.get_ticks_usec() - t_run) / 1000.0
	_check(is_finite(sim.player_pos.x) and is_finite(sim.player_pos.y), "player NaN")
	_check(max_bullets < BulletField.MAX_BULLETS, "bullet cap reached")
	print("%-22s Lv%4.1f est(mean=%5.1f p95=%4.0f peak=%4.0f) events=%4d gen=%.0fms | sim: maxBullets=%4d avg=%4d | hits=%3d hit=%4dms graze=%4d score=%7d | %.3fms/step, %.1f%% of realtime (dt=%.1fms)" % [
		bm.version, gen.level, gen.rating.mean, gen.rating.p95, gen.rating.peak, gen.events.size(), gen_ms, max_bullets, sum_bullets / maxi(steps, 1),
		sim.hits, int(sim.hit_time * 1000.0), sim.graze, int(sim.score), run_ms / steps, run_ms / 1000.0 / maxf(now, 0.001) * 100.0, dt * 1000.0])
	field.free()


## 数フレーム先の弾位置を予測し、最も間隔が空く方向を選ぶ。
func _bot(sim, field) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1e9
	var horizon := 0.18
	var center := GameSim.ARENA * Vector2(0.5, 0.75)
	for d in DIRS:
		var np: Vector2 = sim.player_pos + d.normalized() * GameSim.PLAYER_SPEED * horizon if d != Vector2.ZERO else sim.player_pos
		np = np.clamp(Vector2(12, 12), GameSim.ARENA - Vector2(12, 12))
		var gap := 80.0
		for i in range(field.count):
			if field.grace[i] > 0.0:
				continue
			var bp: Vector2 = field.pos[i]
			# 途中経過と終端の両方を見る
			var mid: Vector2 = bp + field.vel[i] * (horizon * 0.5)
			var endp: Vector2 = bp + field.vel[i] * horizon
			var g: float = minf(minf(bp.distance_to(sim.player_pos.lerp(np, 0.0)), mid.distance_to(sim.player_pos.lerp(np, 0.5))),
				endp.distance_to(np)) - field.rad[i]
			if g < gap:
				gap = g
		var sc := gap * 3.0 - np.distance_to(center) * 0.02
		if sc > best_score:
			best_score = sc
			best = d
	return best
