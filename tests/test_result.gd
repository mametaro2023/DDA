extends SceneTree
## 結果画面の部品の単体テスト(体力の間引き・復元、ランクの境目がゲームの表と一致)。
## godot --headless --path . --script tests/test_result.gd

const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const RankMeter = preload("res://scripts/ui/rank_meter.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	# ランクの境目: メーターの範囲は、GameSim.RANK_TABLE と同じ値(S 95% / A 85% / B 70% / C 55% / D 40%)
	var same := true
	for r in GameSim.RANK_TABLE:
		var i: int = RankMeter.RANKS.find(r[0])
		same = same and i >= 1 and absf(float(RankMeter.BOUNDS[i]) - float(r[1])) < 1e-6
	_check(same and RankMeter.RANKS.size() == GameSim.RANK_TABLE.size() + 1, "メーターのランクの境目が、ゲームの表(RANK_TABLE)と同じ")
	_check(GameSim.rank_of(false, 3, 949999.0, 1000000.0) == "A" and GameSim.rank_of(false, 3, 950000.0, 1000000.0) == "S" and GameSim.rank_of(false, 0, 100.0, 1000000.0) == "SS", "境目ちょうどでランクが変わる(S は 95%、ノーミスは SS)")

	# 体力のサンプルから点列、間引き、復元
	var log := PackedFloat32Array()
	for i in range(41):   # 0..10 秒。5 秒で 1.0 → 0.5 へ落ち、そのあと一定
		log.append(1.0 if i < 20 else 0.5)
	var pts := HpGraph.points_from_log(log, 0.25, 10.0, 0.5)
	_check(pts.size() == 41 and absf(pts[0].x) < 1e-6 and absf(pts[40].x - 10.0) < 1e-6, "サンプルから点列を作る(時刻は番号 × 刻み)")
	var pts2 := HpGraph.points_from_log(log, 0.25, 12.0, 0.0)
	_check(pts2.size() == 42 and absf(pts2[41].x - 12.0) < 1e-6 and pts2[41].y == 0.0, "終わりの時刻と最後の値(ゲームオーバーなら 0)が最後に付く")
	var small := HpGraph.downsample(pts, 48)
	_check(small.size() == 48 and small[0] == 100 and small[47] == 50, "間引くと 48 個(最初 100%、最後 50%)")
	var back := HpGraph.points_from_samples(small, 10.0)
	_check(back.size() == 48 and absf(back[47].x - 10.0) < 1e-6 and absf(back[47].y - 0.5) < 1e-6, "間引いたものから点列に戻せる(長さ 10 秒)")
	var mid := HpGraph.downsample(pts, 5)
	_check(mid.size() == 5 and mid[0] == 100 and mid[1] == 100 and mid[4] == 50, "5 個に間引いても、形が保たれる: %s" % str(mid))
	_check(HpGraph.downsample(PackedVector2Array(), 8).is_empty(), "点がなければ空")
	# グラフの横軸を、最初のノーツ〜最後のノーツに切る(境目は補間。途中で終わる線は、そのまま)
	var line := PackedVector2Array([Vector2(0, 1.0), Vector2(4, 0.6), Vector2(8, 0.2), Vector2(12, 1.0)])
	var cut := HpGraph.clip_range(line, 2.0, 10.0)
	_check(cut.size() == 4 and cut[0].is_equal_approx(Vector2(2, 0.8)) and cut[3].is_equal_approx(Vector2(10, 0.6)),
		"範囲の両端を補間して切る(%s)" % str(cut))
	var dead := HpGraph.clip_range(PackedVector2Array([Vector2(0, 1.0), Vector2(4, 0.5), Vector2(6, 0.0)]), 2.0, 10.0)
	_check(dead.size() == 3 and is_equal_approx(dead[dead.size() - 1].x, 6.0), "ゲームオーバーの線は、範囲の途中で終わる(%s)" % str(dead))

	# ゲーム側の記録
	var sim := GameSim.new()
	var field := preload("res://scripts/game/bullet_field.gd").new()
	sim.setup(field, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 10.0, false, {})
	var t := 0.0
	while t < 3.0:
		sim.step(t, 0.01, Vector2.ZERO, false)
		t += 0.01
	_check(sim.gauge_log.size() == 12 and absf(sim.log_end_t - 2.99) < 0.02, "ゲージの記録: 0.25 秒ごと(3 秒で %d 個)" % sim.gauge_log.size())
	var sim2 := GameSim.new()
	sim2.setup(field, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": []}, 10.0, false, {})
	sim2.step(-1.0, 0.01, Vector2.ZERO, false)
	_check(sim2.gauge_log.is_empty(), "曲の時刻が 0 になる前は、記録しない")

	print("test_result: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
