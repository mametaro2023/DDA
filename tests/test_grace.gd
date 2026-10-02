extends SceneTree
## 自機の近くで撃たれた弾の猶予(game_sim.gd の SAFE_RADIUS / SAFE_GRACE_PX / GRACE_STREAK_*)。
## 猶予は「不意打ち」を防ぐためのもので、同じ場所で待ち続けて近くから撃たれ続ける(スピナーの中央に居座る)と、途中から効かなくなる。
## godot --headless --path . --script tests/test_grace.gd

const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")

const DT := 1.0 / 240.0
const CENTER := Vector2(480, 360)

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## スピナーと同じ形の弾幕: 中央から、t0〜t1 の間 interval 秒ごとに、arms 本の腕を回しながら撃つ。
func _spinner(t0: float, t1: float, interval := 0.12, arms := 4) -> Array:
	var out: Array = []
	var t := t0
	var a := 0.0
	while t < t1:
		var shot := {"n": arms, "speed": 130.0, "a0": a, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
		out.append({"t": t, "pos": CENTER, "warn": false, "shots": [shot], "sfx": ""})
		a += 0.42
		t += interval
	return out


func _burst(t: float, pos: Vector2, n := 16) -> Dictionary:
	var shot := {"n": n, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	return {"t": t, "pos": pos, "warn": false, "shots": [shot], "sfx": ""}


## 練習モードで end_t 秒まで走らせる。move_fn(t) -> 移動の向き(キーボードと同じ)。被弾回数・被弾時間と、被弾したときの中央からの距離を返す。
func _play(events: Array, end_t: float, start: Vector2, move_fn := Callable()) -> Dictionary:
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": events, "gizmos": [], "warn_lead": 0.6, "breaks": []}, end_t, true, {"practice": true})
	s.player_pos = start
	var now := 0.0
	var dists: Array = []
	while not s.finished and now < end_t + 3.0:
		var mv: Vector2 = move_fn.call(now) if move_fn.is_valid() else Vector2.ZERO
		var h0: int = s.hits
		s.step(now, DT, mv, false)
		if s.hits > h0:
			dists.append(s.player_pos.distance_to(CENTER))
		now += DT
	var near := 0
	for d in dists:
		if d < 200.0:
			near += 1
	var out := {"hits": s.hits, "hit_s": s.hit_time, "near_hits": near}
	f.free()
	return out


func _init() -> void:
	# 1) 不意打ちは今までどおり防ぐ: 自機のすぐ近くで撃たれた 1 回の弾は、自機を通り過ぎるまで当たらない
	var r1 := _play([_burst(1.0, CENTER + Vector2(20, 0))], 4.0, CENTER)
	_check(r1.hits == 0, "自機のすぐ近くで 1 回撃たれても、当たらない(猶予): 被弾 %d 回" % r1.hits)

	# 2) スピナーの中央に居座ると、途中から当たる(すべて避けられる悪用を防ぐ)
	var r2 := _play(_spinner(1.0, 5.0), 6.0, CENTER)
	_check(r2.near_hits > 0 and r2.hit_s > 0.5, "スピナーの中央に居座ると、猶予が切れて当たる: 被弾 %d 回 / %.2f 秒" % [r2.hits, r2.hit_s])

	# 3) 始まったら中央から離れれば、離れる途中で当たらない(スピナーの開始に中央にいただけで、理不尽に当たらない)
	#    (このテストの自機は画面の端で止まるので、端で腕に当たるのは数えない: 中央から 200px 以内での被弾だけを見る)
	var leave := func(t: float) -> Vector2:
		return Vector2(0, 1) if t >= 1.25 else Vector2.ZERO
	var r3 := _play(_spinner(1.0, 5.0), 6.0, CENTER, leave)
	_check(r3.near_hits == 0, "スピナーが始まって 0.25 秒で中央から離れれば、離れる途中で当たらない: 中央付近での被弾 %d 回" % r3.near_hits)

	# 4) 間が空けば、猶予は数え直す: 同じ場所でも、離れた時刻の不意打ちはどちらも防ぐ
	var r4 := _play([_burst(1.0, CENTER + Vector2(20, 0)), _burst(1.0 + GameSim.GRACE_STREAK_GAP + 1.5, CENTER + Vector2(-20, 0))], 5.0, CENTER)
	_check(r4.hits == 0, "%.1f 秒以上空いた 2 回の不意打ちは、どちらも当たらない: 被弾 %d 回" % [GameSim.GRACE_STREAK_GAP + 1.5, r4.hits])

	# 5) 猶予の続く時間の中なら、続けて撃たれても当たらない(速い連打の頭で、近くに来たときなど)
	var r5 := _play(_spinner(1.0, 1.0 + GameSim.GRACE_STREAK_MAX * 0.8), 4.0, CENTER)
	_check(r5.hits == 0, "%.2f 秒以内の連続した近くの発射は、すべて猶予がつく: 被弾 %d 回" % [GameSim.GRACE_STREAK_MAX * 0.8, r5.hits])
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
