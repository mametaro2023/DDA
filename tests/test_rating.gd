extends SceneTree
## Danmaku 難易度(画面内の弾数 + 弾速・弾サイズの項。Lv は★と同じ目盛り)を、手元の全 .osz について表示し、
## 目標への追従と、公式の星との順位相関を確認する。
## godot --headless --path . --script tests/test_rating.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")

## 譜面セットごとの公式星評価(難易度名 → ★)。ファイルが無いセットは飛ばす。
const SETS := [
	["320118 Reol - No title.osz", {
		"Irre's Beginner": 1.42, "Celsius' Easy": 2.11, "Misuzu's Normal": 2.48,
		"byfaR's Hard": 3.67, "Light Insane": 4.38, "toybot's Insane": 4.72,
		"Insane": 5.25, "Celsius' Extra": 5.53, "deetz' Expert": 5.64,
		"Nathan's Extra": 5.71, "Lust's Insane": 5.72, "Leader's Light Extra": 5.88,
		"Fast's Expert": 5.94, "jieusieu's Lemur": 6.64}],
	["241526 Soleily - Renatus.osz", {"Normal": 2.22, "Hard": 3.53, "Insane": 5.27}],
	# 高難度側(★8 台まで)の検証用
	["813569 Laur - Sound Chimera.osz", {
		"Orthrus": 4.77, "Typhon": 6.61, "KoToreley's Echidna": 6.74, "Chimera": 8.22}],
]
const DIR := "C:/Desktop/my_apps/DDA/"

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	# 目標表: 表の外側でも単調に増え、逆引きと対称であること(★6.7 で頭打ちにならない)
	var prev := -1.0
	var mono := true
	var sym := true
	for s in [1.0, 2.0, 3.7, 5.9, 6.7, 7.5, 8.3, 9.5, 11.0]:
		var sc := PatternGen.target_score_for(s)
		if sc <= prev:
			mono = false
		prev = sc
		if absf(PatternGen.stars_for_score(sc) - s) > 0.02:
			sym = false
	_check(mono, "目標の弾数は★に対して単調に増える(★6.7 より上でも)")
	_check(sym, "target_score_for と stars_for_score が互いに逆(★1〜11)")
	_check(PatternGen.target_score_for(8.3) > PatternGen.target_score_for(6.7) + 30.0, "★8.3 の目標は★6.7 より十分大きい")

	# 危険半径は実際の当たり判定と同じ式(弾・自機の大きさの倍率を含む)。基準の大きさでは補正が 1(Lv の数値は倍率に左右されない)
	_check(PatternGen.HIT_SCALE == BulletField.HIT_SCALE and PatternGen.PLAYER_HIT_R == GameSim.PLAYER_HIT_R \
			and GameSim.BULLET_SIZE_MUL == PatternGen.BULLET_SIZE_MUL and GameSim.PLAYER_SIZE_MUL == PatternGen.PLAYER_SIZE_MUL,
		"Lv の計算の当たり判定の値が、実際の弾・自機と同じ")
	_check(is_equal_approx(PatternGen.danger_radius(6.75), PatternGen.DANGER_REF), "基準の弾サイズ 6.75 では、弾サイズの補正が 1")
	_check(is_equal_approx(PatternGen.danger_radius(8.0, 7.0), BulletField.HIT_SCALE * 8.0 * GameSim.BULLET_SIZE_MUL + 7.0 * GameSim.PLAYER_SIZE_MUL),
		"危険半径 = 実際の弾の当たり判定 + 実際の自機の当たり判定(巨人など自機の半径を変えても)")

	# 長さの補正は休憩地帯を除いて測る(計測区間 10〜70 秒の中の休憩は引き、区間の外は影響しない)
	var two: Array = [{"t": 10.0, "pos": Vector2(480, 360), "warn": true, "shots": [{"n": 1, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.75, "color": 0, "turn": 0.0}], "sfx": ""},
		{"t": 70.0, "pos": Vector2(480, 360), "warn": true, "shots": [{"n": 1, "speed": 150.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.75, "color": 0, "turn": 0.0}], "sfx": ""}]
	var d_all: float = PatternGen.measure(two).duration
	var d_in: float = PatternGen.measure(two, [[20.0, 40.0]]).duration
	var d_edge: float = PatternGen.measure(two, [[0.0, 15.0], [65.0, 90.0]]).duration
	var d_out: float = PatternGen.measure(two, [[80.0, 90.0]]).duration
	_check(is_equal_approx(d_all, 60.0) and is_equal_approx(d_in, 40.0) and is_equal_approx(d_edge, 50.0) and is_equal_approx(d_out, 60.0),
		"長さは休憩を除いて測る: 休憩なし %.1f / 中に 20 秒 %.1f / 端にかかる 5+5 秒 %.1f / 区間の外 %.1f" % [d_all, d_in, d_edge, d_out])

	var rows: Array = []
	for s in SETS:
		var loader := OszLoader.new()
		if not FileAccess.file_exists(DIR + s[0]) or not loader.open(DIR + s[0]):
			print("skip: ", s[0])
			continue
		for bm in loader.difficulties:
			if not s[1].has(bm.version):
				continue
			var t := Time.get_ticks_usec()
			var g := PatternGen.generate(bm)
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			var g2 := PatternGen.generate(bm)
			_check(is_equal_approx(g.level, g2.level), "non-deterministic " + bm.version)
			rows.append({"set": s[0].substr(0, 6), "bm": bm, "g": g, "off": s[1][bm.version], "ms": ms})
	rows.sort_custom(func(a, b): return a.off < b.off)
	print("%-6s %-20s %8s %6s | %5s %5s %5s | %6s %6s | %5s %5s" % [
		"set", "difficulty", "official", "est★", "mean", "p95", "peak", "target", "Lv", "speed", "size"])
	for r in rows:
		var m: Dictionary = r.g.rating
		print("%-6s %-20s %8.2f %6.2f | %5.0f %5.0f %5.0f | %6.2f %6.2f | %5.0f %5.1f" % [
			r.set, r.bm.version, r.off, r.g.stars, m.mean, m.p95, m.peak, r.g.target_level, r.g.level, r.g.speed, r.g.size])
		# 生成が合わせるのは密度(長さの補正を除いた Lv)。長さの補正は Lv の計算でだけ足す
		var dens_lv: float = PatternGen.level_of(m.score, r.g.speed, r.g.size)
		_check(absf(dens_lv - r.g.target_level) <= r.g.target_level * 0.08,
			"%s %s: Lv(長さ補正なし) %.2f が目標 %.2f から 8%% 以上ずれている" % [r.set, r.bm.version, dens_lv, r.g.target_level])
		# 推定★が公式から大きく外れていない(目標そのものが正しいこと)
		_check(absf(r.g.stars - r.off) <= 0.8, "%s %s: 推定★ %.2f が公式 %.2f から 0.8 以上ずれている" % [r.set, r.bm.version, r.g.stars, r.off])

	# 公式星との順位相関(Spearman)
	var n := rows.size()
	if n >= 3:
		var by_lv := rows.duplicate()
		by_lv.sort_custom(func(a, b): return a.g.level < b.g.level)
		var rank_lv := {}
		for i in range(n):
			rank_lv[by_lv[i].set + by_lv[i].bm.version] = i
		var d2 := 0.0
		for i in range(n):  # rows は公式星順 = rank i
			var d: float = i - rank_lv[rows[i].set + rows[i].bm.version]
			d2 += d * d
		var rho := 1.0 - 6.0 * d2 / (n * (n * n - 1.0))
		print("Spearman(Lv, 公式★) = %.3f  (n=%d)" % [rho, n])
		_check(rho > 0.9, "公式★との順位相関が低い")
		# 最も高い譜面の Lv が、推定★に追従して 7 を超えること(高難度側の頭打ちの回帰テスト)
		var top = rows[n - 1]
		if top.off > 8.0:
			_check(top.g.level > 7.5, "★%.1f の譜面の Lv が 7.5 を超える (%.2f)" % [top.off, top.g.level])

	# 長さ(持久力)の補正: 基準の長さで 1、長いほど大きく、短いほど小さく、上下限で頭打ち。Lv は長い譜面ほど高い
	_check(is_equal_approx(PatternGen.length_factor(PatternGen.LENGTH_REF), 1.0), "基準の長さ(%.0f 秒)の補正は 1" % PatternGen.LENGTH_REF)
	_check(PatternGen.length_factor(300.0) > PatternGen.length_factor(150.0) and PatternGen.length_factor(150.0) > 1.0, "長いほど補正は大きい")
	_check(PatternGen.length_factor(30.0) < PatternGen.length_factor(60.0) and PatternGen.length_factor(60.0) < 1.0, "短いほど補正は小さい")
	_check(PatternGen.length_factor(1.0) == PatternGen.LENGTH_MIN and PatternGen.length_factor(100000.0) == PatternGen.LENGTH_MAX, "補正は上下限で頭打ち")
	_check(PatternGen.length_factor(0.0) == 1.0, "長さが 0(弾なし)なら補正なし")
	_check(PatternGen.level_of(100.0, 150.0, 6.75, 3.5, 300.0) > PatternGen.level_of(100.0, 150.0, 6.75, 3.5, 60.0), "同じ密度なら、長い譜面のほうが Lv が高い")

	# 難易度は「最初のノーツ」から測る: 曲頭のイントロ(譜面のない区間)の長さに依存しない
	if n >= 1:
		var evs: Array = rows[n / 2].g.events
		var base: Dictionary = PatternGen.measure(evs)
		var shifted: Array = []
		for e in evs:
			var e2: Dictionary = e.duplicate()
			e2["t"] = e.t + 30.0   # イントロが 30 秒長い譜面と同じ
			shifted.append(e2)
		var m2: Dictionary = PatternGen.measure(shifted)
		_check(absf(m2.mean - base.mean) < 0.0001 and absf(m2.p95 - base.p95) < 0.0001 and absf(m2.peak - base.peak) < 0.0001,
			"イントロを 30 秒延ばしても難易度は変わらない (mean %.2f → %.2f)" % [base.mean, m2.mean])
		# 弾を撃たないイベント(スピナー開始など)が先頭にあっても、計測の開始位置にならない
		var with_empty: Array = [{"t": 1.0, "pos": Vector2.ZERO, "warn": true, "shots": [], "sfx": ""}]
		with_empty.append_array(evs)
		var m3: Dictionary = PatternGen.measure(with_empty)
		_check(absf(m3.mean - base.mean) < 0.0001, "弾を撃たないイベントが先頭にあっても難易度は変わらない (mean %.2f → %.2f)" % [base.mean, m3.mean])

	# density_mul が Lv に反映され、弾速も星に応じて単調に変わること
	if n >= 3:
		var mid = rows[n / 2].bm
		var lo: float = PatternGen.rate(mid, 0.5).level
		var m1: float = PatternGen.rate(mid, 1.0).level
		var hi: float = PatternGen.rate(mid, 1.5).level
		print("density_mul 0.5/1.0/1.5 -> Lv %.2f / %.2f / %.2f" % [lo, m1, hi])
		_check(lo < m1 and m1 < hi, "density_mul で Lv が単調に変わる")
		_check(rows[0].g.speed < rows[n - 1].g.speed, "弾速が星に応じて上がる")
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
