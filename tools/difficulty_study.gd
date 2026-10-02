extends SceneTree
## 難易度の計算(PatternGen の Lv)が、実際の避けにくさとどれだけ合っているかを調べる(開発用)。
## 避けにくさの目安は、先読みして避けるボット(tests/test_sim.gd と同じ)の被弾時間(練習モードで最後まで走らせる)。
##   godot --headless --path . --script tools/difficulty_study.gd -- maps [osz の名前の一部 ...]   譜面ごと: Lv・★・ボットの被弾
##   godot --headless --path . --script tools/difficulty_study.gd -- factors                     要素ごと: 1 つずつ変えたときの Lv とボットの変化
## 出力は CSV ふうの行(先頭が "row," / "factor,")。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Mods = preload("res://scripts/mods.gd")

const DIRS := [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("factors"):
		_factors()
	else:
		var filters: Array = []
		for a in args:
			if a != "maps":
				filters.append(a)
		_maps(filters)
	quit()


func _osz_files() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://"):
		if f.ends_with(".osz"):
			out.append(ProjectSettings.globalize_path("res://" + f))
	out.sort()
	return out


## 譜面ごと。
func _maps(filters: Array) -> void:
	print("row,set,version,stars,target,lv,lv_nolen,len_s,break_frac,mean,p95,aim_frac,curl_frac,zones,bot_hit_s_per_min,bot_hits_per_min,bot_hit_s_per_min_nozone,weak_hit_s_per_min,weak_hit_s_per_min_nozone")
	for path in _osz_files():
		var ok := filters.is_empty()
		for f in filters:
			if str(path).contains(f):
				ok = true
		if not ok:
			continue
		var loader := OszLoader.new()
		if not loader.open(path):
			continue
		for bm in loader.difficulties:
			var gen := PatternGen.generate(bm)
			var r: Dictionary = gen.rating
			var st := _shot_stats(gen.events)
			var res := _run_bot(gen, {})
			var gen_nz := gen.duplicate()
			gen_nz["zones"] = []
			var res_nz := _run_bot(gen_nz, {})
			var weak := _run_bot(gen, {}, true)
			var weak_nz := _run_bot(gen_nz, {}, true)
			var brk := 0.0
			for b in gen.breaks:
				brk += float(b[1]) - float(b[0])
			print("row,%s,%s,%.2f,%.2f,%.2f,%.2f,%.0f,%.3f,%.1f,%.1f,%.3f,%.3f,%d,%.3f,%.2f,%.3f,%.3f,%.3f" % [
				str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "), gen.stars, gen.target_level, gen.level,
				PatternGen.level_of(r.score, gen.speed, gen.size), r.duration, brk / maxf(r.duration, 1.0), r.mean, r.p95,
				st.aim, st.curl, gen.zones.size(), res.hit_s_per_min, res.hits_per_min, res_nz.hit_s_per_min, weak.hit_s_per_min, weak_nz.hit_s_per_min])


## 要素ごと: いくつかの譜面で、1 つの要素だけを変えて、Lv(adj の比)とボットの被弾の比を比べる。
func _factors() -> void:
	var picks := [
		["320118 Reol", "Misuzu's Normal"], ["320118 Reol", "byfaR's Hard"], ["320118 Reol", "Insane"],
		["241526 Soleily", "Hard"], ["241526 Soleily", "Insane"], ["320118 Reol", "Fast's Expert"],
	]
	var variants := [
		["count x1.5", {"count_mul": 1.5}],
		["speed x1.5", {"speed_mul": 1.5}],
		["speed x0.67", {"speed_mul": 0.6667}],
		["size x1.35", {"size_mul": 1.35}],
		["player x2", {"player_scale": 2.0}],
		["rate x1.5", {"rate": 1.5}],
	]
	print("factor,set,version,variant,lv_base,lv_mod,adj_ratio,bot_ratio,weak_ratio,bot_base,weak_base")
	for pk in picks:
		var bm = _find(pk[0], pk[1])
		if bm == null:
			continue
		var gen := PatternGen.generate(bm)
		gen["zones"] = []   # 危険エリアは Lv に入っていないので、要素の比較からは外す
		var base := _run_bot(gen, {})
		var wbase := _run_bot(gen, {}, true)
		for v in variants:
			var p := Mods.params([])
			for key in v[1]:
				p[key] = v[1][key]
			p.ids = ["x"]
			var g2 := Mods.apply(gen, p)
			g2["zones"] = []
			var res := _run_bot(g2, p)
			var wres := _run_bot(g2, p, true)
			var adj_ratio := PatternGen.target_score_for(float(g2.level) + PatternGen.LEVEL_SHIFT) / PatternGen.target_score_for(float(gen.level) + PatternGen.LEVEL_SHIFT)
			print("factor,%s,%s,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f" % [pk[0], pk[1], v[0], gen.level, g2.level, adj_ratio,
				res.hit_s_per_min / maxf(base.hit_s_per_min, 0.001), wres.hit_s_per_min / maxf(wbase.hit_s_per_min, 0.001), base.hit_s_per_min, wbase.hit_s_per_min])


func _find(set_prefix: String, version: String):
	for path in _osz_files():
		if str(path).get_file().begins_with(set_prefix):
			var loader := OszLoader.new()
			if loader.open(path):
				for bm in loader.difficulties:
					if bm.version == version:
						return bm
	return null


## 弾の内訳: 自機狙いの弾・曲がる弾の割合(弾の数で数える)。
func _shot_stats(events: Array) -> Dictionary:
	var total := 0
	var aim := 0
	var curl := 0
	for e in events:
		for s in e.shots:
			total += int(s.n)
			if s.aim:
				aim += int(s.n)
			if absf(float(s.turn)) > 0.0:
				curl += int(s.n)
	return {"aim": float(aim) / maxf(total, 1), "curl": float(curl) / maxf(total, 1)}


## ボットで最後まで走らせる(練習モード: ゲージが 0 でも続ける)。被弾時間・被弾回数を、遊んだ時間 1 分あたりで返す。
## weak = true: 弱いボット(判断は 0.15 秒ごと、移動は低速 160 px/s)。強いボットは易しい譜面で被弾 0 になり、差が出ないため。
func _run_bot(gen: Dictionary, mods: Dictionary, weak := false) -> Dictionary:
	var field := BulletField.new()
	var sim := GameSim.new()
	var last_t := 0.0
	for e in gen.events:
		last_t = maxf(last_t, float(e.t))
	var end_t := last_t + 2.0
	var m := mods.duplicate()
	m["practice"] = true
	sim.setup(field, gen, end_t, true, m)
	var bot_every := maxi(int(round((0.15 if weak else 0.05) / DT)), 1)
	var now := 0.0
	var steps := 0
	var move := Vector2.ZERO
	var first_t := -1.0
	for e in gen.events:
		if not e.shots.is_empty():
			first_t = float(e.t)
			break
	while not sim.finished and steps < int((end_t + 10.0) / DT):
		if steps % bot_every == 0:
			move = _bot(sim, field, GameSim.PLAYER_SLOW if weak else GameSim.PLAYER_SPEED, 0.3 if weak else 0.18)
		sim.step(now, DT, move, weak)
		steps += 1
		now += DT
	field.free()
	var play_min := maxf(last_t - maxf(first_t, 0.0), 1.0) / 60.0
	return {"hit_s_per_min": sim.hit_time / play_min, "hits_per_min": sim.hits / play_min}


## 数フレーム先の弾位置を予測し、最も間隔が空く方向を選ぶ(tests/test_sim.gd と同じ)。
func _bot(sim, field, speed: float, horizon: float) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1e9
	var center := GameSim.ARENA * Vector2(0.5, 0.75)
	for d in DIRS:
		var np: Vector2 = sim.player_pos + d.normalized() * speed * horizon if d != Vector2.ZERO else sim.player_pos
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
		var sc := gap * 3.0 - np.distance_to(center) * 0.02
		if sc > best_score:
			best_score = sc
			best = d
	return best
