extends SceneTree
## 難易度の計算(PatternGen の Lv)が、実際の避けにくさとどれだけ合っているかを調べる(開発用)。
## 避けにくさの目安は、先読みして避けるボット(tests/test_sim.gd と同じ)の被弾時間(練習モードで最後まで走らせる)。
##   godot --headless --path . --script tools/difficulty_study.gd -- maps [osz の名前の一部 ...]   譜面ごと: Lv・★・ボットの被弾
##   godot --headless --path . --script tools/difficulty_study.gd -- factors                     要素ごと: 1 つずつ変えたときの Lv とボットの変化
##   godot --headless --path . --script tools/difficulty_study.gd -- mods [dir=<osz のフォルダ>] [part=k/n]   MOD ごと: Lv の変化と、ボットが倒れる回数(ベーススコアの倍率を決める材料)
##   godot --headless --path . --script tools/difficulty_study.gd -- elastic [jobs=12] [minlv=0]  弾数・弾の大きさの効き(並列。下の _elastic)
## 出力は CSV ふうの行(先頭が "row," / "factor," / "mod," / "el,")。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Mods = preload("res://scripts/mods.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")

const DIRS := [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
const DT := 1.0 / 60.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("mods"):
		_mods(args)
	elif args.has("factors"):
		_factors()
	elif args.has("elastic"):
		_elastic(args)
	else:
		var filters: Array = []
		for a in args:
			if a != "maps":
				filters.append(a)
		_maps(filters)
	quit()


func _osz_files(dir := "res://") -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".osz"):
			out.append(ProjectSettings.globalize_path(dir.path_join(f)))
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


## MOD ごと: 全譜面(弾幕 v2)で、MOD を付けたときの Lv の変化(adj の比)と、ボットが倒れる回数(練習モードで走らせ、ゲージが 0 になるたびに満タンへ戻して数える)を比べる。
## 倒れる回数は、Lv に出ない厳しさ(体力・自然回復・低体力の半減)も含めた、避けにくさの目安。強いボットと弱いボットの 2 つで測る。
## 最後に "mod_sum," の行で、全譜面の合計(倒れた回数の比・Lv の比の平均)を出す。part=k/n なら、譜面の k 番目の組だけ(並べて走らせる用。合計は手で足す)。
func _mods(args: Array) -> void:
	var dir := "res://"
	var part := 0
	var parts := 1
	for a in args:
		if str(a).begins_with("dir="):
			dir = str(a).trim_prefix("dir=")
		elif str(a).begins_with("part="):
			var kn: PackedStringArray = str(a).trim_prefix("part=").split("/")
			part = int(kn[0])
			parts = int(kn[1])
	var variants := [
		["base", {}],
		["rush", {"mods": ["rush"]}],
		["hell", {"mods": ["hell"]}],
		["slow", {"mods": ["slow"]}],
		["heaven", {"mods": ["heaven"]}],
		["size0.7", {"set": {"size_mul": 0.7}}],
		["noregen", {"mods": ["noregen"]}],
	]
	print("mod,set,version,variant,lv,adj_ratio,strong_deaths,weak_deaths,strong_hit_s,weak_hit_s,play_min")
	var sums := {}
	var k := 0
	for path in _osz_files(dir):
		var loader := OszLoader.new()
		if not loader.open(path):
			continue
		for bm in loader.difficulties:
			k += 1
			if (k - 1) % parts != part:
				continue
			var gen := PatternGenV2.generate(bm, {})
			for v in variants:
				var p := Mods.params(v[1].get("mods", []))
				var setp: Dictionary = v[1].get("set", {})
				for key in setp:
					p[key] = setp[key]
					p.ids = ["x"]
				var g2 := Mods.apply(gen, p)
				var adj := PatternGen.target_score_for(float(g2.level) + PatternGen.LEVEL_SHIFT) / PatternGen.target_score_for(float(gen.level) + PatternGen.LEVEL_SHIFT)
				var s := _run_deaths(g2, p, false)
				var w := _run_deaths(g2, p, true)
				print("mod,%s,%s,%s,%.2f,%.3f,%d,%d,%.2f,%.2f,%.2f" % [str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "), v[0],
					g2.level, adj, s.deaths, w.deaths, s.hit_s, w.hit_s, s.play_min])
				var acc: Dictionary = sums.get(v[0], {"n": 0, "adj": 0.0, "sd": 0, "wd": 0, "min": 0.0})
				acc.n += 1
				acc.adj += adj
				acc.sd += s.deaths
				acc.wd += w.deaths
				acc.min += s.play_min
				sums[v[0]] = acc
	for name in sums:
		var a: Dictionary = sums[name]
		print("mod_sum,%s,n=%d,adj_avg=%.3f,strong_deaths=%d,weak_deaths=%d,min=%.1f" % [name, a.n, a.adj / maxf(a.n, 1), a.sd, a.wd, a.min])


## ボットで最後まで走らせ(練習モード)、ゲージが 0 になった回数を数える(なるたびに満タンへ戻す)。
## p は Mods.params の形(体力・自然回復・低体力の半減・自機の大きさが効く)。再生速度は、弾幕の時刻(g2)に入っている。
func _run_deaths(g2: Dictionary, p: Dictionary, weak: bool) -> Dictionary:
	var field := BulletField.new()
	var sim := GameSim.new()
	var last_t := 0.0
	for e in g2.events:
		last_t = maxf(last_t, float(e.t))
	var end_t := last_t + 2.0
	var m := p.duplicate()
	m["practice"] = true
	sim.setup(field, g2, end_t, true, m)
	var bot_every := maxi(int(round((0.15 if weak else 0.05) / DT)), 1)
	var now := 0.0
	var steps := 0
	var move := Vector2.ZERO
	var deaths := 0
	var first_t := -1.0
	for e in g2.events:
		if not e.shots.is_empty():
			first_t = float(e.t)
			break
	while not sim.finished and steps < int((end_t + 10.0) / DT):
		if steps % bot_every == 0:
			move = _bot(sim, field, GameSim.PLAYER_SLOW if weak else GameSim.PLAYER_SPEED, 0.3 if weak else 0.18)
		sim.step(now, DT, move, weak)
		if sim.gauge <= 0.0:
			deaths += 1
			sim.gauge = 1.0
		steps += 1
		now += DT
	field.free()
	return {"deaths": deaths, "hit_s": sim.hit_time, "play_min": maxf(last_t - maxf(first_t, 0.0), 1.0) / 60.0}


# --- 弾の数と大きさの効き(elastic): 並列で走らせる ---
## 弾数・弾サイズ・自機サイズを少しずつ変え、ボットの被弾がどれだけ増えるかから「効き」(弾性 = ln(被弾の比) / ln(変えた倍率))を求める。
## 弾の大きさは、危険半径(弾 + 自機の当たり判定)の比で数える。Lv の計算は「弾数 ^1 × 危険半径 ^SIZE_EXP」なので、
## 危険半径の効き ÷ 弾数の効き が、ボットに合う SIZE_EXP の目安になる。弾幕は v2(いまの初期状態)。
##   godot --headless --path . --script tools/difficulty_study.gd -- elastic [jobs=12] [dir=<osz のフォルダ>] [minlv=0]
## jobs > 1 なら、自分を jobs 個の子プロセスとして起動し(part=k/n out=<ファイル>)、終わったら全部を集計する。
## ボットは決まった動きなので、開始位置を SEEDS 通りにずらして、同じ条件を複数回走らせる。
const ELASTIC_VARIANTS := [
	["base", {}],
	["count1.25", {"count_mul": 1.25}],
	["count1.5", {"count_mul": 1.5}],
	["size1.25", {"size_mul": 1.25}],
	["size1.5", {"size_mul": 1.5}],
	["player1.5", {"player_scale": 1.5}],
]
const SEEDS := [Vector2.ZERO, Vector2(-90, 0), Vector2(90, -20)]


func _elastic(args: Array) -> void:
	var dir := "res://"
	var jobs := 1
	var part := 0
	var parts := 1
	var out := ""
	var minlv := 0.0
	for a in args:
		var s := str(a)
		if s.begins_with("dir="):
			dir = s.trim_prefix("dir=")
		elif s.begins_with("jobs="):
			jobs = int(s.trim_prefix("jobs="))
		elif s.begins_with("minlv="):
			minlv = float(s.trim_prefix("minlv="))
		elif s.begins_with("out="):
			out = s.trim_prefix("out=")
		elif s.begins_with("part="):
			var kn: PackedStringArray = s.trim_prefix("part=").split("/")
			part = int(kn[0])
			parts = int(kn[1])
	if jobs > 1 and out == "":
		_elastic_parent(dir, jobs, minlv)
		return
	var lines: Array = []
	var k := 0
	for path in _osz_files(dir):
		var loader := OszLoader.new()
		if not loader.open(path):
			continue
		for bm in loader.difficulties:
			k += 1
			if (k - 1) % parts != part:
				continue
			var gen := PatternGenV2.generate(bm, {})
			if float(gen.level) < minlv:
				continue
			gen["zones"] = []   # 特殊エリアは Lv に入っていないので外す
			var r0 := PatternGen.danger_radius(float(gen.size))
			for v in ELASTIC_VARIANTS:
				var p := Mods.params([])
				for key in v[1]:
					p[key] = v[1][key]
				if not (v[1] as Dictionary).is_empty():
					p.ids = ["x"]
				var g2 := Mods.apply(gen, p) if not (v[1] as Dictionary).is_empty() else gen
				g2["zones"] = []
				var r1 := PatternGen.danger_radius(float(gen.size) * float(p.size_mul), PatternGen.PLAYER_HIT_R * float(p.player_scale))
				for si in range(SEEDS.size()):
					for weak in [false, true]:
						var res := _run_bot_at(g2, p, weak, SEEDS[si])
						lines.append("el,%s,%s,%.2f,%s,%d,%s,%.4f,%.4f,%.3f" % [str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "),
							gen.level, v[0], si, "weak" if weak else "strong", res.hit_s, res.play_min, r1 / r0])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	else:
		_elastic_report(lines)


func _elastic_parent(dir: String, jobs: int, minlv: float) -> void:
	var exe := OS.get_executable_path()
	var tmp := OS.get_temp_dir().path_join("danmaku_elastic").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(tmp)
	var pids: Array = []
	var files: Array = []
	var t0 := Time.get_ticks_msec()
	for j in range(jobs):
		var f := tmp.path_join("part%d.csv" % j)
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
		files.append(f)
		pids.append(OS.create_process(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/difficulty_study.gd", "--",
			"elastic", "dir=" + dir, "minlv=%f" % minlv, "part=%d/%d" % [j, jobs], "out=" + f]))
	while true:
		var running := 0
		for pid in pids:
			if int(pid) > 0 and OS.is_process_running(int(pid)):
				running += 1
		if running == 0:
			break
		OS.delay_msec(500)
	var lines: Array = []
	for f in files:
		if FileAccess.file_exists(f):
			for l in FileAccess.get_file_as_string(f).split("\n"):
				if l.begins_with("el,"):
					lines.append(l)
	print("elastic: %d 本の結果(%d 並列、%.0f 秒)" % [lines.size(), jobs, (Time.get_ticks_msec() - t0) / 1000.0])
	_elastic_report(lines)


## 集計: 変えたもの・ボットごとに、全譜面・全開始位置の被弾時間を足して、基準(base)との比を出す(被弾 0 の譜面があっても割れない)。
## 被弾の比 → 弾性。弾数は倍率、弾・自機の大きさは危険半径の比(譜面ごとに違うので、平均)で割る。
func _elastic_report(lines: Array) -> void:
	for l in lines:
		print(l)
	var sum := {}     # "variant|bot" → 被弾時間の合計
	var rr := {}      # variant → [危険半径の比の合計, 数]
	var maps := {}
	for l in lines:
		var c: PackedStringArray = str(l).split(",")
		var key := c[4] + "|" + c[6]
		sum[key] = float(sum.get(key, 0.0)) + float(c[7])
		var a: Array = rr.get(c[4], [0.0, 0])
		a[0] += float(c[9])
		a[1] += 1
		rr[c[4]] = a
		maps[c[1] + c[2]] = true
	print("elastic_sum: 譜面 %d" % maps.size())
	var mult := {"count1.25": 1.25, "count1.5": 1.5}
	for bot in ["strong", "weak"]:
		var base := float(sum.get("base|" + bot, 0.0))
		var e_count := []
		for v in ELASTIC_VARIANTS:
			var name: String = v[0]
			if name == "base":
				continue
			var ratio := float(sum.get(name + "|" + bot, 0.0)) / maxf(base, 1e-6)
			var x: float = mult.get(name, 0.0)
			var by := "弾数"
			if x == 0.0:
				x = float(rr[name][0]) / maxf(float(rr[name][1]), 1.0)
				by = "危険半径"
			var el := log(maxf(ratio, 1e-6)) / log(x)
			if by == "弾数":
				e_count.append(el)
			print("elastic_sum,%s,%s,被弾の比 %.3f,%s ×%.3f,弾性 %.2f" % [bot, name, ratio, by, x, el])
		var ec := 0.0
		for e in e_count:
			ec += float(e) / e_count.size()
		for name in ["size1.25", "size1.5", "player1.5"]:
			var x := float(rr[name][0]) / maxf(float(rr[name][1]), 1.0)
			var ratio := float(sum.get(name + "|" + bot, 0.0)) / maxf(base, 1e-6)
			print("elastic_fit,%s,%s,SIZE_EXP の目安 %.2f(危険半径の弾性 %.2f ÷ 弾数の弾性 %.2f。いまは %.2f)" % [bot, name, (log(maxf(ratio, 1e-6)) / log(x)) / maxf(ec, 1e-6), log(maxf(ratio, 1e-6)) / log(x), ec, PatternGen.SIZE_EXP])


## _run_bot と同じ。開始位置を offset だけずらし、被弾時間(秒)と遊んだ分数を返す。p: Mods.params の形(自機の大きさが効く)。
func _run_bot_at(gen: Dictionary, p: Dictionary, weak: bool, offset: Vector2) -> Dictionary:
	var field := BulletField.new()
	var sim := GameSim.new()
	var last_t := 0.0
	for e in gen.events:
		last_t = maxf(last_t, float(e.t))
	var end_t := last_t + 2.0
	var m := p.duplicate()
	m["practice"] = true
	sim.setup(field, gen, end_t, true, m)
	sim.player_pos = (sim.player_pos + offset).clamp(Vector2(12, 12), GameSim.ARENA - Vector2(12, 12))
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
	return {"hit_s": sim.hit_time, "play_min": maxf(last_t - maxf(first_t, 0.0), 1.0) / 60.0}
