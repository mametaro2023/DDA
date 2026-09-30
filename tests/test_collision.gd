extends SceneTree
## 移動経路上の当たり判定(すり抜け防止)と、マウス相対移動の単体テスト。
## godot --headless --path . --script tests/test_collision.gd

const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var f := BulletField.new()

	# 1) 静止した弾を、1 フレームで 80px 飛び越える移動: 終点だけの判定ではすり抜ける
	f.add(Vector2(100, 100), Vector2.ZERO, 6.0, 0)
	f.update(1.0 / 60.0, Vector2(140, 100), 3.5, true)
	_check(not f.hit, "終点のみの判定(pprev なし)だと素通りする = 従来の挙動")
	f.clear()
	f.add(Vector2(100, 100), Vector2.ZERO, 6.0, 0)
	f.update(1.0 / 60.0, Vector2(140, 100), 3.5, true, Vector2(60, 100))
	_check(f.hit, "移動経路上の判定なら、飛び越えた弾に当たる")

	# 2) 経路が弾から十分離れていれば当たらない
	f.clear()
	f.add(Vector2(100, 130), Vector2.ZERO, 6.0, 0)
	f.update(1.0 / 60.0, Vector2(140, 100), 3.5, true, Vector2(60, 100))
	_check(not f.hit, "経路から 30px 離れた弾には当たらない")

	# 3) 無敵中(check_hit=false)は当たらない
	f.clear()
	f.add(Vector2(100, 100), Vector2.ZERO, 6.0, 0)
	f.update(1.0 / 60.0, Vector2(140, 100), 3.5, false, Vector2(60, 100))
	_check(not f.hit, "check_hit=false では当たらない")

	# 4) 相対移動: 移動量がそのまま反映され、アリーナ内にクランプされる。慣性・追従遅れがない
	var sim := GameSim.new()
	sim.setup(f, {"events": [], "gizmos": [], "warn_lead": 0.6}, 999.0, true)
	var start := sim.player_pos
	sim.step_relative(0.0, 1.0 / 60.0, Vector2(50, -40), false)
	_check(sim.player_pos.is_equal_approx(start + Vector2(50, -40)), "相対移動 (50,-40) がそのまま反映される")
	sim.step_relative(0.0, 1.0 / 60.0, Vector2.ZERO, false)
	_check(sim.player_pos.is_equal_approx(start + Vector2(50, -40)), "入力が 0 なら自機は 1px も動かない(勝手に動かない)")
	sim.step_relative(0.0, 1.0 / 60.0, Vector2(-5000, -5000), false)
	_check(sim.player_pos.is_equal_approx(Vector2(GameSim.PLAYER_MARGIN, GameSim.PLAYER_MARGIN)), "アリーナ端でクランプされる")
	sim.step_relative(0.0, 1.0 / 60.0, Vector2(300, 0), false)
	_check(is_equal_approx(sim.player_pos.x, GameSim.PLAYER_MARGIN + 300.0), "最大速度の上限はなく 1 フレームで 300px 動ける")

	f.free()
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
