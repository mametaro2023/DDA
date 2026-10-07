extends SceneTree
## サバイバル(docs/survival_plan.md)の要点のテスト: 曲の選び方 / 点の合計 / ゲージの持ち越し / 3 択 / 身代わり。
## godot --headless --path . --script tests/test_survival.gd

const SurvivalRun = preload("res://scripts/survival/survival_run.gd")
const SurvivalPicker = preload("res://scripts/survival/survival_picker.gd")
const Upgrades = preload("res://scripts/survival/upgrades.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Enemies = preload("res://scripts/game/enemies.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _chart(title: String, lv: float, len_s := 120.0) -> Dictionary:
	return {"path": "p/" + title, "md5": title + str(lv), "title": title, "artist": "a", "version": "v", "key": SurvivalPicker.song_key(title, "a"), "lv": lv, "len": len_s, "bg": ""}


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# --- 曲の選び方 ---
	var charts := [_chart("A", 3.0), _chart("B", 3.9), _chart("B", 4.1), _chart("C", 4.2), _chart("D", 5.0), _chart("E", 4.0, 400.0)]
	var used := {}
	var ok_window := true
	for i in range(20):
		var pk := SurvivalPicker.pick(charts, 4.0, [], used, rng)
		ok_window = ok_window and absf(float(pk.est) - 4.0) <= 0.3 and str(pk.chart.title) != "E"
	_check(ok_window, "目標の ±0.3 に入る譜面を選ぶ(3 分を超える曲は、近くにあっても出さない)")
	used = {SurvivalPicker.song_key("B", "a"): 1, SurvivalPicker.song_key("C", "a"): 1}
	var pk2 := SurvivalPicker.pick(charts, 4.0, [], used, rng)
	_check(str(pk2.chart.title) == "D" or str(pk2.chart.title) == "A", "出した曲(難易度違いも)は出さず、幅を広げて選ぶ(%s)" % pk2.chart.title)
	used = {}
	for c in charts:
		used[c.key] = 1
	var pk3 := SurvivalPicker.pick(charts, 4.0, [], used, rng)
	_check(pk3.extra_mods == ["rush"] and absf(float(pk3.est) - 4.0) < 0.6, "使い切ったら、出た曲を加速付きでもう一度(Lv %.2f)" % float(pk3.est))
	var pk4 := SurvivalPicker.pick(charts, 6.2, ["storm"], {}, rng)
	_check(absf(float(pk4.est) - 6.2) <= 0.3 and absf(float(pk4.chart.lv) * 1.56 - float(pk4.est)) < 0.001, "MOD を付けたら、Lv の見積もりで選ぶ(暴風雨: MOD なし %.2f → %.2f)" % [float(pk4.chart.lv), float(pk4.est)])

	# --- 点・ゲージの持ち越し ---
	var run := SurvivalRun.new()
	run.start(4.0, ["practice", "boss", "hell"], 123)
	_check(run.mod_ids == ["hell"], "練習・撃破は付けられない")
	_check(is_equal_approx(run.target_level(), 4.0), "1 曲目の目標は開始の Lv")
	var e1 := run.song_done({"failed": false, "score": 900000.0, "level": 4.0, "hp_end": 0.5, "title": "A", "xp_got": 25.0})
	_check(is_equal_approx(e1.points, 900000.0) and is_equal_approx(run.total, 900000.0), "Lv 4 の曲は f = 1(点はそのまま)")
	_check(is_equal_approx(run.gauge, 0.85) and run.picks == 1, "ゲージは持ち越して、曲の間に 35%% 回復(%.2f)。経験値 25 でレベル 1 → 3 択が 1 回" % run.gauge)
	run.levels["max_gauge"] = 2   # 体力の上限 1.3: 上限が増えても、いまの体力(絶対量)は増えない
	var gp := run.game_params()
	_check(is_equal_approx(float(gp.drain_mul), 1.3) and is_equal_approx(float(gp.gauge), 0.85 / 1.3) and is_equal_approx(float(gp.regen), 0.0025), "最大ゲージ: 上限だけ増え、いまの体力・自然回復(毎秒 0.25%)は絶対量のまま")
	run.levels.erase("max_gauge")
	_check(is_equal_approx(run.target_level(), 4.3), "2 曲目の目標は +0.3")
	run.choose("bet")
	_check(is_equal_approx(run.target_level(), 4.8), "背水で、次の曲の目標が +0.5")
	_check(float(run.game_params().xp_mul) == 2.0, "背水: 次の曲の経験値は 2 倍")
	run.song_done({"failed": false, "score": 800000.0, "level": 6.0, "hp_end": 0.9, "xp_got": 10.0})
	_check(run.picks == 0 and run.xp_level == 1, "経験値が足りなければ、レベルは上がらず 3 択もない(通算 %.0f・レベル %d)" % [run.xp, run.xp_level])
	_check(is_equal_approx(run.total, 900000.0 + 800000.0 * 2.25), "Lv 6 は f = (6/4)^2 = 2.25")
	_check(is_equal_approx(run.gauge, 1.0) and is_equal_approx(run.target_level(), 4.6), "回復は満タンまで / 背水は 1 曲だけ")
	run.choose("between_heal")
	run.song_done({"failed": true, "score": 0.0, "fail_score": 400000.0, "level": 4.0, "hp_end": 0.0})
	_check(run.over and is_equal_approx(run.total, 900000.0 + 1800000.0 + 400000.0), "倒れた曲は、倒れる直前の点を数えて終わる")
	_check(run.cleared() == 2 and is_equal_approx(run.best_level(), 6.0), "クリアした曲数・届いた Lv")

	# --- 経験値とレベル ---
	_check(SurvivalRun.level_for_xp(19.9) == 0 and SurvivalRun.level_for_xp(20.0) == 1 and SurvivalRun.level_for_xp(52.0) == 2 and SurvivalRun.level_for_xp(51.0) == 1, "レベル: 20 で 1、20 + 32 = 52 で 2")
	var r3 := SurvivalRun.new()
	r3.start(4.0, [], 9)
	r3.song_done({"failed": false, "score": 1.0, "level": 4.0, "hp_end": 1.0, "xp_got": 60.0})
	_check(r3.picks == 2 and r3.xp_level == 2, "1 曲で 2 つレベルが上がれば、3 択が 2 回")

	# --- 雑魚・自機の弾・経験値の玉(enemies.gd)---
	var shot0 := {"n": 1, "speed": 0.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	var evs: Array = []
	for k in range(60):
		evs.append({"t": 1.0 + k * 1.0, "pos": Vector2(480, 200), "warn": false, "shots": [shot0], "sfx": ""})
	var plan_a := Enemies.make_plan(evs, [], [], 1.0, 60.0)
	var plan_b := Enemies.make_plan(evs, [], [], 1.0, 60.0)
	_check(plan_a.size() >= 34 and plan_a.size() <= 42 and str(plan_a) == str(plan_b), "雑魚の予定: 1 分に 40 体くらい(%d 体)。同じ譜面なら同じ" % plan_a.size())
	_check(Enemies.make_plan(evs, [], [[10.0, 30.0]], 1.0, 60.0).all(func(s): return float(s.t) < 10.0 or float(s.t) > 30.0), "休憩地帯には出ない")
	var en := Enemies.new()
	en.setup(evs, [], [], Rect2(Vector2.ZERO, PatternGen.ARENA), 1.0, 60.0, {"xp_mul": 1.0})
	var ppos := Vector2(480, 640)
	var tn := 0.0
	var first_kill := -1.0
	while tn < 30.0:
		if not en.enemies.is_empty():   # いちばん古い雑魚の真下へ動く(ボット)
			ppos.x = move_toward(ppos.x, float(en.enemies[0].p.x), 380.0 / 1000.0)
		en.update(tn, 0.001, ppos, false)
		if en.kills > 0 and first_kill < 0.0:
			first_kill = tn
		tn += 0.001
	_check(en.kills >= 5 and en.xp_got >= 5.0, "真下を追うと雑魚を倒せて、落ちた玉を取って経験値が入る(30 秒で %d 体・経験値 %.0f)" % [en.kills, en.xp_got])
	var en2 := Enemies.new()
	en2.setup(evs, [], [], Rect2(Vector2.ZERO, PatternGen.ARENA), 1.0, 60.0, {"xp_mul": 2.0, "power": 4})
	en2.enemies.append({"id": 0, "kind": "normal", "hp": 1.0, "max_hp": 1.0, "t0": 0.0, "t1": 99.0, "p": Vector2(100, 100), "home": Vector2(100, 100), "g": null, "flash": 0.0, "leaving_t": -1.0, "seed": 0.0})
	en2._on_hit(0, 0.0)
	en2.sweep()
	_check(en2.kills == 1 and is_equal_approx(en2.xp_got, 2.0), "曲を終えたら、落ちている玉はすべて取ったことになる(経験値 2 倍で %.0f)" % en2.xp_got)

	# --- ボスの曲(S3) ---
	_check(SurvivalRun.is_boss_song(5) and SurvivalRun.is_boss_song(10) and not SurvivalRun.is_boss_song(4) and not SurvivalRun.is_boss_song(0), "5 曲ごとにボスの曲")
	var rb := SurvivalRun.new()
	rb.start(4.0, [], 11)
	rb.song_done({"failed": false, "score": 1.0, "level": 4.0, "hp_end": 1.0, "xp_got": 0.0, "boss": {"defeated": true}})
	_check(rb.picks == 2 and rb.bonus_picks == 1 and is_equal_approx(rb.xp, SurvivalRun.BOSS_XP), "ボスを倒すと、経験値 %d(レベルが上がる)と、ごほうびの 3 択が 1 回" % int(SurvivalRun.BOSS_XP))
	_check(rb.roll_choices().size() == 4, "ごほうびの回は 4 つから選ぶ")
	rb.choose(str(rb.roll_choices()[0]))
	_check(rb.bonus_picks == 0 and rb.picks == 1 and rb.roll_choices().size() == 3, "ごほうびを選んだら、残りはふつうの 3 択")
	var rf := SurvivalRun.new()
	rf.start(4.0, [], 12)
	var ef := rf.song_done({"failed": false, "score": 1.0, "level": 4.0, "hp_end": 1.0, "xp_got": 0.0, "boss": {"defeated": false}})
	_check(rf.picks == 0 and rf.bonus_picks == 0 and str(ef.boss) == "fled" and not rf.over, "倒せなければ、ボスは逃げる(ごほうびなし・ゲームオーバーではない)")
	var bevs: Array = []
	for k in range(30):
		bevs.append({"t": 2.0 + k * 1.0, "pos": Vector2(300.0 + 12.0 * k, 200.0), "warn": false, "shots": [shot0], "sfx": ""})
	var fb := BulletField.new()
	var sb := GameSim.new()
	sb.setup(fb, {"events": bevs, "gizmos": [], "warn_lead": 0.6, "breaks": []}, 40.0, false, {})
	sb.setup_boss_once(0.6, 1.0, {"power": 2})
	sb.debug_invincible = true
	_check(sb.boss != null and sb.boss_once and sb.loop_len == 0.0 and sb.boss.power == 2 and sb.boss.max_hp > 0.0, "ボスの曲: 1 周だけ・強化が弾に効く(HP %.0f)" % (sb.boss.max_hp if sb.boss != null else -1.0))
	var tb := 0.0
	while not sb.finished and tb < 60.0:
		sb.step(tb, 1.0 / 120.0, Vector2.ZERO, false)   # 動かない(ボスにはほとんど当たらない)
		tb += 1.0 / 120.0
	_check(sb.finished and not sb.failed and not sb.boss.defeated and sb.boss_fled_t > 0.0, "倒せないまま曲が終わると、クリアしてボスは逃げる(%.1f 秒)" % sb.boss_fled_t)
	fb.free()
	var fb2 := BulletField.new()
	var sb2 := GameSim.new()
	sb2.setup(fb2, {"events": bevs, "gizmos": [], "warn_lead": 0.6, "breaks": []}, 40.0, false, {})
	sb2.setup_boss_once(0.6, 1.0)
	sb2.debug_invincible = true
	sb2.boss.hp = 3.0
	var tb2 := 0.0
	while not sb2.finished and tb2 < 60.0:
		var dx: float = sb2.boss.pos.x - sb2.player_pos.x
		sb2.step(tb2, 1.0 / 120.0, Vector2(signf(dx) if absf(dx) > 3.0 else 0.0, 0.0), false)   # ボスの真下を追う
		tb2 += 1.0 / 120.0
	_check(sb2.finished and sb2.boss.defeated and sb2.score_boss_time > 0.0 and tb2 < 20.0, "倒すと弾が消えて、少しあとにクリア(撃破タイムボーナス %.0f)" % sb2.score_boss_time)
	fb2.free()

	# --- 3 択 ---
	var levels := {"max_gauge": 3, "regen": 3}
	var dup_ok := true
	var cap_ok := true
	for i in range(50):
		var ch: Array = Upgrades.roll(rng, levels, 3, ["guard"])
		var seen := {}
		for id in ch:
			dup_ok = dup_ok and not seen.has(id)
			seen[id] = true
			cap_ok = cap_ok and id != "max_gauge" and id != "regen" and id != "guard"
	_check(dup_ok and cap_ok, "3 択に同じものは出ず、上限に届いたもの・選べないものは出ない")
	var r2 := SurvivalRun.new()
	r2.start(4.0, ["noregen"], 5)
	_check(r2.excluded_upgrades().has("regen"), "無回復のときは、自然回復の強化を出さない")

	# --- 回復は初期の体力に対する量(体力を増やしても、絶対量は増えない)/ 被ダメージ半減は初期の体力の 30% 以下 ---
	var fu := BulletField.new()
	var su := GameSim.new()
	su.setup(fu, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 30.0, false, {})
	su.drain_time *= 1.5
	su.gauge_unit = 1.0 / 1.5
	su.regen_rate = 0.01
	su.low_threshold = 0.30 * su.gauge_unit
	su.gauge = 0.5
	var nu := 0.0
	for i in range(120):
		su.step(nu, 1.0 / 60.0, Vector2.ZERO, false)
		nu += 1.0 / 60.0
	_check(absf((su.gauge - 0.5) * 1.5 - 0.02) < 0.001, "体力 1.5 倍でも、自然回復は 2 秒で初期の体力の 2%%(絶対量 %.4f)" % ((su.gauge - 0.5) * 1.5))
	_check(absf(su.low_threshold * 1.5 - 0.30) < 1e-6, "被ダメージ半減の境目は、初期の体力の 30%%(いまの体力の %.1f%%)" % (su.low_threshold * 100.0))
	fu.free()

	# --- 最初の弾幕が飛ぶまで、自然回復しない(サバイバル) ---
	var fw := BulletField.new()
	var sw := GameSim.new()
	var shot := {"n": 1, "speed": 0.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	sw.setup(fw, {"events": [{"t": 2.0, "pos": Vector2(60, 60), "warn": false, "shots": [shot], "sfx": ""}, {"t": 20.0, "pos": Vector2(60, 60), "warn": false, "shots": [shot], "sfx": ""}], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 30.0, false, {})
	sw.regen_wait_first = true
	sw.gauge = 0.5
	var nw := 0.0
	for i in range(90):
		sw.step(nw, 1.0 / 60.0, Vector2.ZERO, false)
		nw += 1.0 / 60.0
	var g_before: float = sw.gauge
	for i in range(90):
		sw.step(nw, 1.0 / 60.0, Vector2.ZERO, false)
		nw += 1.0 / 60.0
	_check(is_equal_approx(g_before, 0.5) and absf(sw.gauge - 0.515) < 0.002, "最初の弾幕が飛ぶまで自然回復しない(1.5 秒 %.3f → 3 秒 %.3f)" % [g_before, sw.gauge])
	fw.free()

	# --- 身代わり ---
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 30.0, false, {})
	s.guard = 1
	s.guard_gauge = 0.4
	f.add(s.player_pos, Vector2.ZERO, 6.0, 0, 0.0)
	var now := 0.0
	for i in range(60):
		s.step(now, 1.0 / 60.0, Vector2.ZERO, false)
		now += 1.0 / 60.0
	_check(not s.failed and s.guard == 0 and s.guard_t >= 0.0 and s.gauge > 0.3, "身代わり: ゲージが 0 になるとき 1 回だけ踏みとどまり、弾を消す(ゲージ %.2f)" % s.gauge)
	f.add(s.player_pos, Vector2.ZERO, 6.0, 0, 0.0)
	for i in range(120):
		if s.finished:
			break
		s.step(now, 1.0 / 60.0, Vector2.ZERO, false)
		now += 1.0 / 60.0
	_check(s.failed, "身代わりを使ったあとは、ふつうに倒れる")
	f.free()

	print("test_survival: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
