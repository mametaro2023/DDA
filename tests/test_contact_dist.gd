extends SceneTree
## 弾に触れたときのダメージが、「触れていた時間」と「弾の中を通った距離 ÷ 基準速度」の長いほうで決まることを確かめる。
## 速く動いて弾を抜けても、ダメージが減りすぎない(キーボードの最高速で抜けるより軽くならない)。
## godot --headless --path . --script tests/test_contact_dist.gd

const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _make(coop_guest := false) -> Array:
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 100.0, true, {})   # practice: ゲームオーバーにならない
	if coop_guest:
		s.setup_coop(2, false)
	return [s, f]


## 自機を (x0, y) から x 方向へ speed px/s で動かし、置いてある 1 つの静止した弾(中心 (xb, y)、半径 6)を、まっすぐ通り抜ける。
## dt 秒ごとのステップ(マウスの 1 フレームぶんの移動を、そのまま 1 ステップで動かす場合も含む)。ダメージ量(ゲージ満タン = 1)を返す。
func _cross(speed: float, dt: float, guest := false) -> Dictionary:
	var a := _make(guest)
	var s = a[0]
	var f = a[1]
	var y := 300.0
	s.player_pos = Vector2(100.0, y)
	f.add(Vector2(400.0, y), Vector2.ZERO, 6.0, 0, 0.0)
	var now := 0.0
	var dist := 0.0
	while s.player_pos.x < 700.0:
		var step_px := speed * dt
		s.step_relative(now, dt, Vector2(step_px, 0.0), false)
		now += dt
		dist += step_px
	return {"damage": s.damage_total, "own": s.own_damage, "hit_time": s.hit_time, "contact_dt": s.contact_dt, "contact_extra": s.contact_extra, "sim": s}


func _init() -> void:
	# 弾の当たり判定: 自機 3.5×1.15 + 弾 6×0.7 = 8.225px。まっすぐ通ると、中を通る長さ(弦)は 16.45px
	var chord := 2.0 * (GameSim.PLAYER_HIT_R * GameSim.PLAYER_SIZE_MUL + 6.0 * BulletField.HIT_SCALE)
	var ref := GameSim.CONTACT_SPEED_REF
	var full := chord / ref / GameSim.GAUGE_DRAIN_TIME   # 基準速度で抜けたときのダメージ(ゲージ満タン = 1)
	print("弾の中を通る長さ %.2fpx、基準速度 %.0fpx/s で抜けると ダメージ %.3f" % [chord, ref, full])

	# 1) 基準速度以下は、これまでと同じ(触れていた時間 ÷ 0.25)
	var slow := _cross(100.0, 0.001)
	var want_slow := chord / 100.0 / GameSim.GAUGE_DRAIN_TIME
	_check(absf(slow.damage - want_slow) < want_slow * 0.03, "遅い(100px/s): 触れていた時間どおり %.3f(期待 %.3f)" % [slow.damage, want_slow])
	var at_ref := _cross(ref, 0.001)
	_check(absf(at_ref.damage - full) < full * 0.03, "基準速度(%.0fpx/s)でも、同じ %.3f(期待 %.3f)" % [ref, at_ref.damage, full])

	# 2) 基準速度より速く抜けても、ダメージは基準速度で抜けたときと同じ(距離で決まる)
	for spd in [760.0, 1500.0, 3000.0, 8000.0]:
		var r := _cross(spd, 0.001)
		_check(absf(r.damage - full) < full * 0.05, "%.0fpx/s で抜けても %.3f(基準速度で抜けたときの %.3f と同じ)" % [spd, r.damage, full])
		_check(absf(r.hit_time - chord / spd) < 0.003, "  被弾時間は実際の時間のまま %.1fms(期待 %.1fms)" % [r.hit_time * 1000.0, chord / spd * 1000.0])

	# 3) 1 フレームぶんの大きな移動を 1 ステップで動かしても(マウスを弾く)、同じ。通り抜けたのに、請求しすぎない
	for spd in [3000.0, 12000.0]:
		var r2 := _cross(spd, 1.0 / 60.0)
		_check(r2.damage > full * 0.6 and r2.damage < full * 1.15, "1/60 秒ごとのステップ(%.0fpx/s: 1 ステップ %.0fpx)でも %.3f(基準 %.3f。弾の幅を超えて請求しない)" % [spd, spd / 60.0, r2.damage, full])

	# 4) 自機が止まっていて、弾が通り過ぎるときは、これまでどおり時間で決まる(弾の速度で、ダメージは変わらない)
	var a := _make()
	var s = a[0]
	var f = a[1]
	s.player_pos = Vector2(400.0, 300.0)
	f.add(Vector2(200.0, 300.0), Vector2(200.0, 0.0), 6.0, 0, 0.0)
	var now := 0.0
	for i in range(1500):
		s.step_relative(now, 0.001, Vector2.ZERO, false)
		now += 0.001
	_check(absf(s.damage_total - s.hit_time / GameSim.GAUGE_DRAIN_TIME) < 0.001 and s.hit_time > 0.05, "止まっている自機に弾が通り過ぎる: 触れていた時間 %.0fms のぶん、%.3f" % [s.hit_time * 1000.0, s.damage_total])

	# 5) 協力の参加者: ホストへは、触れていた時間と、追加ダメージ(速く動いたぶん)に分けて送る。合わせると、ホストで同じダメージになる
	var g := _cross(3000.0, 0.001, true)
	var host_a := _make()
	var hs = host_a[0]
	hs.setup_coop(2, true)
	var start_gauge: float = hs.gauge
	hs.ext_report(g.contact_dt, 0, 0, g.contact_extra)
	var drained: float = start_gauge - hs.gauge
	var want_coop := chord / ref / (GameSim.GAUGE_DRAIN_TIME * 2.0)   # 協力は、ゲージ満タン = 人数ぶんの被弾時間
	_check(g.contact_extra > 0.0 and absf(g.contact_dt - chord / 3000.0) < 0.003, "参加者: 実際の時間 %.1fms + 追加 %.1fms を送る" % [g.contact_dt * 1000.0, g.contact_extra * 1000.0])
	_check(absf(drained - want_coop) < want_coop * 0.06, "ホストで減るゲージ %.4f(期待 %.4f)。ひとりで抜けた場合と同じ割合" % [drained, want_coop])

	# 6) 自分ひとりぶんのダメージ量(結果画面・HUD に出す)は、damage_total と同じ値(ひとり用)
	var solo := _cross(1500.0, 0.001)
	_check(absf(solo.own - solo.damage) < 1e-9, "ひとり用: own_damage = damage_total (%.3f)" % solo.own)

	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
