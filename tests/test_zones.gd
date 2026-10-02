extends SceneTree
## 危険エリア(盤面の 3×3 のマス。小節ごとに、数・デバフの種類が変わる)の単体テスト。
## godot --headless --path . --script tests/test_zones.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Mods = preload("res://scripts/mods.gd")

const DT := 0.01

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_test_generation()
	_test_sim()
	print("test_zones: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


func _test_generation() -> void:
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
	_check(str(ge.zones) == str(PatternGen.generate(easy).zones), "決定的(同じ譜面なら同じ予定)")
	_check(ge.zones.size() >= 3 and gh.zones.size() >= 10, "エリアの予定がある(入門 %d 回・Chimera %d 回)" % [ge.zones.size(), gh.zones.size()])
	# 各回: 1〜8 マス・重複なし・0..8・最低 1 マスは安全
	var ok := true
	var min_n := 99
	var max_n := 0
	var sum_e := 0.0
	var sum_h := 0.0
	for pair in [[ge, 0], [gh, 1]]:
		for z in pair[0].zones:
			var seen := {}
			for c in z.cells:
				if int(c.c) < 0 or int(c.c) > 8 or seen.has(int(c.c)):
					ok = false
				seen[int(c.c)] = true
			if z.cells.size() < 1 or z.cells.size() > 8:
				ok = false
			min_n = mini(min_n, z.cells.size())
			max_n = maxi(max_n, z.cells.size())
			if pair[1] == 0:
				sum_e += z.cells.size()
			else:
				sum_h += z.cells.size()
	_check(ok and min_n >= 1 and max_n <= 8, "1 回のエリアは 1〜8 マス・重複なし(最小 %d・最大 %d)" % [min_n, max_n])
	_check(sum_h / gh.zones.size() > sum_e / ge.zones.size() + 2.0, "難易度が高いほど、危険エリアが多い(入門 平均 %.1f マス → Chimera 平均 %.1f マス)" % [sum_e / ge.zones.size(), sum_h / gh.zones.size()])
	var counts := {}
	for z in gh.zones:
		counts[z.cells.size()] = true
	_check(counts.size() >= 3, "1 譜面の中でも、エリアの数は一定でない(%d 通り)" % counts.size())
	# 種類: 入門は鈍足・脆弱だけ、高難度は 4 種類すべて
	var te := {}
	var th := {}
	for z in ge.zones:
		for c in z.cells:
			te[c.type] = true
	for z in gh.zones:
		for c in z.cells:
			th[c.type] = true
	_check(not te.has("poison") and not te.has("big") and te.size() >= 1, "入門のデバフは、鈍足・脆弱だけ(%s)" % str(te.keys()))
	_check(th.size() == 4, "高難度では 4 種類(鈍足・脆弱・毒・巨大)が出る(%s)" % str(th.keys()))
	# 小節の頭から始まり、順番で、重ならない。予告は直前の小節の間
	var starts := PatternGen.measure_starts(hard)
	var aligned := true
	var ordered := true
	var ahead := true
	var ahead_n := 0
	var before_first := false
	for i in range(gh.zones.size()):
		var z: Dictionary = gh.zones[i]
		var found := false
		for m in starts:
			if absf(float(m[0]) - float(z.t)) < 0.001:
				found = true
		if not found:
			aligned = false
		if i > 0 and float(z.t) < float(gh.zones[i - 1].end) - 0.001:
			ordered = false
		if float(z.lead) <= 0.0 or float(z.end) <= float(z.t):
			ordered = false
		var two := 0.0   # 予告は、発動の 2 小節前から
		for m in starts:
			if absf(float(m[0]) - (float(z.t) - float(z.lead))) < 0.001:
				two += 1.0
		if absf(float(z.lead) - _two_measures(starts, float(z.t))) > 0.001:
			ahead = false   # 予告の長さ = 直前の 2 小節の長さ
		if two >= 1.0:
			ahead_n += 1   # 予告の開始も小節の頭(拍子・テンポの変わり目をまたぐ回は、ずれることがある)
		if float(z.t) - float(z.lead) < hard.first_time() / 1000.0 - 0.001:
			before_first = true
	_check(aligned, "エリアの発動は、小節の頭に合っている")
	_check(ordered, "エリアは時刻順で重ならず、予告・終わりが正しい")
	_check(ahead and float(ahead_n) >= 0.8 * gh.zones.size(), "予告は、発動の 2 小節前から始まる(%d / %d 回が小節の頭から)" % [ahead_n, gh.zones.size()])
	_check(not before_first, "最初の弾の発射前には、予告も出ない")
	# MOD(加速)で時刻が詰まる
	var rush := Mods.apply(gh, Mods.params(["rush"]))
	var rate: float = Mods.params(["rush"]).rate
	_check(rush.zones.size() == gh.zones.size() and absf(float(rush.zones[3].t) - float(gh.zones[3].t) / rate) < 1e-6, "MOD(加速)で、エリアの時刻も 1/%.2f になる" % rate)


## 無害な弾を撃つだけ(エリアの確認用)の sim。zones を渡す。
func _make(zones: Array, breaks := [], practice := false, n := 1, host := true) -> Array:
	var shot := {"n": 1, "speed": 0.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	var events := [{"t": 0.1, "pos": Vector2(30, 30), "warn": false, "shots": [shot], "sfx": ""},
		{"t": 90.0, "pos": Vector2(30, 30), "warn": false, "shots": [shot], "sfx": ""}]   # 遅い 2 つ目: すぐにクリア(終了)しないように
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": events, "gizmos": [], "warn_lead": 0.6, "breaks": breaks, "zones": zones}, 100.0, practice, {})
	if n > 1:
		s.setup_coop(n, host)
	return [s, f]


## 発動の時刻 t の直前の 2 小節の長さの合計。
func _two_measures(starts: Array, t: float) -> float:
	var total := 0.0
	for i in range(starts.size()):
		if absf(float(starts[i][0]) - t) < 0.001 and i >= 2:
			total = float(starts[i - 2][1]) + float(starts[i - 1][1])
	return total


func _zone(t: float, end: float, cells: Array) -> Dictionary:
	return {"t": t, "end": end, "lead": 1.0, "cells": cells}


func _test_sim() -> void:
	_check(GameSim.zone_cell(Vector2(0, 0)) == 0 and GameSim.zone_cell(Vector2(959, 719)) == 8 and GameSim.zone_cell(Vector2(480, 360)) == 4 and GameSim.zone_cell(Vector2(700, 100)) == 2, "盤面の 3×3 のマス番号(左上 0 … 右下 8)")
	var right := func(_n: float) -> Vector2: return Vector2(1, 0)
	var mid := Vector2(480, 360)
	# 鈍足: 入っているマスだけ、移動が 0.45 倍
	var a := _make([_zone(0.0, 50.0, [{"c": 4, "type": "slow"}])])
	var s = a[0]
	s.player_pos = mid
	var x0: float = s.player_pos.x
	_run(s, 0.0, 0.5, right)
	var moved_slow: float = s.player_pos.x - x0
	var b := _make([])
	var s0 = b[0]
	s0.player_pos = mid
	_run(s0, 0.0, 0.5, right)
	var moved_norm: float = s0.player_pos.x - mid.x
	_check(absf(moved_slow / moved_norm - GameSim.ZONE_SLOW) < 0.03 and s.zone_debuff == "slow", "鈍足: 移動が %.2f 倍(%.0f px → %.0f px)" % [moved_slow / moved_norm, moved_norm, moved_slow])
	# 別のマスにいれば影響なし
	var c := _make([_zone(0.0, 50.0, [{"c": 0, "type": "slow"}])])
	var s1 = c[0]
	s1.player_pos = mid
	_run(s1, 0.0, 0.5, right)
	_check(absf((s1.player_pos.x - mid.x) - moved_norm) < 0.5 and s1.zone_debuff == "", "危険エリアでないマスでは、何も起きない")
	# 予告の間・終わったあとは効かない
	var d := _make([_zone(2.0, 4.0, [{"c": 4, "type": "slow"}])])
	var s2 = d[0]
	s2.player_pos = mid
	_run(s2, 0.0, 1.0, null)
	_check(s2.zone_debuff == "", "予告の間(発動前)は、効かない")
	_run(s2, 1.0, 2.0, null)
	_check(s2.zone_debuff == "slow", "発動したら効く")
	_run(s2, 3.0, 2.0, null)
	_check(s2.zone_debuff == "", "終わったら効かない")
	# 巨大: 当たり判定が大きくなる(通常は当たらない距離の弾に当たる)
	var near := mid + Vector2(10, 0)
	var e := _make([_zone(0.0, 50.0, [{"c": 4, "type": "big"}])])
	var s3 = e[0]
	s3.player_pos = mid
	s3.field.add(near, Vector2.ZERO, 6.0, 0, 0.0)
	_run(s3, 0.0, 0.05, null)
	var e2 := _make([])
	var s3b = e2[0]
	s3b.player_pos = mid
	s3b.field.add(near, Vector2.ZERO, 6.0, 0, 0.0)
	_run(s3b, 0.0, 0.05, null)
	_check(s3.gauge < 1.0 and s3b.gauge == 1.0 and absf(s3.hit_mult - GameSim.ZONE_BIG) < 1e-9, "巨大: 通常は当たらない距離(10px)の弾に当たる(当たり判定 %.1f 倍)" % s3.hit_mult)
	# 他の人の当たり判定の点の大きさ(描画用): 位置だけから、本人の判定と同じ倍率が求まる
	_check(absf(s3.hit_mult_at(mid, 0.05) - GameSim.ZONE_BIG) < 1e-9 and absf(s3.hit_mult_at(Vector2(10, 10), 0.05) - 1.0) < 1e-9,
		"他の人の当たり判定の倍率: 巨大のマスの中は %.1f 倍、外は 1 倍" % GameSim.ZONE_BIG)
	# マウス操作(相対移動)でも、鈍足が効く
	var f2 := _make([_zone(0.0, 50.0, [{"c": 4, "type": "slow"}])])
	var s4 = f2[0]
	s4.player_pos = mid
	s4.step_relative(0.0, DT, Vector2(100, 0), false)
	_check(absf((s4.player_pos.x - mid.x) - 45.0) < 0.5, "マウス操作: 鈍足は移動量 0.45 倍")
	# 脆弱: 被ダメージ 2 倍
	var h := _make([_zone(0.0, 50.0, [{"c": 4, "type": "fragile"}])])
	var s6 = h[0]
	s6.player_pos = mid
	s6.field.add(mid, Vector2.ZERO, 6.0, 0, 0.0)
	_run(s6, 0.0, 0.05, null)
	var i := _make([])
	var s7 = i[0]
	s7.player_pos = mid
	s7.field.add(mid, Vector2.ZERO, 6.0, 0, 0.0)
	_run(s7, 0.0, 0.05, null)
	var d_frag: float = 1.0 - s6.gauge
	var d_norm: float = 1.0 - s7.gauge
	_check(d_norm > 0.05 and absf(d_frag / d_norm - 2.0) < 0.1, "脆弱: 被ダメージが %.2f 倍(%.3f vs %.3f)" % [d_frag / d_norm, d_frag, d_norm])
	# 毒: ゲージが約 10%/秒で減る。休憩・練習では減らない
	var j := _make([_zone(0.0, 50.0, [{"c": 4, "type": "poison"}])])
	var s8 = j[0]
	s8.player_pos = mid
	_run(s8, 0.0, 2.0, null)
	_check(absf((1.0 - s8.gauge) - 0.2) < 0.04 and s8.damage_total > 0.15, "毒: 2 秒でゲージが約 20%% 減る(%.3f)・累計ダメージにも入る" % [1.0 - s8.gauge])
	var k := _make([_zone(0.0, 50.0, [{"c": 4, "type": "poison"}])], [[0.0, 50.0]])
	var s9 = k[0]
	s9.player_pos = mid
	_run(s9, 0.0, 2.0, null)
	_check(s9.gauge == 1.0 and s9.zone_debuff == "", "休憩の間は、デバフが効かない")
	var l := _make([_zone(0.0, 50.0, [{"c": 4, "type": "poison"}])], [], true)
	var s10 = l[0]
	s10.player_pos = mid
	_run(s10, 0.0, 2.0, null)
	_check(s10.gauge == 1.0 and s10.zone_debuff == "poison", "練習モードでは、毒でゲージは減らない")
	# 協力: 参加者の毒・脆弱は、被弾時間に換算してホストへ報告され、共有ゲージを減らす
	var host := _make([], [], false, 2, true)
	var cl := _make([_zone(0.0, 50.0, [{"c": 4, "type": "poison"}])], [], false, 2, false)
	var sc = cl[0]
	sc.player_pos = mid
	_run(sc, 0.0, 2.0, null)
	var rep: Dictionary = sc.take_contact()
	_check(rep.get("s", 0.0) > 0.01 and sc.gauge == 1.0, "参加者は、自分でゲージを減らさず、デバフによる追加ダメージを報告に溜める(%.3f 秒ぶん)" % rep.get("s", 0.0))
	host[0].ext_report(0.0, 0, 0, rep.s)
	_check(absf((1.0 - host[0].gauge) - rep.s / 0.5) < 1e-6, "ホストは、共有ゲージ(2 人で満タン = 0.5s)に換算して減らす(%.3f)" % host[0].gauge)
	var cl2 := _make([_zone(0.0, 50.0, [{"c": 4, "type": "fragile"}])], [], false, 2, false)
	var sf = cl2[0]
	sf.player_pos = mid
	sf.field.add(mid, Vector2.ZERO, 6.0, 0, 0.0)
	_run(sf, 0.0, 0.05, null)
	var rep2: Dictionary = sf.take_contact()
	_check(absf(rep2.s - rep2.c) < 0.002 and rep2.c > 0.04, "脆弱: 被弾した時間と同じだけ、追加ダメージを報告する(被弾 %.3f・追加 %.3f)" % [rep2.c, rep2.s])


func _run(s, from: float, secs: float, move_fn) -> float:
	var now := from
	var end := from + secs
	while now < end:
		var mv := Vector2.ZERO
		if move_fn != null:
			mv = move_fn.call(now)
		s.step(now, DT, mv, false)
		now += DT
	return now
