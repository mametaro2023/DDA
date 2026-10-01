extends SceneTree
## 協力モード(共有ゲージ・ホストの決定・自機狙いの配布)の単体テスト。
## godot --headless --path . --script tests/test_coop.gd

const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

const DT := 0.001

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _make(n: int, host: bool, events := [], breaks := [], end_t := 10.0, practice := false) -> Array:
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": events, "gizmos": [], "warn_lead": 0.6, "breaks": breaks}, end_t, practice, {})
	s.setup_coop(n, host)
	return [s, f]


func _shot(n: int, speed: float, aim: bool) -> Dictionary:
	return {"n": n, "speed": speed, "a0": 0.0, "spread": TAU, "fan": false, "aim": aim, "size": 6.0, "color": 0, "turn": 0.0}


func _ev(t: float, pos: Vector2, shots: Array) -> Dictionary:
	return {"t": t, "pos": pos, "warn": false, "shots": shots, "sfx": ""}


func _run(s, now: float, secs: float) -> float:
	var n := int(round(secs / DT))
	for i in range(n):
		s.step(now, DT, Vector2.ZERO, false)
		now += DT
	return now


func _init() -> void:
	# 1) 体力は人数に応じて増える: 2 人なら、ひとりで被弾し続けたときの 2 倍の時間(≒0.6 秒)でゲージが 0
	for n in [1, 2, 4]:
		var a := _make(n, true)
		var sim = a[0]
		sim.field.add(sim.player_pos, Vector2.ZERO, 6.0, 0, 0.0)
		var now := 0.0
		while not sim.finished and now < 5.0:
			sim.step(now, DT, Vector2.ZERO, false)
			now += DT
		_check(sim.failed and absf(sim.hit_time - 0.3 * n) < 0.01, "%d 人: 被弾し続けて %.3fs(≒%.1fs)でゲームオーバー" % [n, sim.hit_time, 0.3 * n])

	# 2) 参加者の被弾報告が共有ゲージを減らす(2 人: 0.25 秒ぶん = 満タンの 50%)
	var b := _make(2, true)
	var host = b[0]
	host.ext_report(0.25, 3, 1)
	_check(absf(host.gauge - 0.5) < 1e-6, "他の人の被弾 0.25s → ゲージ %.3f(2 人で満タン = 0.5s)" % host.gauge)
	_check(host.graze == 3 and host.hits == 1 and absf(host.hit_time - 0.25) < 1e-9, "グレイズ・被弾回数・被弾時間が合算される")
	_check(absf(host.damage_total - 0.5) < 1e-6, "累計ダメージは共有ゲージ基準(満タン = 1): %.3f" % host.damage_total)
	# 低体力(20% 以下)は半減
	host.gauge = 0.1
	host.ext_report(0.1, 0, 0)
	_check(absf(host.gauge - (0.1 - 0.1 / 0.5 * 0.5)) < 1e-6, "他の人の被弾でも低体力の半減が効く: %.3f" % host.gauge)
	# 直後はゲージが回復しない
	host.gauge = 0.5
	host.ext_report(0.01, 0, 0)
	var g0: float = host.gauge
	host.step(0.0, 0.05, Vector2.ZERO, false)
	_check(host.gauge <= g0 + 1e-9, "他の人が被弾した直後は回復しない")
	host.step(0.1, 0.5, Vector2.ZERO, false)
	host.step(0.6, 0.5, Vector2.ZERO, false)
	_check(host.gauge > g0, "しばらく被弾がなければ回復する")

	# 3) 参加者: 自分の被弾はホストへ報告するだけで、ゲージは動かない・ゲームオーバーにならない
	var c := _make(2, false)
	var cl = c[0]
	cl.field.add(cl.player_pos, Vector2.ZERO, 6.0, 0, 0.0)
	var now2 := _run(cl, 0.0, 1.0)
	_check(cl.gauge == 1.0 and not cl.failed and not cl.finished, "参加者は自分でゲージを減らさない・ゲームオーバーにしない")
	var rep: Dictionary = cl.take_contact()
	_check(absf(rep.c - 1.0) < 0.01 and rep.h == 1, "被弾 %.3fs・%d 回を報告に溜める" % [rep.c, rep.h])
	_check(cl.take_contact().is_empty(), "取り出すと空になる")
	_check(cl.just_hit or cl.hit_now, "自分の被弾の見た目・音のための状態は動く")
	# ホストの状態を反映
	cl.apply_net_state({"g": 0.42, "d": 1.3, "z": 7, "h": 2, "ht": 0.6})
	_check(absf(cl.gauge - 0.42) < 1e-9 and cl.graze == 7 and cl.hits == 2 and absf(cl.damage_factor - exp(-1.3 / cl.damage_tau)) < 1e-9, "ホストの共有状態を反映(ゲージ・グレイズ・被弾・ダメージ係数)")
	cl.apply_net_event({"k": "fail", "st": {"g": 0.0, "d": 3.0, "z": 7, "h": 5, "ht": 1.0}}, now2)
	_check(cl.failed and cl.finished and cl.score == 0.0, "ホストのゲームオーバーの通知で終わる")

	# 4) 自機狙いは、ホストが配った位置を使う(全員で同じ弾になる)
	var e := _ev(0.5, Vector2(400, 100), [_shot(1, 100.0, true)])
	var d := _make(2, false, [e])
	var s4 = d[0]
	s4.player_pos = Vector2(50, 50)   # 自分の位置は関係ない
	s4.aim_targets[0] = [Vector2(400, 500)]   # ホストが決めた目標(真下)
	s4.step(0.5, 0.001, Vector2.ZERO, false)
	var f4 = d[1]
	_check(f4.count == 1 and f4.vel[0].normalized().distance_to(Vector2.DOWN) < 0.01, "配られた目標(真下)へ撃つ: v=%s" % str(f4.vel[0]))
	# 配られていなければ、いま分かっている全員を狙う(1 人 1 発。誰かが狙われっぱなしにならない)
	var d2 := _make(2, true, [e])
	var s5 = d2[0]
	s5.slot_positions = [Vector2(100, 100), Vector2(700, 100)]
	s5.step(0.5, 0.001, Vector2.ZERO, false)
	var f5 = d2[1]
	_check(f5.count == 2 and f5.vel[0].x < 0.0 and f5.vel[1].x > 0.0, "全員を狙う: 1 発は左(スロット 0)、もう 1 発は右(スロット 1)へ")

	# 5) 休憩の一掃・クリアは、全員の周りが落ち着いてから(ホスト)
	var brk := _make(2, true, [_ev(0.1, Vector2(30, 30), [_shot(1, 0.0, false)]), _ev(9.0, Vector2(30, 30), [_shot(1, 0.0, false)])], [[1.0, 6.0]], 12.0, true)
	var s6 = brk[0]
	var f6 = brk[1]
	s6.slot_positions = [Vector2(480, 600), Vector2(480, 300)]
	s6.player_pos = s6.slot_positions[0]
	f6.add(Vector2(480, 320), Vector2.ZERO, 6.0, 0, 0.0)   # 2 人目のすぐそばに弾
	var t6 := _run(s6, 0.0, 1.5)
	_check(s6.break_clear_t < 0.0 and f6.count > 0, "2 人目のそばに弾があるうちは、休憩でも一掃しない")
	s6.slot_positions = [Vector2(480, 600), Vector2(480, 700)]
	t6 = _run(s6, t6, 0.2)
	_check(s6.break_clear_t >= 0.0 and f6.count == 0, "全員の周りが落ち着くと一掃する")
	_check(s6.net_events.any(func(x): return x.k == "wipe" and absf(x.end - 6.0) < 1e-6), "一掃の出来事をホストが配る")
	# 参加者へ反映
	var cl2 := _make(2, false, [], [[1.0, 6.0]])
	cl2[1].add(Vector2(300, 300), Vector2.ZERO, 6.0, 0, 0.0)
	cl2[0].apply_net_event({"k": "wipe", "end": 6.0}, 2.0)
	_check(cl2[1].count == 0 and cl2[0].break_clear_t == 2.0 and cl2[0].break_end_t == 6.0, "参加者も一掃してカウントダウンを始める")
	# 参加者は休憩が終わると状態を戻す
	cl2[0].step(7.0, 0.001, Vector2.ZERO, false)
	_check(cl2[0].break_clear_t < 0.0, "休憩が終わればカウントダウンの状態が戻る")

	# 6) クリア: ホストが決め、参加者へ配る
	var fin := _make(2, true, [_ev(0.1, Vector2(30, 30), [_shot(1, 0.0, false)])], [], 3.0, true)
	var s7 = fin[0]
	s7.slot_positions = [Vector2(480, 600), Vector2(480, 700)]
	s7.player_pos = s7.slot_positions[0]
	var t7 := _run(s7, 0.0, 0.5)
	fin[1].clear()
	t7 = _run(s7, t7, 0.1)
	_check(s7.finished and not s7.failed and s7.net_events.any(func(x): return x.k == "clear"), "撃ち終えて全員が落ち着いたらクリア。出来事を配る")
	var cl3 := _make(2, false)
	var ev: Dictionary = s7.net_events.filter(func(x): return x.k == "clear")[0]
	cl3[0].apply_net_event(ev, 1.0)
	_check(cl3[0].finished and not cl3[0].failed and cl3[0].score_progress == 1.0, "参加者もクリアになる")

	# 7) グレイズのボーナスは人数で割る(4 人で合計 40 でも、ひとり 10 と同じ)
	var g1 := _make(1, true)
	var g4 := _make(4, true)
	g1[0].graze = 10
	g4[0].graze = 40
	g1[0]._update_score()
	g4[0]._update_score()
	_check(absf(g1[0].score_graze - g4[0].score_graze) < 1e-6, "グレイズは人数の平均で数える(%.1f = %.1f)" % [g1[0].score_graze, g4[0].score_graze])

	print("test_coop: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
