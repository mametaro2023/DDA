extends SceneTree
## 弾速の実験(scripts/speed_study.gd): 条件の選び方・記録の読み書き・集計・同じ Lv に合わせた弾幕。
## godot --headless --path . --script tests/test_speed_study.gd

const SpeedStudy = preload("res://scripts/speed_study.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")

const TMP := "user://test_speed_study.csv"

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	# 参加するのは: 設定が入・ひとり・弾幕に効く MOD なし(練習は可)
	_check(SpeedStudy.eligible({"speed_study": true, "mods": []}, false), "設定が入・ひとり・MOD なしなら実験する")
	_check(SpeedStudy.eligible({"speed_study": true, "mods": ["practice"]}, false), "練習は弾幕を変えないので、実験してよい")
	_check(not SpeedStudy.eligible({"speed_study": false, "mods": []}, false), "設定が切なら実験しない")
	_check(not SpeedStudy.eligible({"speed_study": true, "mods": []}, true), "マルチプレイでは実験しない(全員で同じ弾幕にするため)")
	_check(not SpeedStudy.eligible({"speed_study": true, "mods": ["storm"]}, false) and not SpeedStudy.eligible({"speed_study": true, "mods": ["dark"]}, false),
		"弾幕・見え方に効く MOD があれば実験しない")

	# 条件は、その譜面で遊んだ回数が少ないものから(4 回で 4 条件がそろう)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rows: Array = []
	var seen := {}
	for i in range(4):
		var c := SpeedStudy.choose("A", rows, rng)
		seen[c] = true
		rows.append({"map": "A", "cond": c})
	_check(seen.size() == 4, "4 回遊ぶと、4 つの条件が 1 回ずつになる: %s" % str(seen.keys()))
	rows.append({"map": "B", "cond": "base"})
	_check(SpeedStudy.choose("B", rows, rng) != "base", "ほかの譜面の回数は数えない(B は base だけ遊んだので、次は base 以外)")

	# 記録の読み書き(「,」を含む名前でも列がずれない)
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	SpeedStudy.record({"map": "X, Y [Hard]", "cond": "fast", "hit_ms": 1200, "played_s": 60.0, "failed": 0, "progress": 1.0}, TMP)
	SpeedStudy.record({"map": "X, Y [Hard]", "cond": "slow", "hit_ms": 600, "played_s": 60.0, "failed": 1, "progress": 0.5}, TMP)
	var back := SpeedStudy.read_rows(TMP)
	_check(back.size() == 2 and str(back[0].map) == "X  Y [Hard]" and str(back[0].cond) == "fast" and is_equal_approx(float(back[0].hit_ms), 1200.0)
		and is_equal_approx(float(back[1].failed), 1.0), "記録を書いて読み戻せる(%d 行)" % back.size())
	DirAccess.remove_absolute(TMP)

	# 集計: 作った記録から、比と SPEED_EXP の推定が出る
	#   dense は base の 1.25^2 倍(β = 2)、fast/slow = 1.5625^1(→ 推定 = SPEED_EXP + 1/2)
	var synth: Array = []
	for m in range(6):
		var base := 0.5 + 0.1 * m
		for c in ["base", "slow", "fast", "dense"]:
			var rate := base
			match c:
				"dense": rate = base * 1.5625
				"fast": rate = base * 1.25
				"slow": rate = base / 1.25
			synth.append({"map": "M%d" % m, "cond": c, "hit_ms": rate * 1000.0, "played_s": 60.0, "failed": 0.0, "progress": 1.0})
	var s := SpeedStudy.summarize(synth)
	_check(absf(float(s.ratios.dense.ratio) - 1.5625) < 1e-4 and absf(float(s.ratios["fast/slow"].ratio) - 1.5625) < 1e-4, "比が出る(dense/base %.3f, fast/slow %.3f)" % [s.ratios.dense.ratio, s.ratios["fast/slow"].ratio])
	_check(s.estimate != null and absf(float(s.estimate) - (PatternGen.SPEED_EXP + 0.5)) < 1e-3, "SPEED_EXP の推定 = 今の値 + log(fast/slow) / (β log 1.5625) = %.3f" % (s.estimate if s.estimate != null else -1.0))
	var few := SpeedStudy.summarize(synth.slice(0, 8))
	_check(few.estimate == null and str(few.note).contains("足りません"), "データが少ないうちは推定を出さない: " + str(few.note))

	# 同じ Lv に合わせた弾幕: 弾速 ×0.8 / ×1.25 でも Lv(長さの補正なし)は目標の 8% 以内、弾数は速いほど少ない
	var path := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
	var loader := OszLoader.new()
	if FileAccess.file_exists(path) and loader.open(path):
		for bm in loader.difficulties:
			if not bm.version in ["Misuzu's Normal", "Insane"]:
				continue
			var lv := {}
			var mean := {}
			for c in ["slow", "base", "fast"]:
				var g := PatternGen.generate(bm, {"speed_mul": SpeedStudy.CONDITIONS[c].speed_mul})
				lv[c] = PatternGen.level_of(g.rating.score, g.speed, g.size)
				mean[c] = g.rating.mean
				_check(absf(float(lv[c]) - float(g.target_level)) <= float(g.target_level) * 0.08, "%s %s: Lv %.2f が目標 %.2f に合う" % [bm.version, c, lv[c], g.target_level])
			_check(float(mean.fast) < float(mean.base) and float(mean.base) < float(mean.slow), "%s: 同じ Lv なら、速い弾ほど画面内の弾は少ない(%.0f / %.0f / %.0f)" % [bm.version, mean.slow, mean.base, mean.fast])
	else:
		print("skip: 譜面がないので、弾幕の確認は飛ばす")
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
