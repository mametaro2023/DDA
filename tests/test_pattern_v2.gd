extends SceneTree
## 弾幕 v2(MOD「弾幕 v2」)の確認。手元の .osz(リポジトリの外。他のテストと同じ絶対パス)で、
##   ・弾の挙動(BulletField): 加減速・停止→再発進・分裂・反射
##   ・難易度の見積り(PatternGen.measure)が、挙動のある弾の実際の寿命に合っていること
##   ・生成が決定的で、Lv が譜面の★に追従し、弾数が上限に収まり、イベントの形が正しいこと
##   ・譜面ごとの違い(弾の向き・発生源・挙動の分布)が、v1 より大きいこと
##   ・MOD の配線、ゲーム(GameSim)で最後まで進められること
## godot --headless --path . --script tests/test_pattern_v2.gd [-- sets]   (sets を付けると、全難易度の一覧を出す)

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Mods = preload("res://scripts/mods.gd")

const DIR := "C:/Desktop/my_apps/DDA/"

var _fail := 0
var _verbose := false
var _cases: Array = []          # 生成した全譜面: {bm, g1, g2}(スピナー・サイズのテストに使う)
var _tiers := [0.0, 0.0, 0.0]   # 弾サイズの 3 段階(小・普通・大)の弾数


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var verbose := OS.get_cmdline_user_args().has("sets")
	_verbose = verbose
	_test_behaviors()
	_test_measure_estimates()
	_test_ar_speed()
	_test_star_scaling()
	_test_mods()
	var picks := _test_generation(verbose)
	_test_diversity(picks)
	_test_ar_independent(picks)
	_test_mod_apply(picks)
	_test_sizes()
	_print_normal_reference()
	_test_spinners()
	if not picks.is_empty():
		var best = picks[0]   # 挙動のある shot が最も多い譜面で、ゲームを通す
		var best_n := -1
		for p in picks:
			var cnt := 0
			for e in p.g2.events:
				for s in e.shots:
					if s.has("beh"):
						cnt += 1
			if cnt > best_n:
				best_n = cnt
				best = p
		_test_sim(best.bm, best.g2)
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 弾の挙動 ---

func _run(f: BulletField, secs: float, dt := 1.0 / 120.0) -> void:
	var n := int(round(secs / dt))
	for i in range(n):
		f.update(dt, Vector2(-500, -500), 3.5, false)


func _test_behaviors() -> void:
	var far := Vector2(480, 360)
	# 挙動なしの弾は、今までどおり直進
	var f := BulletField.new()
	f.add(far, Vector2(100, 0), 8.0, 0)
	_run(f, 1.0)
	_check(f.count == 1 and absf(f.pos[0].x - 580.0) < 1.0 and f.kind[0] == 0, "挙動なしの弾は直進する (x=%.1f)" % f.pos[0].x)

	# ACCEL: 50 → 150 px/s(加速度 100)。0.5 秒で 100、1 秒以降は 150 のまま
	f = BulletField.new()
	f.add(far, Vector2(50, 0), 8.0, 0, 0.0, 0.0, BulletField.BEH_ACCEL, 100.0, 150.0, 0.0)
	_run(f, 0.5)
	_check(absf(f.vel[0].length() - 100.0) < 2.0, "ACCEL: 0.5 秒後の速さ %.1f ≒ 100" % f.vel[0].length())
	_run(f, 1.0)
	_check(absf(f.vel[0].length() - 150.0) < 0.5, "ACCEL: 目標の速さで止まる %.1f" % f.vel[0].length())
	f = BulletField.new()   # 減速
	f.add(far, Vector2(200, 0), 8.0, 0, 0.0, 0.0, BulletField.BEH_ACCEL, -100.0, 80.0, 0.0)
	_run(f, 2.0)
	_check(absf(f.vel[0].length() - 80.0) < 0.5, "ACCEL: 減速して目標の速さで止まる %.1f" % f.vel[0].length())

	# STOPGO: 1 秒で止まり、1 秒待って、90 度回して再発進
	f = BulletField.new()
	f.add(far, Vector2(100, 0), 8.0, 0, 0.0, 0.0, BulletField.BEH_STOPGO, 1.0, 1.0, PI * 0.5)
	_run(f, 0.5)
	var x_mid: float = f.pos[0].x
	_check(x_mid > far.x + 45.0, "STOPGO: 止まる前は進む (x=%.1f)" % x_mid)
	_run(f, 0.8)   # 1.3 秒(止まっている間)
	var p_a: Vector2 = f.pos[0]
	_run(f, 0.4)   # 1.7 秒
	_check(f.pos[0].distance_to(p_a) < 0.5, "STOPGO: 止まっている間は動かない (%.2f px)" % f.pos[0].distance_to(p_a))
	_run(f, 1.5)   # 3.2 秒
	_check(f.pos[0].y > p_a.y + 50.0 and absf(f.pos[0].x - p_a.x) < 2.0, "STOPGO: 回した向き(下)へ再発進する (%s → %s)" % [str(p_a), str(f.pos[0])])

	# SPLIT: 0.5 秒で 4 つに割れ、子弾は親の 0.7 倍の速さ。親は消える
	f = BulletField.new()
	f.add(far, Vector2(100, 0), 10.0, 3, 0.0, 0.0, BulletField.BEH_SPLIT, 0.5, 4.0, 0.7)
	_run(f, 0.4)
	_check(f.count == 1, "SPLIT: 割れる前は 1 発")
	_run(f, 0.2)
	var sp_ok := f.count == 4
	for i in range(f.count):
		sp_ok = sp_ok and absf(f.vel[i].length() - 70.0) < 0.5 and f.kind[i] == 0 and f.col[i] == 3
	_check(sp_ok, "SPLIT: 4 つの子弾(速さ 70・挙動なし・同じ色) count=%d" % f.count)
	# 上限: 満杯のときは子弾を足さず、親だけ消える(あふれない)
	f = BulletField.new()
	for i in range(BulletField.MAX_BULLETS - 1):
		f.add(Vector2(-100, -100), Vector2.ZERO, 5.0, 0)   # 範囲外(次の更新で消える)
	f.add(far, Vector2(10, 0), 10.0, 0, 0.0, 0.0, BulletField.BEH_SPLIT, 0.0, 8.0, 1.0)
	f.update(0.01, Vector2(-500, -500), 3.5, false)
	_check(f.count <= BulletField.MAX_BULLETS, "SPLIT: 上限(%d)を超えない count=%d" % [BulletField.MAX_BULLETS, f.count])

	# BOUNCE: 右の縁(x=960)で 1 回だけ跳ね返り、2 回目は出ていく
	f = BulletField.new()
	f.add(Vector2(940, 300), Vector2(100, 0), 8.0, 0, 0.0, 0.0, BulletField.BEH_BOUNCE, 1.0, 0.0, 0.0)
	_run(f, 0.6)
	_check(f.count == 1 and f.vel[0].x < 0.0 and f.pos[0].x < 960.0, "BOUNCE: 縁で跳ね返る (x=%.1f vx=%.1f)" % [f.pos[0].x, f.vel[0].x])
	_run(f, 12.0)   # 左の縁まで行って、反射の回数が 0 なので出ていく
	_check(f.count == 0, "BOUNCE: 反射の回数を使い切ったら、そのまま出ていく (count=%d)" % f.count)


# --- 見積り(measure)が実際の寿命に合う ---

## 1 発(または挙動つきの 1 発)を BulletField で実際に飛ばして、盤面から消えるまでの弾の秒数の合計(子弾も含む)。
func _sim_bullet_seconds(p: Vector2, ang: float, s: Dictionary) -> float:
	var f := BulletField.new()
	var beh: Dictionary = s.beh
	var v := Vector2.from_angle(ang) * float(s.speed)
	f.add(p, v, 8.0, 0, 0.0, 0.0, int(beh.k), float(beh.a), float(beh.b), float(beh.c))
	var dt := 1.0 / 120.0
	var total := 0.0
	var t := 0.0
	while f.count > 0 and t < 90.0:
		total += float(f.count) * dt
		f.update(dt, Vector2(-500, -500), 3.5, false)
		t += dt
	return total


func _test_measure_estimates() -> void:
	var cases := [
		{"k": BulletField.BEH_ACCEL, "a": 120.0, "b": 220.0, "c": 0.0},
		{"k": BulletField.BEH_ACCEL, "a": -80.0, "b": 60.0, "c": 0.0},
		{"k": BulletField.BEH_STOPGO, "a": 0.8, "b": 0.5, "c": 0.45},
		{"k": BulletField.BEH_STOPGO, "a": 0.6, "b": 0.4, "c": -0.45},
		{"k": BulletField.BEH_SPLIT, "a": 0.9, "b": 4.0, "c": 0.7},
		{"k": BulletField.BEH_BOUNCE, "a": 2.0, "b": 0.0, "c": 0.0},
	]
	var spots := [[Vector2(480, 300), 0.4], [Vector2(200, 500), 2.5], [Vector2(800, 200), -2.0]]
	var worst := 0.0
	for cs in cases:
		for sp in spots:
			var s := {"speed": 150.0, "beh": cs}
			var cells := 4000
			var diff := PackedFloat64Array()
			diff.resize(cells)
			PatternGen._mark_behaving(diff, cells, 0.0, sp[0], sp[1], s)
			var est := 0.0
			var run := 0
			for i in range(cells):
				run += diff[i]
				est += float(run) * PatternGen.SAMPLE_DT
			var act := _sim_bullet_seconds(sp[0], sp[1], s)
			var err := absf(est - act) / maxf(act, 0.001)
			worst = maxf(worst, err)
			_check(err < 0.15, "見積り: beh %d を %s から撃つと、弾の秒数 見積り %.2f / 実際 %.2f (誤差 %.0f%%)" % [int(cs.k), str(sp[0]), est, act, err * 100.0])
	print("measure の見積り: 最大の誤差 %.1f%%" % (worst * 100.0))
	# v1 の shot(beh も off もない)の見積りは、今までと同じ
	var ev1 := [{"t": 1.0, "pos": Vector2(480, 360), "warn": true, "shots": [{"n": 24, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.75, "color": 0, "turn": 0.0}], "sfx": ""}]
	var ev2 := ev1.duplicate(true)
	ev2[0].shots[0]["off"] = Vector2.ZERO
	_check(is_equal_approx(PatternGen.measure(ev1).mean, PatternGen.measure(ev2).mean), "off = 0 の shot は、off なしと同じ見積り")


# --- MOD ---

func _test_ar_speed() -> void:
	var f := PatternGenV2.ar_speed_mul
	_check(is_equal_approx(f.call(8.0), 1.0), "AR 8 の弾速は基準のまま (%.3f)" % f.call(8.0))
	# AR 8 以下は、表(AR → アプローチ時間 ms)に反比例: 弾速の倍率 = 750 / ms
	var table := {0: 1800.0, 1: 1680.0, 2: 1560.0, 3: 1440.0, 4: 1320.0, 5: 1200.0, 6: 1050.0, 7: 900.0, 8: 750.0}
	for ar in table:
		_check(is_equal_approx(f.call(float(ar)), 750.0 / float(table[ar])), "AR %d の倍率 %.3f が 750/%d に合う" % [ar, f.call(float(ar)), int(table[ar])])
	# AR 8 より上は、アプローチ時間どおりより遅く、上がり方がだんだん小さくなり、頭打ち(1 + AR_FAST_SOFT)
	var step_a: float = f.call(8.5) - f.call(8.0)
	var step_b: float = f.call(9.0) - f.call(8.5)
	var step_c: float = f.call(9.5) - f.call(9.0)
	var step_d: float = f.call(10.0) - f.call(9.5)
	_check(f.call(9.0) < 750.0 / 600.0 and f.call(10.0) < 750.0 / 450.0 and f.call(10.0) < 1.0 + PatternGenV2.AR_FAST_SOFT, "高 AR は、アプローチ時間どおりより遅い(AR 9: %.3f・AR 10: %.3f。上限 %.2f)" % [f.call(9.0), f.call(10.0), 1.0 + PatternGenV2.AR_FAST_SOFT])
	_check(step_a > step_b and step_b > step_c and step_c > step_d and step_d > 0.0, "高 AR ほど、弾速の上がり方が小さい(0.5 刻みで +%.3f → +%.3f → +%.3f → +%.3f)" % [step_a, step_b, step_c, step_d])
	_check(f.call(10.0) * PatternGen.BASE_SPEED < 200.0, "AR 10 でも弾速は 200 px/s 未満(%.0f px/s)" % (f.call(10.0) * PatternGen.BASE_SPEED))
	var bm0 := Beatmap.new()
	for ar in [0.0, 3.5, 5.0, 7.2]:
		bm0.ar = ar
		_check(is_equal_approx(f.call(ar), 750.0 / bm0.preempt_ms()), "AR %.1f: Beatmap.preempt_ms と同じ式" % ar)
	var prev := 0.0
	var mono := true
	for i in range(0, 101):
		var v: float = f.call(float(i) / 10.0)
		mono = mono and v > prev
		prev = v
	_check(mono, "AR が大きいほど弾速が上がる(単調増加)")
	_check(is_equal_approx(f.call(-3.0), f.call(0.0)) and is_equal_approx(f.call(12.0), f.call(10.0)), "範囲外の AR は端に止める")


## 弾速は Lv に入る(速いほど難しい): 同じ譜面で AR だけ変えると、弾速は AR で変わる。Lv は★の目標のままになるよう、速いほど画面内の弾数は少なく、遅いほど多くなる。
## MOD の弾速の倍率は、基準の弾速(BASE_SPEED)に対する比として Lv に効く(v1 と同じ)。
func _test_ar_independent(picks: Array) -> void:
	if picks.is_empty():
		return
	var bm = picks[0].bm
	var ar0: float = bm.ar
	var res := {}
	for ar in [2.0, 8.0, 10.0]:
		bm.ar = ar
		var g := PatternGenV2.generate(bm)
		var shots := 0.0
		for e in g.events:
			for s in e.shots:
				shots += float(s.n)
		res[ar] = {"g": g, "shots": shots}
	bm.ar = ar0
	var lo: Dictionary = res[2.0]
	var mid: Dictionary = res[8.0]
	var hi: Dictionary = res[10.0]
	_check(is_equal_approx(mid.g.speed, PatternGen.BASE_SPEED * PatternGenV2.star_speed_mul(mid.g.stars)) and is_equal_approx(float(mid.g.speed_ref), PatternGen.BASE_SPEED), "AR 8 の弾速は、基準 × ★の倍率・Lv の弾速の基準(speed_ref)は基準の弾速")
	_check(is_equal_approx(hi.g.speed / lo.g.speed, PatternGenV2.ar_speed_mul(10.0) / PatternGenV2.ar_speed_mul(2.0)), "AR だけ変えると弾速は倍率どおりに変わる(★の倍率は同じ)")
	for k in [lo, hi]:
		_check(absf(float(k.g.level) - float(mid.g.level)) < 0.25, "AR を変えても Lv は同じ (%.2f / %.2f)" % [k.g.level, mid.g.level])
	_check(lo.g.rating.mean > mid.g.rating.mean * 1.1 and mid.g.rating.mean > hi.g.rating.mean * 1.05, "速い弾ほど、同じ Lv に必要な画面内の弾数は少ない(速いほど難しい。AR 2/8/10 の平均: %.0f / %.0f / %.0f)" % [lo.g.rating.mean, mid.g.rating.mean, hi.g.rating.mean])
	_check(lo.shots > mid.shots and mid.shots > hi.shots, "発射する数も、速いほど少ない (AR 2/8/10: %.0f / %.0f / %.0f)" % [lo.shots, mid.shots, hi.shots])
	# MOD の弾速の倍率は、基準の弾速に対する比で Lv に効く
	var up_lo: float = Mods.apply(lo.g, Mods.params(["storm"])).level - float(lo.g.level)
	var up_hi: float = Mods.apply(hi.g, Mods.params(["storm"])).level - float(hi.g.level)
	_check(up_lo > 0.3 and up_hi > 0.3, "AR が低くても高くても、暴風雨で Lv が上がる (+%.2f / +%.2f)" % [up_lo, up_hi])
	print("AR と弾幕(同じ譜面で AR だけ変更): AR 2 → 弾速 %.0f / Lv %.2f / 平均 %.0f 発 / 発射 %.0f、AR 8 → %.0f / %.2f / %.0f / %.0f、AR 10 → %.0f / %.2f / %.0f / %.0f" % [
		lo.g.speed, lo.g.level, lo.g.rating.mean, lo.shots, mid.g.speed, mid.g.level, mid.g.rating.mean, mid.shots, hi.g.speed, hi.g.level, hi.g.rating.mean, hi.shots])


## ★で変える弾速(STAR_SPEED_*)と、v2 用の表(TARGET_TABLE_V2): 高★ほど弾速が上がり、★ 1 あたりの弾数が v1 より多い。
func _test_star_scaling() -> void:
	var s := PatternGenV2.star_speed_mul
	_check(is_equal_approx(s.call(2.0), PatternGenV2.STAR_SPEED_LO) and is_equal_approx(s.call(4.0), PatternGenV2.STAR_SPEED_LO) and is_equal_approx(s.call(8.0), PatternGenV2.STAR_SPEED_HI) and is_equal_approx(s.call(10.0), PatternGenV2.STAR_SPEED_HI), "★の弾速の倍率: ★4 以下 %.2f・★8 以上 %.2f" % [PatternGenV2.STAR_SPEED_LO, PatternGenV2.STAR_SPEED_HI])
	var mono := true
	for i in range(1, 41):
		mono = mono and s.call(4.0 + float(i) * 0.1) >= s.call(4.0 + float(i - 1) * 0.1)
	_check(mono and s.call(6.0) > s.call(5.0), "高★ほど、弾速の倍率が大きい")
	# v2 の表: ★(表の 5.9 = 譜面の約 4.9)までは v1 と同じ。それより上は、v1 より多く、傾きも急
	var t1 := PatternGen.TARGET_TABLE
	var t2 := PatternGen.TARGET_TABLE_V2
	var same := true
	for r in t1:
		if r[0] <= 5.9 and PatternGen.target_score_for(float(r[0]), t2) != float(r[1]):
			same = false
	_check(same, "v2 の表は、表の ★5.9 以下では v1 と同じ")
	_check(PatternGen.target_score_for(6.7, t2) > PatternGen.target_score_for(6.7, t1) + 15.0 and PatternGen.target_score_for(9.27, t2) > PatternGen.target_score_for(9.27, t1) * 1.2, "v2 の表の高★は、v1 より弾数が多い (★7.7 相当 %.0f / %.0f・★8.3 相当 %.0f / %.0f)" % [PatternGen.target_score_for(8.7, t2), PatternGen.target_score_for(8.7, t1), PatternGen.target_score_for(9.27, t2), PatternGen.target_score_for(9.27, t1)])
	var inv := true
	for st in [1.0, 3.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.5, 11.0]:
		if absf(PatternGen.stars_for_score(PatternGen.target_score_for(st, t2), t2) - st) > 0.02:
			inv = false
	_check(inv, "v2 の表で、target_score_for と stars_for_score が互いに逆")
	# 実際の譜面: ★5 と ★7 以上で、弾数・弾速の差が v1 より広がる
	var easy = null
	var hard = null
	var o := OszLoader.new()
	if o.open(DIR + "320118 Reol - No title.osz"):
		for bm in o.difficulties:
			if bm.version == "Insane":
				easy = bm
	var o2 := OszLoader.new()
	if o2.open(DIR + "813569 Laur - Sound Chimera.osz"):
		for bm in o2.difficulties:
			if bm.version == "Chimera":
				hard = bm
	if easy != null and hard != null:
		var e2 := PatternGenV2.generate(easy)
		var h2 := PatternGenV2.generate(hard)
		var e1 := PatternGen.generate(easy)
		var h1 := PatternGen.generate(hard)
		var r2: float = float(h2.rating.mean) / float(e2.rating.mean)
		var r1: float = float(h1.rating.mean) / float(e1.rating.mean)
		_check(r2 > r1 * 1.05 and r2 > 1.4, "★5 → ★8 の画面内の弾数の比: v2 %.2f 倍 > v1 %.2f 倍" % [r2, r1])
		_check(float(h2.speed) / float(e2.speed) > 1.1, "★5 → ★8 の弾速の比 %.2f 倍(%.0f → %.0f px/s)" % [float(h2.speed) / float(e2.speed), e2.speed, h2.speed])
		_check(float(h2.speed) < PatternGen.BASE_SPEED * PatternGenV2.ar_speed_mul(10.0) * 1.2 and float(h2.speed) < 230.0, "高★でも弾速は 230 px/s 未満(%.0f px/s)" % h2.speed)


func _test_mods() -> void:
	var m := Mods.find("v2")
	_check(not m.is_empty(), "MOD v2 が登録されている")
	var p := Mods.params(["v2"])
	_check(bool(p.gen_v2) and is_equal_approx(p.score_mul, 1.0), "v2: gen_v2 = true / スコア倍率 ×1.0")
	_check(not bool(Mods.params(["hell", "rush"]).gen_v2), "v2 を付けていなければ gen_v2 = false")
	_check(Mods.multi_ok(["v2", "boss"]) == ["v2"], "v2 はマルチでも使える(撃破だけ外れる)")
	_check(bool(Mods.params(["hell", "v2"]).gen_v2) and is_equal_approx(Mods.params(["hell", "v2"]).size_mul, 1.35), "v2 は他の MOD と併用できる")
	# 体力: v2 は 250ms → 300ms(+20%)。地獄(150ms)と併用なら 180ms。v2 なしは変わらない
	_check(is_equal_approx(float(p.drain_time), 0.30), "v2: 体力(ゲージ満タンぶんの被弾時間)が 300ms (%.3f)" % float(p.drain_time))
	_check(is_equal_approx(float(Mods.params(["hell", "v2"]).drain_time), 0.18), "地獄 + v2: 150ms × 1.2 = 180ms")
	_check(is_equal_approx(float(Mods.params(["hell"]).drain_time), 0.15) and is_equal_approx(float(Mods.params([]).drain_time), GameSim.GAUGE_DRAIN_TIME), "v2 なしの体力は変わらない")
	# ゲームの中でも、同じ接触時間のダメージが 1/1.2 になり、回復(割合)は絶対値で 1.2 倍の体力に効く
	var gauge_after := func(ids: Array) -> float:
		var f := BulletField.new()
		var s := GameSim.new()
		s.setup(f, {"events": [], "gizmos": [], "warn_lead": 0.5, "breaks": [], "zones": []}, 100.0, false, Mods.params(ids))
		f.add(s.player_pos, Vector2.ZERO, 8.0, 0)   # 自機の位置に止まっている弾
		for i in range(12):   # 0.2 秒触れる(自機は動かさない)
			s.step(float(i) / 60.0, 1.0 / 60.0, Vector2.ZERO, false)
		return s.gauge
	var g_v1: float = gauge_after.call([])
	var g_v2: float = gauge_after.call(["v2"])
	_check((1.0 - g_v2) < (1.0 - g_v1) * 0.86 and (1.0 - g_v2) > (1.0 - g_v1) * 0.80, "同じ接触で、v2 のダメージは約 1/1.2(v1 %.3f / v2 %.3f)" % [1.0 - g_v1, 1.0 - g_v2])


# --- 生成 ---

func _feat_ok(g: Dictionary, label: String) -> void:
	var prev := -1.0
	var bad := 0
	var why := ""
	for e in g.events:
		if float(e.t) < prev:
			bad += 1
			why = why if why != "" else "時刻順 t=%.3f" % float(e.t)
		prev = float(e.t)
		for s in e.shots:
			if int(s.n) < 1 or not (s.speed > 0.0) or not (s.size > 0.0):
				bad += 1
				why = why if why != "" else "n/speed/size %s" % str(s)
			var p: Vector2 = e.pos + (s.off as Vector2 if s.has("off") else Vector2.ZERO)
			if not (p.x > -200.0 and p.x < 1160.0 and p.y > -200.0 and p.y < 920.0):   # 巨大なスライダーの軌道は、盤面の外へ出ることがある(v1 も同じ。出た位置の弾は、すぐ消える)
				bad += 1
				why = why if why != "" else "位置 %s (t=%.2f)" % [str(p), float(e.t)]
			if s.has("beh"):
				var b: Dictionary = s.beh
				if int(b.k) == BulletField.BEH_SPLIT and (int(b.b) < 1 or int(b.b) > 8):
					bad += 1
					why = why if why != "" else "分裂数 %s" % str(b)
	_check(bad == 0, "%s: イベントの形(時刻順・n・速さ・大きさ・位置・beh) の不正が %d 件 (最初: %s)" % [label, bad, why])


## 譜面の特徴ベクトル(発射位置の 3×3、発射方向の 12 方位、挙動の割合 5 種。それぞれ合計 1 に正規化して連結)。
func _features(g: Dictionary) -> PackedFloat32Array:
	var cell := PackedFloat32Array()
	cell.resize(9)
	var ang := PackedFloat32Array()
	ang.resize(12)
	var beh := PackedFloat32Array()
	beh.resize(5)
	for e in g.events:
		for s in e.shots:
			var p: Vector2 = e.pos + (s.off as Vector2 if s.has("off") else Vector2.ZERO)
			var base: float = s.a0
			if s.aim:
				base += (PatternGen.AIM_REF - p).angle()
			var w := float(s.n)
			var cx := clampi(int(p.x / (PatternGen.ARENA.x / 3.0)), 0, 2)
			var cy := clampi(int(p.y / (PatternGen.ARENA.y / 3.0)), 0, 2)
			cell[cy * 3 + cx] += w
			for i in range(int(s.n)):
				var a := fposmod(PatternGen.shot_angle(s, base, i), TAU)
				ang[mini(int(a / TAU * 12.0), 11)] += 1.0
			beh[int(s.beh.k) if s.has("beh") else 0] += w
	var out := PackedFloat32Array()
	for arr in [cell, ang, beh]:
		var sum := 0.0
		for v in arr:
			sum += v
		for v in arr:
			out.append(v / maxf(sum, 1.0))
	return out


func _dist(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d := 0.0
	for i in range(a.size()):
		d += absf(a[i] - b[i])
	return d / 3.0   # 3 つの分布の平均の L1(0..2)


## 戻り値: 曲ごとに、★4.5 に最も近い 1 難易度の {set, bm, g1, g2}(多様性の比較に使う)
func _test_generation(verbose: bool) -> Array:
	var picks: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		print("skip: ", DIR)
		return picks
	var files: Array = []
	for f in d.get_files():
		if f.ends_with(".osz"):
			files.append(f)
	files.sort()
	var n_gen := 0
	var ms_v1 := 0.0
	var ms_v2 := 0.0
	var worst_dev := 0.0
	var n_raised := 0
	var motif_total := PackedInt32Array()
	motif_total.resize(PatternGenV2.MOTIF_N)
	for f in files:
		var loader := OszLoader.new()
		if not loader.open(DIR + f):
			print("skip: ", f)
			continue
		var best = null
		for bm in loader.difficulties:
			var t0 := Time.get_ticks_usec()
			var g1 := PatternGen.generate(bm)
			var t1 := Time.get_ticks_usec()
			var g2 := PatternGenV2.generate(bm)
			var t2 := Time.get_ticks_usec()
			ms_v1 += (t1 - t0) / 1000.0
			ms_v2 += (t2 - t1) / 1000.0
			n_gen += 1
			var label := "%s [%s]" % [f.left(14), bm.version]
			# 決定的
			var g3 := PatternGenV2.generate(bm)
			_check(str(g2.events).hash() == str(g3.events).hash() and is_equal_approx(g2.level, g3.level), label + ": v2 の生成が決定的でない")
			_check(g2.style == "v2" and g1.style == "v1", label + ": style")
			# 弾速: v2 は AR で決まる(AR 5 で基準の弾速)。v1 は★に応じた ±15% のまま
			# (低 ★ × 低 AR で、弾数を最小にしても Lv が目標に下がりきらないときだけ、AR の弾速から上がる。上限は基準の弾速)
			var ar_spd: float = PatternGen.BASE_SPEED * PatternGenV2.ar_speed_mul(bm.ar) * PatternGenV2.star_speed_mul(g2.stars)
			if is_equal_approx(g2.speed, ar_spd):
				pass
			else:
				n_raised += 1
				_check(g2.speed > ar_spd and g2.speed <= PatternGen.BASE_SPEED + 0.001, "%s: v2 の弾速 %.1f は AR %.1f の弾速 %.1f から上がる場合も、基準以下" % [label, g2.speed, bm.ar, ar_spd])
			_check(absf(g1.speed / PatternGen.BASE_SPEED - 1.0) <= PatternGen.SPEED_VAR + 0.0001, "%s: v1 の弾速 %.1f は★に応じた範囲のまま" % [label, g1.speed])
			# Lv(長さ補正なし)が目標に合う(v1 と同じ許容 8%)。弾数の下限/上限で合わせきれない譜面は、弾サイズで吸収される
			var m: Dictionary = g2.rating
			var dens_lv: float = PatternGen.level_of(m.score, g2.speed, g2.size, PatternGen.PLAYER_HIT_R, PatternGen.LENGTH_REF, g2.speed_ref, g2.table)
			var dev := absf(dens_lv - g2.target_level) / maxf(g2.target_level, 0.01)
			worst_dev = maxf(worst_dev, dev)
			_check(dev <= 0.08, "%s: v2 の Lv(長さ補正なし) %.2f が目標 %.2f から 8%% 以上ずれている" % [label, dens_lv, g2.target_level])
			# 弾数の上限(画面内の弾数のピークが、BulletField の上限の 8 割以内)
			_check(m.peak < BulletField.MAX_BULLETS * 0.8, "%s: 画面内の弾数のピーク %.0f が上限の 8 割を超える" % [label, m.peak])
			_feat_ok(g2, label)
			_count_tiers(g2, label)
			_cases.append({"bm": bm, "g1": g1, "g2": g2})
			for sec in g2.v2.sections:
				motif_total[sec.motif] += 1
			if verbose:
				print("%-16s %-22s ★%.2f | v1 Lv %.2f (mean %3.0f peak %3.0f) | v2 Lv %.2f (mean %3.0f peak %3.0f) target %.2f" % [
					f.left(16), bm.version.left(22), g2.stars, g1.level, g1.rating.mean, g1.rating.peak, g2.level, m.mean, m.peak, g2.target_level])
			if best == null or absf(bm.stars - 4.5) < absf(best.bm.stars - 4.5):
				best = {"set": f, "bm": bm, "g1": g1, "g2": g2}
		if best != null:
			picks.append(best)
	print("生成 %d 譜面: 1 譜面あたり v1 %.0f ms / v2 %.0f ms / v2 の目標からの最大のずれ %.1f%%" % [n_gen, ms_v1 / maxf(n_gen, 1), ms_v2 / maxf(n_gen, 1), worst_dev * 100.0])
	print("弾速が AR の値から上がった譜面: %d / %d" % [n_raised, n_gen])
	var hist := ""
	for i in range(PatternGenV2.MOTIF_N):
		hist += "%s:%d " % [PatternGenV2.MOTIF_NAMES[i], motif_total[i]]
	print("区間のモチーフ(全譜面の合計): ", hist)
	for i in range(1, PatternGenV2.MOTIF_N):
		_check(motif_total[i] > 0, "モチーフ %s が、どの譜面でも 1 度も選ばれていない" % PatternGenV2.MOTIF_NAMES[i])
	return picks


## 曲どうし(★4.5 前後の 1 難易度ずつ)の特徴ベクトルの距離の平均が、v1 より十分大きいこと。
func _test_diversity(picks: Array) -> void:
	if picks.size() < 4:
		return
	var f1: Array = []
	var f2: Array = []
	for p in picks:
		f1.append(_features(p.g1))
		f2.append(_features(p.g2))
	var s1 := 0.0
	var s2 := 0.0
	var n := 0
	for i in range(picks.size()):
		for j in range(i + 1, picks.size()):
			s1 += _dist(f1[i], f1[j])
			s2 += _dist(f2[i], f2[j])
			n += 1
	print("譜面どうしの違い(特徴ベクトルの距離の平均, %d 曲 %d 組): v1 %.3f / v2 %.3f (%.1f 倍)" % [picks.size(), n, s1 / n, s2 / n, s2 / maxf(s1, 0.0001)])
	_check(s2 > s1 * 1.5, "v2 の譜面どうしの違い %.3f が v1 の 1.5 倍(%.3f)に届かない" % [s2 / n, s1 * 1.5 / n])


# --- ゲームで最後まで進める ---

func _test_sim(bm, gen: Dictionary) -> void:
	var field := BulletField.new()
	var sim := GameSim.new()
	var end_t: float = bm.last_time() / 1000.0 + 2.0
	sim.setup(field, gen, end_t, true, {})
	var dt := 1.0 / 60.0
	var now := 0.0
	var max_count := 0
	var beh_seen := {}
	var t0 := Time.get_ticks_usec()
	while now < end_t and not sim.finished:
		sim.step(now, dt, Vector2.ZERO, false)
		max_count = maxi(max_count, field.count)
		if int(now / dt) % 15 == 0:
			for i in range(field.count):
				if field.kind[i] != 0:
					beh_seen[int(field.kind[i])] = true
		now += dt
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("GameSim(v2, %s): 最大 %d 発 / 挙動の種類 %s / %.0f ms(%.2f ms/フレーム)" % [bm.version, max_count, str(beh_seen.keys()), ms, ms / maxf(now / dt, 1.0)])
	_check(max_count <= BulletField.MAX_BULLETS, "ゲーム中の弾数が上限を超えない (%d)" % max_count)
	_check(max_count > 20, "ゲーム中に弾が撃たれている (最大 %d)" % max_count)
	_check(not beh_seen.is_empty(), "ゲーム中に、挙動のある弾が飛んでいる")


# --- ほかの MOD との併用 ---

## v2 の弾幕に「暴風雨」「加速」を掛けても、壁の弾は 1 発ずつのまま(本数が崩れない)で、Lv は MOD なしより上がること。
func _test_mod_apply(picks: Array) -> void:
	var g: Dictionary = {}
	for p in picks:
		var walls := 0
		for e in p.g2.events:
			for s in e.shots:
				if s.get("keep_n", false):
					walls += 1
		if walls > 0:
			g = p.g2
			break
	if g.is_empty():
		return
	var storm: Dictionary = Mods.apply(g, Mods.params(["storm"]))
	var bad := 0
	var kept := 0
	for e in storm.events:
		for s in e.shots:
			if s.get("keep_n", false):
				kept += 1
				if int(s.n) != 1:
					bad += 1
	_check(kept > 0 and bad == 0, "暴風雨を掛けても、壁の弾(%d 発)は 1 発ずつのまま(崩れたもの %d)" % [kept, bad])
	_check(storm.level > g.level + 0.5, "v2 + 暴風雨 の Lv %.2f が、MOD なし %.2f より上がる" % [storm.level, g.level])
	var rush: Dictionary = Mods.apply(g, Mods.params(["rush"]))
	_check(rush.level > g.level + 0.3, "v2 + 加速 の Lv %.2f が、MOD なし %.2f より上がる" % [rush.level, g.level])
	_check(is_equal_approx(Mods.apply(g, Mods.params(["v2"])).level, g.level), "v2 だけなら、MOD の適用で Lv は変わらない")


# --- 弾サイズの 3 段階 ---

## 弾ごとの大きさ(基準の弾サイズに対する倍率)が、小(0.65 前後)・普通(1.0)・大(2.2)のどれかであること。弾数を数える。
func _count_tiers(g: Dictionary, label: String) -> void:
	var unknown := 0
	for e in g.events:
		for s in e.shots:
			var r: float = float(s.size) / float(g.size)
			var w := float(s.n)
			if absf(r - 1.0) < 0.01:
				_tiers[1] += w
			elif absf(r - PatternGenV2.SIZE_LARGE) < 0.01:
				_tiers[2] += w
			elif r < 0.99 and r >= 0.6:
				_tiers[0] += w
			else:
				unknown += 1
	_check(unknown == 0, "%s: 3 段階のどれでもない弾サイズの shot が %d 件" % [label, unknown])


func _test_sizes() -> void:
	var total: float = _tiers[0] + _tiers[1] + _tiers[2]
	if total <= 0.0:
		return
	print("弾サイズの割合(全譜面の弾数): 小 %.1f%% / 普通 %.1f%% / 大 %.2f%%" % [_tiers[0] * 100.0 / total, _tiers[1] * 100.0 / total, _tiers[2] * 100.0 / total])
	_check(_tiers[0] > 0.0 and _tiers[2] > 0.0, "小さい弾・大きい弾がどちらも使われている")
	_check(_tiers[2] / total < 0.08, "大きい弾は弾数の 8%% 未満(%.2f%%)" % (_tiers[2] * 100.0 / total))
	# measure の重み: 大きい弾は、危険半径の比で重く数える(size_ref を渡さなければ、数は同じ)
	var mk := func(size: float) -> Array:
		return [{"t": 1.0, "pos": Vector2(480, 360), "warn": true, "shots": [{"n": 40, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": size, "color": 0, "turn": 0.0}], "sfx": ""},
			{"t": 20.0, "pos": Vector2(480, 360), "warn": true, "shots": [], "sfx": ""},
			{"t": 21.0, "pos": Vector2(480, 360), "warn": true, "shots": [{"n": 1, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": size, "color": 0, "turn": 0.0}], "sfx": ""}]
	var small: Dictionary = PatternGen.measure(mk.call(6.0), [], 6.0)
	var big: Dictionary = PatternGen.measure(mk.call(6.0 * PatternGenV2.SIZE_LARGE), [], 6.0)
	var ratio := PatternGen.danger_radius(6.0 * PatternGenV2.SIZE_LARGE) / PatternGen.danger_radius(6.0)
	_check(absf(big.mean / small.mean - ratio) < 0.01, "重み: 大きい弾の mean は %.2f 倍(危険半径の比 %.2f)" % [big.mean / small.mean, ratio])
	_check(is_equal_approx(PatternGen.measure(mk.call(6.0)).mean, PatternGen.measure(mk.call(6.0 * PatternGenV2.SIZE_LARGE)).mean), "size_ref なし(v1)では、弾の大きさは数えない")


# --- スピナー ---

## 盤面を格子に分けて、自機が入れる(弾の当たり判定から離れた)マスを数える。{free: 割合, comp: いちばん大きいつながりの割合, cells: 入れるマスの PackedByteArray}
func _free_map(field: BulletField) -> Dictionary:
	var cw := 32
	var ch := 24
	var cell := 30.0
	var free := PackedByteArray()
	free.resize(cw * ch)
	var pr := GameSim.PLAYER_HIT_R * GameSim.PLAYER_SIZE_MUL + 6.0   # 自機の当たり判定 + 余裕 6px
	var nfree := 0
	for iy in range(ch):
		for ix in range(cw):
			var c := Vector2((ix + 0.5) * cell, (iy + 0.5) * cell)
			var ok := 1
			for i in range(field.count):
				var lim: float = field.rad[i] * BulletField.HIT_SCALE + pr
				if field.pos[i].distance_squared_to(c) < lim * lim:
					ok = 0
					break
			free[iy * cw + ix] = ok
			nfree += ok
	# いちばん大きいつながり(8 近傍)
	var seen := PackedByteArray()
	seen.resize(cw * ch)
	var best := 0
	for s0 in range(cw * ch):
		if free[s0] == 0 or seen[s0] == 1:
			continue
		var stack: Array = [s0]
		seen[s0] = 1
		var size := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			size += 1
			var cx := cur % cw
			var cy := cur / cw
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := cx + dx
					var ny := cy + dy
					if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
						continue
					var ni := ny * cw + nx
					if free[ni] == 1 and seen[ni] == 0:
						seen[ni] = 1
						stack.append(ni)
		best = maxi(best, size)
	return {"free": float(nfree) / float(cw * ch), "comp": float(best) / float(cw * ch), "cells": free}


## 1 つのスピナーだけを撃たせて(その区間のイベントだけ)、0.4 秒ごとに {free, comp} と、前の記録からの「安全なマスが残る割合」を測る。
func _spin_metrics(g: Dictionary, spin: Dictionary, preroll := 0.0) -> Dictionary:
	var evs: Array = []
	for e in g.events:
		if float(e.t) >= float(spin.t) - preroll - 0.001 and float(e.t) <= float(spin.end) + 0.2:
			evs.append(e)
	var field := BulletField.new()
	var sim := GameSim.new()
	var sub := {"events": evs, "gizmos": [], "warn_lead": 0.5, "breaks": [], "zones": []}
	var t_end: float = float(spin.end) + 3.0
	sim.setup(field, sub, t_end, true, {})
	sim.debug_invincible = true
	var dt := 1.0 / 60.0
	var now: float = float(spin.t) - preroll - 0.05
	var next_sample: float = float(spin.t) + 0.4
	var free_min := 1.0
	var comp_min := 1.0
	var prev: PackedByteArray = PackedByteArray()
	var pers_sum := 0.0
	var pers_n := 0
	while now < t_end:
		sim.step(now, dt, Vector2.ZERO, false)
		now += dt
		if now >= next_sample and now <= float(spin.end) + 1.5:
			next_sample += 0.4
			var m := _free_map(field)
			free_min = minf(free_min, m.free)
			comp_min = minf(comp_min, m.comp)
			var cur: PackedByteArray = m.cells
			if prev.size() == cur.size():
				var a := 0
				var both := 0
				for i in range(cur.size()):
					if prev[i] == 1:
						a += 1
						if cur[i] == 1:
							both += 1
				if a > 0:
					pers_sum += float(both) / float(a)
					pers_n += 1
			prev = cur
	return {"free_min": free_min, "comp_min": comp_min, "persist": pers_sum / maxf(float(pers_n), 1.0)}


## v2 のスピナー: 4 つの型がすべて使われる / どのスピナーでも、自機の入れる場所が十分に残り、つながっている(必ず通れる)/
## 安全な場所が v1 より動く(同じ場所に居続けられない)。
func _test_spinners() -> void:
	var kinds := [0, 0, 0, 0]
	var v1_p := 0.0
	var v1_f := 0.0
	var v2_f := 0.0
	var v2_p := 0.0
	var n := 0
	var worst_free := 1.0
	var worst_comp := 1.0
	var t0 := Time.get_ticks_usec()
	for cs in _cases:
		var spins: Array = cs.g2.v2.spins
		for sp in spins:
			kinds[int(sp.kind)] += 1
		if spins.is_empty():
			continue
		var pick: Dictionary = spins[0]
		for sp in spins:   # いちばん長いスピナー
			if float(sp.end) - float(sp.t) > float(pick.end) - float(pick.t):
				pick = sp
		if float(pick.end) - float(pick.t) < 1.0:
			continue
		var m2 := _spin_metrics(cs.g2, pick)
		var m1 := _spin_metrics(cs.g1, pick)
		worst_free = minf(worst_free, m2.free_min)
		worst_comp = minf(worst_comp, m2.comp_min)
		v1_p += m1.persist
		v1_f += m1.free_min
		if _verbose:
			print("  spin %-12s %-14s ★%.1f %-9s %.1fs  v1 free %.0f%% pers %.2f / v2 free %.0f%% pers %.2f" % [cs.bm.title.left(12), cs.bm.version.left(14), cs.bm.stars, PatternGenV2.SPIN_NAMES[int(pick.kind)], float(pick.end) - float(pick.t), m1.free_min * 100.0, m1.persist, m2.free_min * 100.0, m2.persist])
		v2_f += m2.free_min
		v2_p += m2.persist
		n += 1
		_check(m2.free_min >= 0.40 and m2.comp_min >= 0.25, "%s [%s] スピナー(%s, %.1f 秒): 入れる場所 %.0f%%・つながり %.0f%% が足りない" % [
			cs.bm.title.left(12), cs.bm.version, PatternGenV2.SPIN_NAMES[int(pick.kind)], float(pick.end) - float(pick.t), m2.free_min * 100.0, m2.comp_min * 100.0])
	print("スピナーの型: %s / 測定 %d 個(%.1f 秒) / 入れる場所の最小 %.0f%%・つながりの最小 %.0f%% / 入れる場所の最小の平均: v1 %.0f%% → v2 %.0f%% / 安全なマスが 0.4 秒後も残る割合: v1 %.2f → v2 %.2f" % [
		str(kinds), n, (Time.get_ticks_usec() - t0) / 1000000.0, worst_free * 100.0, worst_comp * 100.0, v1_f * 100.0 / maxf(n, 1.0), v2_f * 100.0 / maxf(n, 1.0), v1_p / maxf(n, 1.0), v2_p / maxf(n, 1.0)])
	for i in range(4):
		_check(kinds[i] > 0, "スピナーの型 %s が、どの譜面でも選ばれていない" % PatternGenV2.SPIN_NAMES[i])
	if n >= 4:
		_check(v2_p < v1_p, "v2 のスピナーは、安全なマスが v1 より動く(%.2f < %.2f)" % [v2_p / n, v1_p / n])


## 参考(判定はしない): ふつうの区間(曲の 4 割あたりの 3 秒)の、入れる場所の最小と、安全なマスが残る割合。スピナーの難しさの目安にする。
func _print_normal_reference() -> void:
	var f1 := 0.0
	var f2 := 0.0
	var p1 := 0.0
	var p2 := 0.0
	var n := 0
	for cs in _cases:
		if cs.bm.stars < 4.0:
			continue
		var evs: Array = cs.g2.events
		var t_mid: float = float(evs[int(evs.size() * 0.4)].t)
		var w := {"t": t_mid, "end": t_mid + 3.0}
		var m2 := _spin_metrics(cs.g2, w, 4.0)
		var m1 := _spin_metrics(cs.g1, w, 4.0)
		f1 += m1.free_min
		f2 += m2.free_min
		p1 += m1.persist
		p2 += m2.persist
		n += 1
	if n > 0:
		print("参考(★4 以上の譜面の、ふつうの区間 3 秒 %d 個): 入れる場所の最小 v1 %.0f%% / v2 %.0f%%、安全なマスが残る割合 v1 %.2f / v2 %.2f" % [n, f1 * 100.0 / n, f2 * 100.0 / n, p1 / n, p2 / n])
