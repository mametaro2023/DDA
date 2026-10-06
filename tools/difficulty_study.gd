extends SceneTree
## 難易度の計算(PatternGen の Lv)が、実際の避けにくさとどれだけ合っているかを調べる(開発用)。
## 避けにくさの目安は、先読みして避けるボット(tests/test_sim.gd と同じ)の被弾時間(練習モードで最後まで走らせる)。
##   godot --headless --path . --script tools/difficulty_study.gd -- maps [osz の名前の一部 ...]   譜面ごと: Lv・★・ボットの被弾
##   godot --headless --path . --script tools/difficulty_study.gd -- factors                     要素ごと: 1 つずつ変えたときの Lv とボットの変化
##   godot --headless --path . --script tools/difficulty_study.gd -- mods [dir=<osz のフォルダ>] [jobs=14] [sexp=1.0]   MOD ごと: Lv の変化と、ボットが倒れる回数(ベーススコアの倍率を決める材料)
##   godot --headless --path . --script tools/difficulty_study.gd -- elastic [jobs=12] [minlv=0] [bots=human hd=0.26 he=0.15]  弾数・弾の大きさ・弾速の効き(並列。下の _elastic)
##   godot --headless --path . --script tools/difficulty_study.gd -- calib [jobs=14]   人間に近いボットを、保存されたリプレイ(使う人のプレイ)に合わせる(下の _calib)
##   godot --headless --path . --script tools/difficulty_study.gd -- sizeexp [exp=1.3] [jobs=14]   SIZE_EXP を変えたときの、全譜面の Lv の変化(下の _sizeexp)
## 出力は CSV ふうの行(先頭が "row," / "factor," / "mod," / "el,")。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Mods = preload("res://scripts/mods.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const Replay = preload("res://scripts/replay.gd")

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
	elif args.has("calib"):
		_calib(args)
	elif args.has("sizeexp"):
		_sizeexp(args)
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
	var jobs := 1
	var out := ""
	var sexp := PatternGen.SIZE_EXP
	for a in args:
		if str(a).begins_with("dir="):
			dir = str(a).trim_prefix("dir=")
		elif str(a).begins_with("jobs="):
			jobs = int(str(a).trim_prefix("jobs="))
		elif str(a).begins_with("sexp="):   # SIZE_EXP を差し替えて測る(前の値と比べる用)
			sexp = float(str(a).trim_prefix("sexp="))
		elif str(a).begins_with("out="):
			out = str(a).trim_prefix("out=")
		elif str(a).begins_with("part="):
			var kn: PackedStringArray = str(a).trim_prefix("part=").split("/")
			part = int(kn[0])
			parts = int(kn[1])
	if jobs > 1 and out == "":   # 並列: 子の行を集めて、ここで合計する
		_mods_sum(_parallel(["mods", "dir=" + dir, "sexp=%f" % sexp], jobs, "mod,"))
		return
	var variants := [
		["base", {}],
		["rush", {"mods": ["rush"]}],
		["storm", {"mods": ["storm"]}],
		["giant", {"mods": ["giant"]}],
		["hell", {"mods": ["hell"]}],
		["slow", {"mods": ["slow"]}],
		["heaven", {"mods": ["heaven"]}],
		["noregen", {"mods": ["noregen"]}],
	]
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
			var gen := PatternGenV2.generate(bm, {"size_exp": sexp})
			for v in variants:
				var p := Mods.params(v[1].get("mods", []))
				var setp: Dictionary = v[1].get("set", {})
				for key in setp:
					p[key] = setp[key]
					p.ids = ["x"]
				var g2 := Mods.apply(gen, p)
				var tbl: Array = gen.get("table", PatternGen.TARGET_TABLE)   # 弾幕 v2 は v2 の表(★ ⇔ 弾数)
				var adj := PatternGen.target_score_for(float(g2.level) + PatternGen.LEVEL_SHIFT, tbl) / PatternGen.target_score_for(float(gen.level) + PatternGen.LEVEL_SHIFT, tbl)
				var s := _run_deaths(g2, p, false)
				var w := _run_deaths(g2, p, true)
				lines.append("mod,%s,%s,%s,%.2f,%.3f,%d,%d,%.2f,%.2f,%.2f" % [str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "), v[0],
					g2.level, adj, s.deaths, w.deaths, s.hit_s, w.hit_s, s.play_min])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	else:
		_mods_sum(lines)


## MOD ごとの合計: Lv の比(adj_ratio)の平均、強い・弱いボットが倒れた回数の合計、被弾時間の合計。
func _mods_sum(lines: Array) -> void:
	print("mod,set,version,variant,lv,adj_ratio,strong_deaths,weak_deaths,strong_hit_s,weak_hit_s,play_min")
	var sums := {}
	var order: Array = []
	for l in lines:
		print(l)
		var c: PackedStringArray = str(l).split(",")
		var name := c[3]
		if not sums.has(name):
			order.append(name)
		var acc: Dictionary = sums.get(name, {"n": 0, "adj": 0.0, "lv": 0.0, "sd": 0, "wd": 0, "sh": 0.0, "wh": 0.0, "min": 0.0})
		acc.n += 1
		acc.adj += float(c[5])
		acc.lv += float(c[4])
		acc.sd += int(c[6])
		acc.wd += int(c[7])
		acc.sh += float(c[8])
		acc.wh += float(c[9])
		acc.min += float(c[10])
		sums[name] = acc
	var base: Dictionary = sums.get("base", {"lv": 0.0, "n": 1})
	for name in order:
		var a: Dictionary = sums[name]
		print("mod_sum,%s,n=%d,adj_avg=%.3f,lv_avg=%.2f(差 %+.2f),strong_deaths=%d,weak_deaths=%d,strong_hit_s=%.1f,weak_hit_s=%.1f,min=%.1f" % [name, a.n, a.adj / maxf(a.n, 1),
			a.lv / maxf(a.n, 1), a.lv / maxf(a.n, 1) - float(base.lv) / maxf(float(base.n), 1), a.sd, a.wd, a.sh, a.wh, a.min])


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
	["speed1.25", {"speed_mul": 1.25}],
	["speed0.8", {"speed_mul": 0.8}],
]
const SEEDS := [Vector2.ZERO, Vector2(-90, 0), Vector2(90, -20)]


func _elastic(args: Array) -> void:
	var dir := "res://"
	var jobs := 1
	var part := 0
	var parts := 1
	var out := ""
	var minlv := 0.0
	var bots := ["strong", "weak"]
	var hd := 0.26
	var he := 0.15
	for a in args:
		var s := str(a)
		if s.begins_with("bots="):
			bots = Array(s.trim_prefix("bots=").split("+"))
		elif s.begins_with("hd="):
			hd = float(s.trim_prefix("hd="))
		elif s.begins_with("he="):
			he = float(s.trim_prefix("he="))
		elif s.begins_with("dir="):
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
		_elastic_report(_parallel(["elastic", "dir=" + dir, "minlv=%f" % minlv, "bots=" + "+".join(bots), "hd=%f" % hd, "he=%f" % he], jobs, "el,"), bots)
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
					for bot in bots:
						var res := _run_bot_at(g2, p, bot == "weak", SEEDS[si]) if bot != "human" else _run_human_at(g2, p, SEEDS[si], hd, he, hash("%s|%s|%d" % [path, bm.version, si]))
						lines.append("el,%s,%s,%.2f,%s,%d,%s,%.4f,%.4f,%.3f" % [str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "),
							gen.level, v[0], si, bot, res.hit_s, res.play_min, r1 / r0])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	else:
		_elastic_report(lines, bots)


## 集計: 変えたもの・ボットごとに、全譜面・全開始位置の被弾時間を足して、基準(base)との比を出す(被弾 0 の譜面があっても割れない)。
## 被弾の比 → 弾性。弾数は倍率、弾・自機の大きさは危険半径の比(譜面ごとに違うので、平均)で割る。
func _elastic_report(lines: Array, bots: Array = ["strong", "weak"]) -> void:
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
	var mult := {"count1.25": 1.25, "count1.5": 1.5, "speed1.25": 1.25, "speed0.8": 0.8}
	for bot in bots:
		var base := float(sum.get("base|" + bot, 0.0))
		var e_count := []
		for v in ELASTIC_VARIANTS:
			var name: String = v[0]
			if name == "base":
				continue
			var ratio := float(sum.get(name + "|" + bot, 0.0)) / maxf(base, 1e-6)
			var x: float = mult.get(name, 0.0)
			var by := "弾数" if name.begins_with("count") else "弾速"
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


## _run_bot_at の人間に近いボット版(下の _run_human)。
func _run_human_at(gen: Dictionary, p: Dictionary, offset: Vector2, delay: float, err: float, seed: int) -> Dictionary:
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
	var first_t := -1.0
	for e in gen.events:
		if not e.shots.is_empty():
			first_t = float(e.t)
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hit_s := _run_human(sim, field, end_t + 10.0, delay, err, rng)
	field.free()
	return {"hit_s": hit_s, "play_min": maxf(last_t - maxf(first_t, 0.0), 1.0) / 60.0}


# --- 人間に近いボット(human)と、リプレイでの合わせ込み(calib) ---
## 今のボット(_bot)は、反応が 0.05 秒・動きにぶれがない・自分の大きさを考えない、で人間よりずっと強い。人間に近づけたボット:
##   - 反応の遅れ: 0.1 秒ごとに判断し、決めた動きは delay 秒後(+ 0〜H_JITTER 秒のゆらぎ)に効く(見てから手が動くまで)
##   - ぶれ: err の確率で、いちばん良い動きではなく、上位 3 つのどれかを選ぶ
##   - 自分の当たり判定を引いて、すき間を測る。H_HORIZON 秒先まで 4 点で読む
##   - ふだんは全速、低速のほうがすき間が広いときだけ低速(Shift)
## calib: 保存されたリプレイ(使う人のプレイ)と同じ弾幕を、このボットで走らせ、被弾時間(1 分あたり)を人間と比べる。delay × err の組を総当たり。
##   godot --headless --path . --script tools/difficulty_study.gd -- calib [jobs=14]
## elastic に bots=human hd=<delay> he=<err> を付けると、このボットで効きを測る。
const H_THINK := 0.1
const H_JITTER := 0.06
const H_HORIZON := 0.35
const CALIB_DELAYS := [0.0, 0.05, 0.1, 0.18]
const CALIB_ERRS := [0.0, 0.15, 0.3]
const CALIB_SEEDS := 2
const SongLibrary = preload("res://scripts/song_library.gd")


## リプレイの譜面(md5)→ 曲の場所。dir の .osz と osu! の Songs フォルダ(標準の場所)を、曲の索引(SongLibrary.info。保存された控えを使う)で調べる。
## 子プロセスは、親が作ったこの表(JSON)を読む(全員で 800 曲を調べ直さない)。
func _chart_map(dir: String, want: Dictionary) -> Dictionary:
	var paths: Array = _osz_files(dir)
	paths.append_array(SongLibrary.find_osz())
	var osu := SongLibrary.detect_osu_songs()
	if osu != "":
		for sub in DirAccess.get_directories_at(osu):
			paths.append(osu.path_join(sub))
	var out := {}
	for path in paths:
		if out.size() >= want.size():
			break
		var inf := SongLibrary.info(str(path))
		for md5 in (inf.get("ids", {}) as Dictionary):
			if want.has(md5) and not out.has(md5):
				out[md5] = str(path)
	SongLibrary.save_index()
	return out


func _bot_h(sim, field, rng: RandomNumberGenerator, err: float) -> Array:
	var cands: Array = []   # [score, move, slow]
	var center := GameSim.ARENA * Vector2(0.5, 0.75)
	var pr: float = sim.player_r * 1.0
	for slow in [false, true]:
		var speed: float = GameSim.PLAYER_SLOW if slow else GameSim.PLAYER_SPEED
		for d in DIRS:
			if slow and d == Vector2.ZERO:
				continue
			var gap := 80.0
			for kk in range(1, 5):
				var tt: float = H_HORIZON * float(kk) / 4.0
				var np: Vector2 = (sim.player_pos + d.normalized() * speed * tt) if d != Vector2.ZERO else sim.player_pos
				np = np.clamp(Vector2(12, 12), GameSim.ARENA - Vector2(12, 12))
				for i in range(field.count):
					if field.grace[i] > 0.0:
						continue
					var g: float = (field.pos[i] + field.vel[i] * tt).distance_to(np) - field.rad[i] - pr
					if g < gap:
						gap = g
			var endp: Vector2 = (sim.player_pos + d.normalized() * speed * H_HORIZON) if d != Vector2.ZERO else sim.player_pos
			cands.append([gap * 3.0 - endp.distance_to(center) * 0.02 - (0.5 if slow else 0.0), d, slow])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var pick: Array = cands[0]
	if err > 0.0 and rng.randf() < err:
		pick = cands[rng.randi_range(0, mini(2, cands.size() - 1))]
	return [pick[1], pick[2]]


## 人間に近いボットで、until 秒まで走らせる(練習モード)。被弾時間(秒)を返す。
func _run_human(sim, field, until: float, delay: float, err: float, rng: RandomNumberGenerator) -> float:
	var now := 0.0
	var move := Vector2.ZERO
	var slow := false
	var queue: Array = []   # [効く時刻, move, slow]
	var next_think := 0.0
	var steps := 0
	while not sim.finished and now < until and steps < int((until + 10.0) / DT):
		if now >= next_think:
			next_think = now + H_THINK
			var dec := _bot_h(sim, field, rng, err)
			queue.append([now + delay + rng.randf() * H_JITTER, dec[0], dec[1]])
		while not queue.is_empty() and float(queue[0][0]) <= now:
			var q: Array = queue.pop_front()
			move = q[1]
			slow = q[2]
		sim.step(now, DT, move, slow)
		steps += 1
		now += DT
	return sim.hit_time


func _calib(args: Array) -> void:
	var jobs := 1
	var part := 0
	var parts := 1
	var out := ""
	var dir := "C:/Desktop/my_apps/DDA"
	var map_file := ""
	for a in args:
		var s := str(a)
		if s.begins_with("jobs="):
			jobs = int(s.trim_prefix("jobs="))
		elif s.begins_with("out="):
			out = s.trim_prefix("out=")
		elif s.begins_with("dir="):
			dir = s.trim_prefix("dir=")
		elif s.begins_with("map="):
			map_file = s.trim_prefix("map=")
		elif s.begins_with("part="):
			var kn: PackedStringArray = s.trim_prefix("part=").split("/")
			part = int(kn[0])
			parts = int(kn[1])
	var names: Array = []
	for n in DirAccess.get_files_at(Replay.dir):   # 一覧の控え(index.json)は書き換えない(子が同時に書くと壊れる)
		if str(n).ends_with(".rpl"):
			names.append(str(n))
	names.sort()
	var charts := {}
	if map_file != "":
		var mj = JSON.parse_string(FileAccess.get_file_as_string(map_file))
		charts = mj if mj is Dictionary else {}
	else:
		var want := {}
		for n in names:
			var d0 := Replay.load_file(n)
			if not d0.is_empty():
				want[str(d0.md5)] = true
		charts = _chart_map(dir, want)
		print("calib: 譜面 %d / %d が見つかった" % [charts.size(), want.size()])
	if jobs > 1 and out == "":
		var mf := OS.get_temp_dir().path_join("danmaku_study_charts.json").replace("\\", "/")
		var fw := FileAccess.open(mf, FileAccess.WRITE)
		fw.store_string(JSON.stringify(charts))
		fw.close()
		_calib_report(_parallel(["calib", "map=" + mf], jobs, "cal"))
		return
	var lines: Array = []
	var k := 0
	for n in names:
		k += 1
		if (k - 1) % parts != part:
			continue
		var d := Replay.load_file(n)
		if d.is_empty():
			continue
		var mods: Array = (d.settings as Dictionary).get("mods", [])
		if mods.has("auto") or mods.has("boss") or mods.has("dark") or str(d.get("cond", "")) != "":
			lines.append("cal_skip,%s,MOD" % n)
			continue   # オート・撃破(ボスを追う)・暗闇(見えない)・弾速の実験は、比べられない
		var ch := Replay.open_chart(str(charts[str(d.md5)]), str(d.md5)) if charts.has(str(d.md5)) else {}
		if ch.is_empty():
			lines.append("cal_skip,%s,曲がない" % n)
			continue
		var st: Dictionary = d.stats
		var first := float(st.get("first_fire", 0.0))
		var until := float(st.get("hp_t_end", 0.0))
		var play_min := (until - maxf(first, 0.0)) / 60.0
		if play_min < 0.15:
			lines.append("cal_skip,%s,短い" % n)
			continue   # 短すぎる(すぐ終えた)プレイは使わない
		var human := float(st.get("hit_ms", 0)) / 1000.0 / play_min
		var lv := float(st.get("level", 0.0))
		for delay in CALIB_DELAYS:
			for err in CALIB_ERRS:
				var acc := 0.0
				var ok := true
				for s in range(CALIB_SEEDS):
					var field := BulletField.new()
					var g := Replay.build_game(field, ch.bm, Replay.play_settings(d), "", {}, true)
					if Replay.fingerprint_of(g.sim) != int(d.get("fp", -1)):
						ok = false   # 版が変わって、人が見た弾幕と違う
						field.free()
						break
					var rng := RandomNumberGenerator.new()
					rng.seed = hash("%s|%d" % [n, s])
					acc += _run_human(g.sim, field, until, delay, err, rng) / play_min
					field.free()
				if not ok:
					lines.append("cal_skip,%s,版が違う(%s)" % [n, str(d.get("app", ""))])
					break
				lines.append("cal,%s,%.2f,%s,%.3f,%.2f,%.2f,%.4f,%.4f" % [n, lv, "+".join(mods), play_min, delay, err, human, acc / CALIB_SEEDS])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	else:
		_calib_report(lines)


## 集計: delay × err ごとに、全プレイの被弾時間の合計の比(ボット ÷ 人間。遊んだ長さで重み)と、プレイごとの比の対数の平均・ばらつき。
func _calib_report(lines: Array) -> void:
	for l in lines:
		print(l)
	var agg := {}
	var plays := {}
	for l in lines:
		if str(l).begins_with("cal_skip,"):
			continue
		var c: PackedStringArray = str(l).split(",")
		var key := c[5] + "|" + c[6]
		var a: Array = agg.get(key, [0.0, 0.0, 0.0, 0.0, 0, [], []])
		var w := float(c[4])
		a[0] += float(c[7]) * w
		a[1] += float(c[8]) * w
		var lr := log((float(c[8]) + 0.02) / (float(c[7]) + 0.02))
		a[2] += lr
		a[3] += lr * lr
		a[4] += 1
		(a[5] as Array).append(log(float(c[7]) + 0.02))
		(a[6] as Array).append(log(float(c[8]) + 0.02))
		agg[key] = a
		plays[c[1]] = true
	print("calib_sum: プレイ %d" % plays.size())
	var keys := agg.keys()
	keys.sort()
	for key in keys:
		var a: Array = agg[key]
		var n := maxf(float(a[4]), 1.0)
		var mean := float(a[2]) / n
		print("calib_sum,delay=%s,err=%s,合計の比(ボット/人間) %.2f,比の対数 平均 %.2f ばらつき %.2f,相関 %.2f" % [str(key).split("|")[0], str(key).split("|")[1], float(a[1]) / maxf(float(a[0]), 1e-6), mean, sqrt(maxf(float(a[3]) / n - mean * mean, 0.0)), _corr(a[5], a[6])])


## 相関係数(プレイごとの被弾の多さの順が、人間とボットでどれだけ揃うか。1 に近いほど、どの譜面が難しいかの感じ方が同じ)。
static func _corr(xs: Array, ys: Array) -> float:
	var n := float(xs.size())
	if n < 3:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in range(xs.size()):
		mx += float(xs[i]) / n
		my += float(ys[i]) / n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in range(xs.size()):
		sxy += (float(xs[i]) - mx) * (float(ys[i]) - my)
		sxx += (float(xs[i]) - mx) * (float(xs[i]) - mx)
		syy += (float(ys[i]) - my) * (float(ys[i]) - my)
	return sxy / sqrt(maxf(sxx * syy, 1e-12))


## 自分を jobs 個の子プロセスで起動し(part=k/n out=<ファイル>)、prefix で始まる行を集める。
func _parallel(mode_args: Array, jobs: int, prefix: String) -> Array:
	var exe := OS.get_executable_path()
	var tmp := OS.get_temp_dir().path_join("danmaku_study").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(tmp)
	var pids: Array = []
	var files: Array = []
	var t0 := Time.get_ticks_msec()
	for j in range(jobs):
		var f := tmp.path_join("%s%d.csv" % [str(mode_args[0]), j])
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
		files.append(f)
		var a := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/difficulty_study.gd", "--"]
		a.append_array(mode_args)
		a.append_array(["part=%d/%d" % [j, jobs], "out=" + f])
		pids.append(OS.create_process(exe, a))
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
				if l.begins_with(prefix):
					lines.append(l)
	print("%s: %d 本の結果(%d 並列、%.0f 秒)" % [str(mode_args[0]), lines.size(), jobs, (Time.get_ticks_msec() - t0) / 1000.0])
	return lines


# --- SIZE_EXP を変えたときの Lv の変化(sizeexp) ---
## 全譜面(弾幕 v2)で、いまの SIZE_EXP と exp の 2 通りを比べる:
##   ① 同じ弾幕のまま測り直した Lv(表示が変わる量)。MOD「地獄」(弾サイズ ×1.35)・「巨人」(自機 ×2)・「天国」(弾サイズ ×0.7)を付けたときも
##   ② exp で弾幕を作り直したとき: Lv(目標に合わせるので、ほぼ同じ)と、弾の数・弾サイズの変化(実際に遊ぶ弾幕が変わる量)
##   godot --headless --path . --script tools/difficulty_study.gd -- sizeexp [exp=1.3] [jobs=14] [dir=<osz のフォルダ>]
func _sizeexp(args: Array) -> void:
	var dir := "C:/Desktop/my_apps/DDA"
	var e1 := 1.3
	var jobs := 1
	var part := 0
	var parts := 1
	var out := ""
	for a in args:
		var s := str(a)
		if s.begins_with("dir="):
			dir = s.trim_prefix("dir=")
		elif s.begins_with("exp="):
			e1 = float(s.trim_prefix("exp="))
		elif s.begins_with("jobs="):
			jobs = int(s.trim_prefix("jobs="))
		elif s.begins_with("out="):
			out = s.trim_prefix("out=")
		elif s.begins_with("part="):
			var kn: PackedStringArray = s.trim_prefix("part=").split("/")
			part = int(kn[0])
			parts = int(kn[1])
	if jobs > 1 and out == "":
		_sizeexp_report(_parallel(["sizeexp", "dir=" + dir, "exp=%f" % e1], jobs, "sx,"), e1)
		return
	var e0 := PatternGen.SIZE_EXP_LEGACY
	var mods := {"hell": Mods.params(["hell"]), "giant": Mods.params(["giant"]), "heaven": Mods.params(["heaven"])}
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
			var gen := PatternGenV2.generate(bm, {"size_exp": e0})
			var lv0 := float(gen.level)
			var m0 := {}
			for id in mods:
				m0[id] = float(Mods.apply(gen, mods[id]).level)
			var lv1 := _relevel(gen, e1)   # ① 同じ弾幕を、新しい指数で測り直す
			var gen_e1 := gen.duplicate()
			gen_e1["size_exp"] = e1
			var m1 := {}
			for id in mods:
				m1[id] = float(Mods.apply(gen_e1, mods[id]).level)
			var gen2 := PatternGenV2.generate(bm, {"size_exp": e1})   # ② 新しい指数で作り直す
			lines.append("sx,%s,%s,%.2f,%.3f,%.2f,%.2f,%.2f,%d,%d,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [str(path).get_file().substr(0, 14).replace(",", " "), str(bm.version).replace(",", " "),
				float(gen.stars), float(gen.size) / (6.75 * PatternGenV2.V2_SIZE_MUL), lv0, lv1, float(gen2.level), _shots(gen), _shots(gen2), float(gen2.size) / maxf(float(gen.size), 0.001),
				m0.hell, m1.hell, m0.giant, m1.giant, m0.heaven, m1.heaven])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	else:
		_sizeexp_report(lines, e1)


## 同じ弾幕の Lv を、指数 sexp で測り直す(Mods.apply の最後と同じ式)。
func _relevel(gen: Dictionary, sexp: float) -> float:
	var rating := PatternGen.measure(gen.events, gen.get("breaks", []), float(gen.size) if bool(gen.get("size_weight", false)) else 0.0, sexp)
	return PatternGen.level_of(rating.score, float(gen.speed), float(gen.size), PatternGen.PLAYER_HIT_R, rating.duration, float(gen.get("speed_ref", PatternGen.BASE_SPEED)), gen.get("table", PatternGen.TARGET_TABLE), sexp)


func _shots(gen: Dictionary) -> int:
	var n := 0
	for e in gen.events:
		for s in e.shots:
			n += int(s.n)
	return n


func _sizeexp_report(lines: Array, e1: float) -> void:
	print("sx,set,version,stars,size(基準比),lv(いま),lv(測り直し),lv(作り直し),弾数(いま),弾数(作り直し),弾サイズ(作り直し/いま),地獄(いま),地獄(新),巨人(いま),巨人(新),天国(いま),天国(新)")
	var rows: Array = []
	for l in lines:
		print(l)
		rows.append(str(l).split(","))
	rows.sort_custom(func(a, b): return float(a[4]) < float(b[4]))
	var n := float(rows.size())
	if n == 0:
		return
	var sum_d := 0.0
	var sum_ad := 0.0
	var max_up := -99.0
	var max_dn := 99.0
	var cnt := 0.0
	var gsz := 0.0
	var dm := {"hell": 0.0, "giant": 0.0, "heaven": 0.0}
	for r in rows:
		var d := float(r[6]) - float(r[5])
		sum_d += d
		sum_ad += absf(d)
		max_up = maxf(max_up, d)
		max_dn = minf(max_dn, d)
		cnt += log(float(r[9]) / maxf(float(r[8]), 1.0))
		gsz += log(float(r[10]))
		dm.hell += (float(r[12]) - float(r[6])) - (float(r[11]) - float(r[5]))
		dm.giant += (float(r[14]) - float(r[6])) - (float(r[13]) - float(r[5]))
		dm.heaven += (float(r[16]) - float(r[6])) - (float(r[15]) - float(r[5]))
	print("sx_sum: 譜面 %d、SIZE_EXP %.2f → %.2f" % [rows.size(), PatternGen.SIZE_EXP_LEGACY, e1])
	print("sx_sum: ① 同じ弾幕の Lv の変化: 平均 %+.2f、絶対値の平均 %.2f、最大 %+.2f / 最小 %+.2f" % [sum_d / n, sum_ad / n, max_up, max_dn])
	print("sx_sum: ② 作り直したとき: 弾数 ×%.3f(幾何平均)、弾サイズ ×%.3f" % [exp(cnt / n), exp(gsz / n)])
	print("sx_sum: MOD を付けたときの Lv の上がり幅の変化(新 − いま、平均): 地獄 %+.2f / 巨人 %+.2f / 天国 %+.2f" % [dm.hell / n, dm.giant / n, dm.heaven / n])
	# 弾サイズの大きさ別(基準比)の、① の変化
	for b in [[0.0, 0.9], [0.9, 1.1], [1.1, 9.0]]:
		var s := 0.0
		var c := 0
		for r in rows:
			if float(r[4]) >= float(b[0]) and float(r[4]) < float(b[1]):
				s += float(r[6]) - float(r[5])
				c += 1
		if c > 0:
			print("sx_sum: 弾サイズ(基準比)%.1f〜%.1f の譜面 %d: ① の平均 %+.2f" % [b[0], minf(b[1], 9.0), c, s / c])
