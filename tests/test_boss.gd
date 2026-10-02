extends SceneTree
## 小型化・撃破 MOD の単体テスト。
## godot --headless --path . --script tests/test_boss.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Boss = preload("res://scripts/game/boss.gd")
const Mods = preload("res://scripts/mods.gd")

const DT := 0.005

var _fail := 0
var _fields: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var reol := OszLoader.new()
	reol.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var laur := OszLoader.new()
	laur.open("C:/Desktop/my_apps/DDA/813569 Laur - Sound Chimera.osz")
	var easy = null
	var hard = null
	for bm in reol.difficulties:
		if bm.version == "Irre's Beginner":
			easy = bm
	for bm in laur.difficulties:
		if bm.version == "Chimera":
			hard = bm
	var ge := PatternGen.generate(easy)
	var gh := PatternGen.generate(hard)
	_test_mods()
	_test_shrink(gh)
	_test_path(gh)
	_test_loop(ge)
	_test_items(ge)
	for pair in [["入門", ge], ["Chimera", gh]]:
		_test_battle(pair[0], pair[1], [])
		_test_battle(pair[0], pair[1], ["shrink"])
	for f in _fields:
		f.free()
	print("test_boss: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


func _sim(gen: Dictionary, ids: Array) -> GameSim:
	var p := Mods.params(ids)
	var g := Mods.apply(gen, p)
	var f := BulletField.new()
	_fields.append(f)
	var sim := GameSim.new()
	sim.setup(f, g, _last_t(g) + 2.0, false, p)
	return sim


func _last_t(g: Dictionary) -> float:
	var end_t := 0.0
	for e in g.events:
		end_t = maxf(end_t, float(e.t))
	return end_t


func _test_mods() -> void:
	var p := Mods.params(["shrink", "boss"])
	_check(is_equal_approx(p.field_scale, 0.5) and p.boss, "小型化・撃破の効果が合成される")
	_check(Mods.multi_ok(["boss", "shrink", "dark"]) == ["shrink", "dark"], "マルチプレイでは撃破だけを外す")
	var g := Mods.apply({"events": [], "gizmos": [], "level": 3.0}, p)
	_check(is_equal_approx(float(g.level), 3.0), "弾幕を変えない MOD なので Lv はそのまま")


func _test_shrink(gen: Dictionary) -> void:
	var sim := _sim(gen, ["shrink"])
	var r: Rect2 = sim.move_rect
	_check(r.position.is_equal_approx(Vector2(240, 180)) and r.size.is_equal_approx(Vector2(480, 360)), "動ける範囲は中央の縦横 50%")
	_check(r.has_point(sim.player_pos), "開始位置は範囲の中 %s" % str(sim.player_pos))
	var ok := true
	var t := 0.0
	for dir in [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2(-1, -1)]:
		for i in range(300):
			sim.step(t, 0.01, dir, false)
			t += 0.01
			ok = ok and r.has_point(sim.player_pos)
	_check(ok, "どの方向へ動かし続けても範囲の外へ出ない")
	var full := _sim(gen, [])
	_check(full.player_pos.is_equal_approx(Vector2(480, 612)), "MOD なしの開始位置は今までどおり")
	# 危険エリアのマスは、動ける範囲を 3×3 に分けたもの
	_check(sim.cell_of(r.position + Vector2(2, 2)) == 0 and sim.cell_of(r.end - Vector2(2, 2)) == 8 and sim.cell_of(r.get_center()) == 4
		and sim.cell_rect(4).get_center().is_equal_approx(r.get_center()) and sim.cell_rect(8).end.is_equal_approx(r.end),
		"小型化: 危険エリアのマスは、動ける範囲を 3×3 に分けたもの")
	_check(full.cell_of(Vector2(700, 100)) == GameSim.zone_cell(Vector2(700, 100)), "MOD なしのマスは今までどおり")
	# 小型化のマスの中にいると、そのマスのデバフを受ける
	var s2 := _sim(gen, ["shrink"])
	var z: Dictionary = {}
	for zz in gen.zones:   # 休憩地帯と重ならない回(休憩中はデバフが効かない)
		if not s2.in_break((float(zz.t) + float(zz.end)) * 0.5) and z.is_empty() and float(zz.t) > 30.0:
			z = zz
	var c: Dictionary = z.cells[0]
	var tz := (float(z.t) + float(z.end)) * 0.5
	s2.player_pos = s2.cell_rect(int(c.c)).get_center()
	s2._update_zone_debuff(tz)
	_check(s2.zone_debuff == str(c.type), "小型化: 範囲の中のマス %d にいると、デバフ %s を受ける(%s)" % [int(c.c), str(c.type), s2.zone_debuff])
	var sb := _sim(gen, ["boss"])
	_check(sb.zones.is_empty() and not gen.zones.is_empty(), "撃破: 危険エリアは出ない")


func _test_path(gen: Dictionary) -> void:
	var sim := _sim(gen, ["boss"])
	var b = sim.boss
	var worst := 0.0
	var n := 0
	for e in gen.events:
		if e.shots.is_empty():
			continue
		var inside := false
		for g in gen.gizmos:
			if float(e.t) >= float(g.t) and float(e.t) <= float(g.end):
				inside = g.kind == "spinner"
		if inside:
			continue
		worst = maxf(worst, b.target_at(float(e.t)).distance_to(e.pos))
		n += 1
	_check(n > 100 and worst < 1.0, "ボスの目標(オートの動き)は、弾を撃つ時刻にその発射位置(%d 発・最大のずれ %.2f px)" % [n, worst])
	var sl := 0
	var sl_worst := 0.0
	for g in gen.gizmos:
		if g.kind != "slider":
			continue
		var tm := lerpf(float(g.t), float(g.end), 0.37)
		sl_worst = maxf(sl_worst, b.target_at(tm).distance_to(GameSim.slider_emitter(g, tm)))
		sl += 1
	_check(sl > 0 and sl_worst < 0.01, "目標は、スライダーの途中は軌道の上(%d 本)" % sl)
	# 登場: 盤面の上の外から降りてくる
	var first: Vector2 = b.pos_at(float(sim.first_fire_time))
	_check(b.pos_at(b.appear_t - 0.5).y < -Boss.BOSS_R and b.pos_at(b.appear_t + Boss.ENTER_TIME * 0.5).y < first.y
		and b.pos_at(b.appear_t + Boss.ENTER_TIME).distance_to(first) < 1.0 and b.appear_t < sim.first_fire_time,
		"ボスは盤面の上の外から、最初の発射位置へ降りてくる")
	# 登場のあとは、最高速度を超えない(目標が速すぎるところでは遅れる)
	var top := 0.0
	var lag := 0.0
	var prev: Vector2 = b.pos_at(b.appear_t + Boss.ENTER_TIME)
	var t: float = b.appear_t + Boss.ENTER_TIME
	while t < float(sim._last_fire):
		t += 0.01
		var q: Vector2 = b.pos_at(t)
		top = maxf(top, q.distance_to(prev) / 0.01)
		lag = maxf(lag, q.distance_to(b.target_at(t)))
		prev = q
	_check(top <= Boss.MAX_SPEED * 1.01 and lag > 50.0, "ボスは最高速度 %.0f px/s を超えない(最大 %.0f px/s・目標からの遅れ 最大 %.0f px)" % [Boss.MAX_SPEED, top, lag])


## 撃破: 曲(弾幕)を繰り返し、倒すまで終わらない。2 周目以降も、ボスは発射位置にいる。
func _test_loop(gen: Dictionary) -> void:
	var sim := _sim(gen, ["boss"])
	var L: float = sim.loop_len
	_check(is_equal_approx(L, sim.loop_end - sim.loop_from + Boss.BONUS_TIME) and is_equal_approx(sim.loop_from, sim.first_fire_time - GameSim.LOOP_LEAD),
		"1 周 = 最初のノーツの %.0f 秒前 〜 最後のノーツ + ボーナスタイム %.0f 秒(%.1f 秒)" % [GameSim.LOOP_LEAD, Boss.BONUS_TIME, L])
	sim.debug_invincible = true
	var base_n: int = gen.events.size()
	var t := -1.0
	var score_l1 := 0.0
	while t < L * 2.5:
		sim.step(t, 0.01, Vector2.ZERO, false)
		sim.gauge = 1.0
		if score_l1 == 0.0 and t >= L * 1.2:
			score_l1 = sim.score
		t += 0.01
	# スコア: 進行率はボスに与えたダメージの割合なので、1 周を過ぎても伸びる
	_check(sim.score > score_l1 and score_l1 > 0.0 and is_equal_approx(sim.score_progress, 1.0 - sim.boss.hp / sim.boss.max_hp)
		and is_equal_approx(sim.damage_tau, GameSim.DAMAGE_TAU * Boss.HP_CHASE_SECONDS / GameSim.DAMAGE_REF_TIME),
		"スコアは 1 周を過ぎても、ボスを削るほど伸びる(1.2 周 %.0f → 2.5 周 %.0f。被ダメージ係数の時定数 %.1f)" % [score_l1, sim.score, sim.damage_tau])
	_check(not sim.finished and not sim.failed, "倒すまで、曲の最後を過ぎても終わらない(%.0f 秒 = %.1f 周)" % [t, t / L])
	_check(sim.events.size() >= base_n * 3 and sim._ev_idx > base_n * 2, "弾幕を周ごとに足して、撃ち続ける(%d 件・撃った %d 件)" % [sim.events.size(), sim._ev_idx])
	_check(gen.events.size() == base_n, "元の弾幕(選曲画面が覚えているもの)は書き換えない")
	var worst := 0.0
	for k in [1, 2]:
		for e in gen.events:
			if e.shots.is_empty():
				continue
			var inside := false
			for g in gen.gizmos:
				if float(e.t) >= float(g.t) and float(e.t) <= float(g.end):
					inside = true
			if not inside:
				worst = maxf(worst, sim.boss.target_at(float(e.t) + L * k).distance_to(e.pos))
	_check(worst < 1.0, "2・3 周目も、ボスの目標は発射位置(最大のずれ %.2f px)" % worst)
	# ボーナスタイム: 最後のノーツのあとの 3 秒は、弾が来ず、ボスの目標は止まる
	var b0: float = sim.loop_end + L
	var no_fire := true
	for e in sim.events:
		if float(e.t) > b0 + 0.001 and float(e.t) < b0 + Boss.BONUS_TIME and not e.shots.is_empty():
			no_fire = false
	_check(no_fire and absf(sim.bonus_left(b0 + 1.0) - (Boss.BONUS_TIME - 1.0)) < 0.001 and sim.bonus_left(b0 - 0.5) < 0.0 and sim.bonus_left(b0 + Boss.BONUS_TIME + 0.1) < 0.0
		and sim.boss.target_at(b0 + 0.2).distance_to(sim.boss.target_at(b0 + Boss.BONUS_TIME - 0.01)) < 0.01 and sim.loop_index(b0 + 1.0) == 1 and sim.loop_index(b0 + Boss.BONUS_TIME + 0.1) == 2,
		"ボーナスタイム(%.0f 秒): 弾が来ず、ボスの目標は止まり、そのあと次の周" % Boss.BONUS_TIME)
	var br_ok := true
	for b in gen.get("breaks", []):
		br_ok = br_ok and sim.in_break(float(b[0]) + L + 0.01) and sim.in_break(float(b[1]) + 2.0 * L - 0.01)
	_check(br_ok, "休憩地帯も周ごとに繰り返す")


func _test_items(gen: Dictionary) -> void:
	var a := _item_run()
	var b := _item_run()
	_check(a == b, "同じ弾幕なら、アイテムの出方は同じ")
	_check(a.contains("power") and a.contains("rate") and a.contains("wide") and a.contains("heal") and a.contains("bomb"), "5 種類のアイテムが出る")
	var boss := Boss.new()
	boss.setup([], [], [], Rect2(240, 180, 480, 360), 0.0, 100.0)
	for k in ["power", "rate", "wide"]:
		for i in range(6):
			boss.items.append({"kind": k, "p": Vector2(480, 400), "v": Vector2.ZERO, "t": 0.0})
	boss._update_items(0.0, 0.01, Vector2(480, 400))
	_check(boss.power == 4 and is_equal_approx(boss.power_mul, 2.0) and boss.rate_lv == 3 and boss.wide_lv == 2,
		"触れると強化され、上限で止まる(攻撃 %d 段・連射 %d 段・ワイド %d 段)" % [boss.power, boss.rate_lv, boss.wide_lv])
	_check(is_equal_approx(boss.fire_interval(), Boss.FIRE_INTERVAL / 1.75), "連射の最大で、間隔は 1/1.75")
	boss.items.clear()
	var none := true
	for i in range(400):
		var kd := boss._pick_kind()
		none = none and not ["power", "rate", "wide"].has(kd)
	_check(none, "上限に届いた強化は、もう落とさない")
	# 回復・ボムは GameSim が反映する
	var sim := _sim(gen, ["boss"])
	sim.gauge = 0.5
	sim.field.add(Vector2(100, 100), Vector2(0, 1), 5.0, 0)
	sim.boss.apply_item("heal", sim.player_pos, 0.0)
	sim.boss.apply_item("bomb", sim.player_pos, 0.0)
	sim.step(0.0, 0.001, Vector2.ZERO, false)
	_check(sim.gauge >= 0.5 + Boss.HEAL_AMOUNT - 0.01 and sim.field.count == 0, "回復でゲージが増え、ボムで弾が消える(ゲージ %.2f・弾 %d)" % [sim.gauge, sim.field.count])
	# ボスに当てると回復する(速さは毎秒 HIT_HEAL_MAX まで)。当てない自機は自然回復だけ
	var gains := []
	for hit_on in [true, false]:
		var hs := _sim(gen, ["boss"])
		hs.debug_invincible = true
		hs.boss.hp = 1e9
		hs.boss.wide_lv = 2
		hs.boss.rate_lv = 3
		var t := float(hs.first_fire_time) + 5.0
		var g0 := 0.4
		hs.gauge = g0
		for k in range(1000):
			hs.player_pos = (hs.boss.pos_at(t) + Vector2(0, 150)) if hit_on else Vector2(20, 700)
			hs.step(t, 0.001, Vector2.ZERO, false)
			t += 0.001
		gains.append(hs.gauge - g0)
	_check(gains[0] > gains[1] + GameSim.HIT_HEAL_MAX * 0.5 and gains[0] <= gains[1] + GameSim.HIT_HEAL_MAX + 0.002,
		"ボスに当てると回復する(1 秒で 当てた +%.1f%% / 当てない +%.1f%%。差は毎秒 %.0f%% まで)" % [gains[0] * 100.0, gains[1] * 100.0, GameSim.HIT_HEAL_MAX * 100.0])
	var it := Boss.new()
	it.setup([], [], [], Rect2(240, 180, 480, 360), 0.0, 100.0)
	it.items.append({"kind": "power", "p": Vector2(60, 200), "v": Vector2(0, -Boss.ITEM_POP), "t": 0.0})
	var reached := false
	for k in range(400):
		it._update_items(0.0, 0.01, Vector2(-999, -999))
		if it.items.is_empty():
			break
		var p: Vector2 = it.items[0].p
		if p.y < 540.0 and p.x >= 240.0 and p.x <= 720.0:
			reached = true
	_check(reached, "範囲の外に落ちたアイテムも、範囲の下端より上で横幅の中へ寄る")


## ボスを真下から撃ち続けて、出たアイテムの種類を記録する(アイテムは取らない)。
func _item_run() -> String:
	var boss := Boss.new()
	var ev: Array = [{"t": 0.0, "pos": Vector2(480, 100), "shots": [{}]}, {"t": 600.0, "pos": Vector2(480, 100), "shots": [{}]}]
	boss.setup(ev, [], [], Rect2(0, 0, 960, 720), 0.0, 600.0)
	boss.hp = 1e9
	var t := 0.0
	var log := ""
	for k in range(60000):
		boss.update(t, 0.005, Vector2(480, 600), false)
		t += 0.005
		for it in boss.items:
			if not it.has("seen"):
				it["seen"] = true
				log += str(it.kind) + ","
	return log + "_" + str(boss.hp)


## 撃破: 弾を気にせずボスの下を追いかける自機(無敵・アイテムを拾う)なら倒せて、倒すとクリアになる。
## HP の見積もり(Boss.ref_hits)が、実際に追いかけた自機の命中数(1 周目・アイテムなし)と大きくずれないことも確かめる。
func _test_battle(label: String, gen: Dictionary, extra: Array) -> void:
	var name := "+".join(extra) if not extra.is_empty() else "全体"
	var res := []
	for endless in [true, false]:
		var sim := _sim(gen, ["boss"] + extra)
		sim.debug_invincible = true
		var b = sim.boss
		if endless:
			b.hp = 1e9
		var t := -1.0
		var r: Rect2 = sim.move_rect
		var limit: float = (sim.loop_end + Boss.BONUS_TIME) if endless else 1800.0   # 見積もりと同じく、1 周目のボーナスタイムの終わりまで
		while not sim.finished and t < limit:
			var target := Vector2(b.pos.x, clampf(b.pos.y + Boss.CHASE_BELOW, r.position.y, r.end.y))
			var d: Vector2 = target - sim.player_pos
			sim.step(t, DT, d if d.length() > 4.0 else Vector2.ZERO, false)
			sim.gauge = 1.0   # 無敵でも毒のエリアでは減るので、満タンに保つ
			if endless:   # 見積もりと比べるので、強化なし
				b.power = 0
				b.power_mul = 1.0
				b.rate_lv = 0
				b.wide_lv = 0
			t += DT
		res.append([sim, b, t])
	var est: float = res[0][1].ref_hits
	var got: int = res[0][1].hits_total
	# 見積もりは、実際に追いかけた自機より 1〜3 割ほど多め(= HP が少し多め)。ボスが最高速度で動くようになって、追いかけ方のわずかな違いが効く
	_check(got > est * 0.7 and got < est * 1.25, "%s %s: HP の見積もりが、追いかけた自機の命中数に近い(見積もり %.0f 発・実際 %d 発)" % [label, name, est, got])
	var sim: GameSim = res[1][0]
	var b = res[1][1]
	var fight := float(b.defeat_t) - float(sim.first_fire_time)
	print("  %s %s: HP %.0f(追いかけて %.1f 発/秒)・撃破 %s(%.0f 秒・%.1f 周)・強化 攻撃 %d / 連射 %d / ワイド %d" % [label, name, b.max_hp, b.ref_rate,
		"済" if b.defeated else "できず", fight, fight / maxf(float(sim.loop_len), 1.0), b.power, b.rate_lv, b.wide_lv])
	_check(b.defeated and fight > 30.0 and fight < Boss.HP_CHASE_SECONDS * 1.3, "%s %s: 追いかける自機なら倒せる(%.0f 秒)" % [label, name, fight])
	var want_bonus := GameSim.SCORE_BOSS_TIME * exp(-fight / GameSim.BOSS_TIME_TAU)
	_check(absf(sim.score_boss_time - want_bonus) < 1.0 and absf(sim.score - (sim.score_base + sim.score_graze + sim.score_boss_time) * sim.damage_factor) < 1.0,
		"%s %s: 撃破タイムボーナス %.0f 点(%.0f 秒)が、最終点に入る" % [label, name, sim.score_boss_time, fight])
	_check(sim.finished and not sim.failed and is_equal_approx(sim.score_progress, 1.0) and sim.field.count == 0
		and absf(float(res[1][2]) - float(b.defeat_t) - GameSim.BOSS_CLEAR_DELAY) < 0.05,
		"%s %s: 倒すと弾が消え、%.1f 秒後にクリア" % [label, name, GameSim.BOSS_CLEAR_DELAY])
