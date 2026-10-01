extends SceneTree
## ゲージ制・スコア・休憩地帯の単体テスト。
## godot --headless --path . --script tests/test_gauge.gd

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Mods = preload("res://scripts/mods.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

const DT := 1.0 / 60.0

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _make(practice: bool, end_t := 10.0, breaks := [], events := [], mods := {}) -> Array:
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": events, "gizmos": [], "warn_lead": 0.6, "breaks": breaks}, end_t, practice, mods)
	return [s, f]


## t 秒に n 発(止まったまま)撃つイベント。弾は自機に当たらない位置(左上)に置く。
func _ev(t: float, n: int) -> Dictionary:
	var shot := {"n": n, "speed": 0.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	return {"t": t, "pos": Vector2(60, 60), "warn": false, "shots": [shot], "sfx": ""}


## 自機の位置に静止した弾を置く(当たり続ける)。
func _put_bullet_on_player(s, f) -> void:
	f.add(s.player_pos, Vector2.ZERO, 6.0, 0, 0.0)


## 自機の周り(半径 15px)に、当たらないがグレイズになる静止した弾を n 発置く。
func _put_graze_bullets(s, f, n: int) -> void:
	for i in range(n):
		var ang := TAU * float(i) / float(n)
		f.add(s.player_pos + Vector2.from_angle(ang) * 15.0, Vector2.ZERO, 6.0, 0, 0.0)


## n ステップ進める。now を返す。
func _run(s, now: float, n: int) -> float:
	for i in range(n):
		s.step(now, DT, Vector2.ZERO, false)
		now += DT
	return now


func _init() -> void:
	# --- ゲージ ---
	# 1) 当たり続けると、20% までは 250ms 基準、以降は半減で合計約 300ms でゲージが 0 になる
	var a := _make(false)
	var sim = a[0]
	var f = a[1]
	_put_bullet_on_player(sim, f)
	var now := 0.0
	var frames := 0
	while not sim.finished and frames < 120:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
		frames += 1
	_check(sim.failed, "被弾し続けるとゲームオーバーになる")
	_check(absf(sim.hit_time - 0.3) <= DT * 2.0, "連続被弾で %.3fs ≒ 0.3s(250ms×0.8 + 半減した残り 20%%)でゲージが 0" % sim.hit_time)
	_check(sim.hits == 1, "連続した被弾は 1 回と数える (hits=%d)" % sim.hits)

	# 2) 20% 以下では被ダメージが半分。通常時: 1 フレームで dt/0.25 減る。しきい値を確実に下回った後は、その半分
	a = _make(true)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	var g_prev: float = sim.gauge
	now = _run(sim, 0.0, 1)
	var full_step: float = g_prev - sim.gauge
	_check(absf(full_step - DT / GameSim.GAUGE_DRAIN_TIME) < 0.001, "通常時: 1 フレームで %.4f 減る(= dt / 250ms)" % full_step)
	while sim.gauge > 0.18:
		now = _run(sim, now, 1)
	g_prev = sim.gauge
	now = _run(sim, now, 1)
	var low_step: float = g_prev - sim.gauge
	_check(absf(low_step - full_step * 0.5) < 0.001, "ゲージ 20%% 以下(%.2f)では被ダメージが半分: 1 フレームで %.4f 減る" % [g_prev, low_step])

	# 3) 練習モードはゲージ 0 でも続行。ゲージは 0 で止まる
	a = _make(true)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 300)
	_check(not sim.failed and not sim.finished, "練習モードはゲージ 0 でも続行する")
	_check(sim.gauge == 0.0, "ゲージは 0 で下げ止まる (%.3f)" % sim.gauge)

	# 4) 回復: 被弾していないときはごくわずか。休憩地帯では回復しない
	a = _make(false, 100.0)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 6)  # 0.1 秒被弾
	f.clear()
	var g0: float = sim.gauge
	now = _run(sim, now, 300)  # 5 秒
	var regen: float = sim.gauge - g0
	_check(absf(regen - GameSim.GAUGE_REGEN * 5.0) < 0.01, "休憩地帯の外: 5 秒で %.3f 回復する(毎秒 %.2f)" % [regen, GameSim.GAUGE_REGEN])

	a = _make(false, 100.0, [[0.0, 50.0]])
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 6)
	f.clear()
	g0 = sim.gauge
	now = _run(sim, now, 300)
	_check(sim.gauge == g0, "休憩地帯の中: ゲージは回復しない (%.3f → %.3f)" % [g0, sim.gauge])
	_check(sim.in_break(1.0) and not sim.in_break(60.0), "in_break が休憩地帯の内外を判定する")

	# 5) 別々の被弾は別に数える
	a = _make(true, 100.0)
	sim = a[0]
	f = a[1]
	now = 0.0
	for burst in range(2):
		_put_bullet_on_player(sim, f)
		now = _run(sim, now, 6)
		f.clear()
		now = _run(sim, now, 30)
	_check(sim.hits == 2, "0.5 秒あけた 2 回の被弾は 2 回 (hits=%d)" % sim.hits)

	# --- スコア ---
	# 6) ノーダメージ・グレイズなしで完走 = 1,000,000。開始時点から 1,000,000
	a = _make(false, 10.0)
	sim = a[0]
	_check(sim.score == 0.0 and sim.score_potential == 1000000.0, "開始時点の表示点数は 0(進捗 0%)、今クリアした場合の点数は 1,000,000")
	now = 0.0
	while not sim.finished:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
	_check(sim.score == 1000000.0 and not sim.failed, "ノーダメージ・グレイズなしの完走は 1,000,000")

	# 7) グレイズのボーナスは 30,000(3%)に漸近する(無限大で 30,000)。基本点とは別に足される
	a = _make(false, 10.0)
	sim = a[0]
	sim.graze = 100000
	now = _run(sim, 0.0, 10)
	_check(absf(sim.score_potential - 1030000.0) < 1.0, "ノーダメージ+グレイズ満点なら最終点は 1,030,000 (%.0f)" % sim.score_potential)
	_check(absf(sim.score_graze - 30000.0) < 0.01, "グレイズが十分多ければ、ボーナスは 30,000 に限りなく近づく")
	# 漸近: 増えるほど単調に増えるが、上乗せは小さくなり、30,000 には届かない
	var tau := GameSim.GRAZE_TAU_MIN   # イベントなしの譜面では下限
	var prev_b := 0.0
	var prev_gain := INF
	var mono_b := true
	var shrink := true
	for gz in [0, 5, 10, 20, 40, 80, 160]:
		a = _make(false, 10.0)
		sim = a[0]
		sim.graze = gz
		_run(sim, 0.0, 1)
		var bonus: float = sim.score_graze
		if gz > 0:
			if bonus <= prev_b or bonus >= 30000.0:
				mono_b = false
			var gain := (bonus - prev_b) / float(gz - (0 if gz == 5 else gz / 2))
			if gain >= prev_gain:
				shrink = false
			prev_gain = gain
		prev_b = bonus
	_check(mono_b, "グレイズが増えるほどボーナスは増え続けるが、30,000 には届かない")
	_check(shrink, "1 回あたりの上乗せは、グレイズが増えるほど小さくなる")
	a = _make(false, 10.0)
	sim = a[0]
	sim.graze = int(tau)
	_run(sim, 0.0, 1)
	_check(absf(sim.score_graze - 30000.0 * (1.0 - exp(-1.0))) < 0.5, "グレイズ数 = graze_tau で、最大の約 63%% (%.0f)" % sim.score_graze)
	a = _make(false, 10.0)
	sim = a[0]
	sim.graze = 200
	_run(sim, 0.0, 1)
	_check(sim.score_graze < 30000.0 and sim.score_graze > 29999.0, "グレイズ 200 回でも 30,000 未満 (%.6f)" % sim.score_graze)

	# 8) 被ダメージ係数 = exp(-累計ダメージ / τ)(τ = DAMAGE_TAU = 3)。0.1 秒の被弾(累計ダメージ 0.4)で係数 exp(-0.4/3) ≒ 0.875
	a = _make(true, 100.0)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 6)
	f.clear()
	var expect_factor := exp(-0.4 / GameSim.DAMAGE_TAU)
	_check(absf(sim.damage_total - 0.4) < 0.01, "0.1 秒の被弾で累計ダメージ 0.4 (%.3f)" % sim.damage_total)
	_check(absf(sim.damage_factor - expect_factor) < 0.005, "被ダメージ係数 = exp(-D/τ) = %.4f (%.4f)" % [expect_factor, sim.damage_factor])
	_check(absf(sim.score_potential - 1000000.0 * sim.damage_factor) < 1.0, "最終点 = 1,000,000 × 係数 = %.0f" % sim.score_potential)
	# 回復してもいったん下がった係数は戻らない
	var factor_after_hit: float = sim.damage_factor
	now = _run(sim, now, 600)
	_check(sim.damage_factor == factor_after_hit, "ゲージが回復しても被ダメージ係数は戻らない (%.4f)" % sim.damage_factor)

	# 8b) 係数は「ベース 100 万 + グレイズボーナス」の全体にかかる(掛け算)
	a = _make(true, 100.0)
	sim = a[0]
	f = a[1]
	sim.graze = 100000
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 6)
	f.clear()
	var gross := 1000000.0 + 30000.0
	_check(absf(sim.score_gross - gross) < 0.01, "係数を掛ける前の点数は 1,030,000 (%.0f)" % sim.score_gross)
	_check(absf(sim.score_potential - gross * sim.damage_factor) < 1.0, "最終点 = (1,000,000 + グレイズ 30,000) × 係数 = %.0f" % sim.score_potential)

	# 9) 係数は 0 に漸近する: 被弾し続けるほど下がり続けるが、0 にはならず、マイナスにもならない
	a = _make(true, 1000.0)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 600)  # 10 秒被弾し続ける
	var s10: float = sim.score_potential
	now = _run(sim, now, 600)  # さらに 10 秒
	var s20: float = sim.score_potential
	_check(s10 > 0.0 and s20 > 0.0, "何秒被弾し続けても 0 にはならない (10秒後 %.2f / 20秒後 %.4f)" % [s10, s20])
	_check(s20 < s10, "被弾し続けるほど 0 に近づく(単調に減る)")
	_check(s10 < 5000.0, "十分被弾すると 0 に近い値になる (%.2f)" % s10)

	# 9b) 累計ダメージが増えるほど、係数は単調に小さくなる
	var prev_factor := 2.0
	var mono := true
	for d in [0.0, 0.2, 0.5, 1.0, 2.0, 4.0, 8.0]:
		var fac := exp(-d / GameSim.DAMAGE_TAU)
		if fac >= prev_factor:
			mono = false
		prev_factor = fac
	_check(mono and exp(-8.0 / GameSim.DAMAGE_TAU) > 0.0, "係数は累計ダメージに対して単調減少で、正の値のまま")

	# 10) ゲームオーバーは常に 0 点(グレイズが満点でも)
	a = _make(false, 10.0)
	sim = a[0]
	f = a[1]
	sim.graze = 100000
	_put_bullet_on_player(sim, f)
	now = 0.0
	while not sim.finished:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
	_check(sim.failed and sim.score == 0.0 and sim.score_gross == 0.0 and sim.score_graze == 0.0,
		"ゲームオーバーは 0 点(スコアなし)")


	# --- 休憩地帯 ---
	# 11) 休憩地帯のグレイズは数えず、スコアも上がらない
	a = _make(false, 100.0, [[0.0, 50.0]])
	sim = a[0]
	f = a[1]
	_put_graze_bullets(sim, f, 30)
	var s_before: float = sim.score_potential
	now = _run(sim, 0.0, 3)
	_check(sim.graze == 0 and sim.score_potential == s_before, "休憩地帯の中のグレイズは数えず、スコアも上がらない (graze=%d)" % sim.graze)

	a = _make(false, 100.0)
	sim = a[0]
	f = a[1]
	_put_graze_bullets(sim, f, 30)
	s_before = sim.score_potential
	now = _run(sim, 0.0, 3)
	_check(sim.graze == 30 and sim.score_potential > s_before, "休憩地帯の外では同じグレイズが数えられ、スコアが上がる (graze=%d)" % sim.graze)

	# 12) 休憩地帯でもダメージは受ける(無効になるのは加点と回復だけ)
	a = _make(false, 100.0, [[0.0, 50.0]])
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, 6)
	_check(sim.gauge < 0.7 and sim.damage_factor < 1.0, "休憩地帯でも被弾すればゲージも被ダメージ係数も下がる")


	# --- 発射した弾数に応じたスコアの増加 ---
	# 13) スコア進捗 = 発射した弾数 / 全弾数。最初のノーツまで(イントロ)は増えず、弾が発射されるたびに増える
	#     3.0 秒に 10 発、4.0 秒に 30 発、8.0 秒に 60 発(合計 100 発)
	var evs := [_ev(3.0, 10), _ev(4.0, 30), _ev(8.0, 60)]
	a = _make(false, 10.0, [], evs)
	sim = a[0]
	f = a[1]
	_check(sim.bullets_total == 100, "全弾数は 100 発 (%d)" % sim.bullets_total)
	now = _run(sim, 0.0, 179)  # 2.98 秒(イントロ)
	_check(sim.score == 0.0 and sim.bullets_fired == 0, "最初のノーツ(3.0 秒)までは、スコアは増えない (%.0f)" % sim.score)
	now = _run(sim, now, 3)    # 3.0 秒を過ぎる → 10 発
	_check(sim.bullets_fired == 10 and absf(sim.score - 100000.0) < 1.0, "10 発撃つと 10%% 進む: 100,000 (%.0f)" % sim.score)
	now = _run(sim, now, 60)   # 4.0 秒を過ぎる → 累計 40 発
	_check(sim.bullets_fired == 40 and absf(sim.score - 400000.0) < 1.0, "累計 40 発で 400,000 (%.0f)" % sim.score)
	var s40: float = sim.score
	now = _run(sim, now, 150)  # 6.5 秒ごろ: 発射がない間は増えない
	_check(sim.score == s40, "弾が発射されない間はスコアが増えない (%.0f)" % sim.score)
	var prev := -1.0
	var rising := true
	while not sim.finished:
		sim.step(now, DT, Vector2.ZERO, false)
		if sim.score < prev - 0.0001:
			rising = false
		prev = sim.score
		now += DT
	_check(rising, "ノーダメージならスコアは減らない")
	_check(sim.bullets_fired == 100 and sim.score == 1000000.0, "全弾を撃ち終えると最終点 1,000,000 (%.0f)" % sim.score)
	_check(sim.progress == 1.0 and sim.score_progress == 1.0, "クリア時、進行率もスコア進捗も 100%")

	# 14) 休憩地帯(5〜7 秒)の発射は数えない(全弾数にも含めない)。休憩中はスコアが増えない
	evs = [_ev(3.0, 50), _ev(6.0, 999), _ev(8.0, 50)]
	a = _make(false, 10.0, [[5.0, 7.0]], evs)
	sim = a[0]
	f = a[1]
	_check(sim.bullets_total == 100, "休憩地帯の発射は全弾数に含めない (%d)" % sim.bullets_total)
	now = _run(sim, 0.0, 240)   # 4.0 秒: 50 発
	var s_pre: float = sim.score
	now = _run(sim, now, 150)   # 6.5 秒: 休憩中の 999 発が発射される
	_check(sim.bullets_fired == 50 and sim.score == s_pre, "休憩中に発射された弾は数えず、スコアも増えない (%.0f)" % sim.score)
	_check(absf(sim.progress - 0.65) < 0.01, "曲の進行率(時間)は休憩中も進む (%.3f)" % sim.progress)
	while not sim.finished:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
	_check(sim.score == 1000000.0, "休憩を挟んでも、クリアで最終点 1,000,000 になる (%.0f)" % sim.score)

	# 15) ダメージを受けると係数が全体にかかるので、その時点の表示点数も下がる
	evs = [_ev(1.0, 50), _ev(6.0, 50)]
	a = _make(true, 10.0, [], evs)
	sim = a[0]
	f = a[1]
	now = _run(sim, 0.0, 300)   # 5 秒: 50 発
	var s_before_hit: float = sim.score
	_put_bullet_on_player(sim, f)
	now = _run(sim, now, 6)
	f.clear()
	_check(sim.score < s_before_hit and s_before_hit > 0.0, "被弾すると表示点数も下がる (%.0f → %.0f)" % [s_before_hit, sim.score])

	# --- MOD ---
	# 16) 合成: MOD なしは既定値のまま。地獄は 弾サイズ 1.35 倍 / 体力 150ms / 半減なし / ベース +6%
	var none: Dictionary = Mods.params([])
	_check(none.size_mul == 1.0 and none.drain_time == GameSim.GAUGE_DRAIN_TIME and none.low_protect and none.score_mul == 1.0,
		"MOD なしは既定の設定")
	var hell: Dictionary = Mods.params(["hell"])
	_check(hell.size_mul == 1.35 and absf(hell.drain_time - 0.15) < 1e-9 and not hell.low_protect and absf(hell.score_mul - 1.06) < 1e-9,
		"地獄: 弾サイズ ×1.35 / 体力 150ms / 低体力の半減なし / ベーススコア ×1.06")
	_check(Mods.params(["hell", "hell", "nope"]).ids == ["hell"], "重複・未知の MOD id は無視する")

	# 17) 地獄: 当たり続けると 150ms でゲージ 0(半減がないので、20% 以下でも減る速さは変わらない)
	a = _make(false, 10.0, [], [], hell)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = 0.0
	frames = 0
	while not sim.finished and frames < 120:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
		frames += 1
	_check(sim.failed and absf(sim.hit_time - 0.15) <= DT * 2.0, "地獄: 連続被弾 %.3fs ≒ 0.15s でゲージ 0" % sim.hit_time)
	a = _make(true, 10.0, [], [], hell)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	g_prev = sim.gauge
	now = _run(sim, 0.0, 1)
	full_step = g_prev - sim.gauge
	_check(absf(full_step - DT / 0.15) < 0.001, "地獄: 1 フレームで %.4f 減る(= dt / 150ms)" % full_step)
	while sim.gauge > 0.18:
		now = _run(sim, now, 1)
	g_prev = sim.gauge
	now = _run(sim, now, 1)
	_check(absf((g_prev - sim.gauge) - full_step) < 0.001, "地獄: ゲージ 20%% 以下(%.2f)でも被ダメージは半減しない: 1 フレームで %.4f" % [g_prev, g_prev - sim.gauge])

	# 18) 地獄: ベーススコア +6%。グレイズのボーナスは別(+30,000 のまま)、被ダメージ係数は全体にかかる
	a = _make(false, 10.0, [], [], hell)
	sim = a[0]
	sim.graze = 100000
	now = _run(sim, 0.0, 10)
	_check(absf(sim.score_gross - (1060000.0 + 30000.0)) < 0.5, "地獄: 係数を掛ける前の点数 = 1,060,000 + グレイズ 30,000 (%.0f)" % sim.score_gross)
	a = _make(false, 10.0, [], [], hell)
	sim = a[0]
	now = 0.0
	while not sim.finished:
		sim.step(now, DT, Vector2.ZERO, false)
		now += DT
	_check(absf(sim.score - 1060000.0) < 0.5 and not sim.failed, "地獄: ノーダメージ・グレイズなしの完走は 1,060,000 (%.0f)" % sim.score)

	# 19) 効果の合成(すべて乗算)。ベーススコアは 1.06 を 2 つ付けたら 1.06 × 1.06
	var storm: Dictionary = Mods.params(["storm"])
	# 弾速の倍率(speed_mul)は MOD の効果の 1 つとして残してある。単独で付ける MOD は今はないので、合成の辞書を直接作って確かめる
	var gale: Dictionary = Mods.params(["storm"])
	gale.speed_mul = 2.0
	gale.count_mul = 1.0
	var giant: Dictionary = Mods.params(["giant"])
	var rush: Dictionary = Mods.params(["rush"])
	_check(storm.count_mul == 1.5 and storm.speed_mul == 1.5 and absf(storm.score_mul - 1.06) < 1e-9, "暴風雨: 弾の量 ×1.5(+50%) / 弾の速度 ×1.5(+50%) / ベーススコア ×1.06")
	_check(Mods.find("gale").is_empty(), "疾風は暴風雨に統合された(単独の MOD としてはない)")
	_check(giant.player_scale == 3.0 and absf(giant.score_mul - 1.06) < 1e-9, "巨人: 自機サイズ ×3(+200%) / ベーススコア ×1.06")
	_check(rush.rate == 1.5 and absf(rush.score_mul - 1.12) < 1e-9, "加速: 再生速度 ×1.5 / ベーススコア ×1.12")
	_check(absf(Mods.params(["storm", "giant"]).score_mul - 1.06 * 1.06) < 1e-9, "6%% を 2 つ重ねると 1.06 × 1.06 = %.4f" % (1.06 * 1.06))
	var all4: Dictionary = Mods.params(["hell", "storm", "giant", "rush"])
	_check(absf(all4.score_mul - 1.06 * 1.06 * 1.06 * 1.12) < 1e-9, "4 つ重ねると 1.06^3 × 1.12 = %.4f" % all4.score_mul)
	_check(all4.size_mul == 1.35 and all4.count_mul == 1.5 and all4.speed_mul == 1.5 and all4.player_scale == 3.0 and all4.rate == 1.5,
		"重ねても、それぞれの効果は自分の倍率のまま")
	_check(Mods.names(["hell", "rush"]) == "地獄 + 加速", "MOD 名の表示")

	# 20) apply: 弾幕への効果と、MOD 適用後の難易度(Lv)。合成用の弾幕: 1 秒ごとに 7 発のリングを 20 回
	var mevs: Array = []
	for i in range(20):
		var ev := _ev(2.0 + i, 7)
		ev.pos = Vector2(480, 360)
		ev.shots[0].speed = 150.0
		mevs.append(ev)
	var gen0 := {"events": mevs, "gizmos": [{"kind": "slider", "t": 3.0, "end": 6.0, "span": 3.0, "repeats": 1, "color": 0}],
		"breaks": [[9.0, 12.0]], "warn_lead": 0.6, "speed": 150.0, "size": 6.0, "stars": 3.0}
	var meas: Dictionary = PatternGen.measure(mevs)
	gen0["rating"] = meas
	gen0["level"] = PatternGen.level_of(meas.score, 150.0, 6.0, PatternGen.PLAYER_HIT_R, meas.duration)
	var none_gen: Dictionary = Mods.apply(gen0, Mods.params([]))
	_check(none_gen.level == gen0.level and none_gen.base_level == gen0.level and none_gen.events == gen0.events, "MOD なしは弾幕も Lv も変えない")

	var g_storm: Dictionary = Mods.apply(gen0, storm)
	var total0 := 0
	var total1 := 0
	for i in range(mevs.size()):
		total0 += mevs[i].shots[0].n
		total1 += g_storm.events[i].shots[0].n
	_check(absi(total1 - int(round(total0 * 1.5))) <= 1, "暴風雨: 弾数が 1.5 倍(+50%%) (%d → %d)" % [total0, total1])
	_check(g_storm.events[0].shots[0].speed == 225.0 and g_storm.speed == 225.0 and g_storm.events[0].shots[0].size == 6.0, "暴風雨: 弾速が 1.5 倍で、弾サイズは変わらない")
	_check(g_storm.level > gen0.level and g_storm.base_level == gen0.level, "暴風雨: MOD 適用後の Lv のほうが高い (%.2f → %.2f)" % [gen0.level, g_storm.level])

	var g_gale: Dictionary = Mods.apply(gen0, gale)
	_check(g_gale.events[0].shots[0].speed == 300.0 and g_gale.events[0].shots[0].n == 7 and g_gale.speed == 300.0, "弾速の倍率だけ: 弾速が 2 倍で、弾数は同じ")
	_check(g_gale.level > gen0.level, "弾速の倍率だけ: 弾速が上がると Lv も上がる (%.2f → %.2f)" % [gen0.level, g_gale.level])
	_check(g_gale.rating.mean < gen0.rating.mean, "弾速の倍率だけ: 速い弾は画面内に残る時間が短く、画面内の弾数は減る (%.1f → %.1f)" % [gen0.rating.mean, g_gale.rating.mean])

	var g_giant: Dictionary = Mods.apply(gen0, giant)
	_check(g_giant.events[0].shots[0].n == 7 and g_giant.rating.score == gen0.rating.score, "巨人: 弾幕は変わらない")
	_check(g_giant.level > gen0.level, "巨人: 自機が大きいと Lv が上がる (%.2f → %.2f)" % [gen0.level, g_giant.level])

	var g_rush: Dictionary = Mods.apply(gen0, rush)
	_check(absf(g_rush.events[3].t - 5.0 / 1.5) < 1e-9 and absf(g_rush.events[19].t - 21.0 / 1.5) < 1e-9, "加速: 発射時刻が 1/1.5 になる")
	_check(absf(g_rush.gizmos[0].t - 2.0) < 1e-9 and absf(g_rush.gizmos[0].end - 4.0) < 1e-9 and absf(g_rush.gizmos[0].span - 2.0) < 1e-9,
		"加速: スライダーの軌道(開始・終了・1 往復の長さ)も 1/1.5")
	_check(absf(g_rush.breaks[0][0] - 6.0) < 1e-9 and absf(g_rush.breaks[0][1] - 8.0) < 1e-9, "加速: 休憩地帯も 1/1.5")
	_check(g_rush.events[0].shots[0].speed == 150.0 and g_rush.warn_lead == 0.6, "加速: 弾速・予兆の長さは実時間のまま")
	_check(g_rush.level > gen0.level, "加速: 発射が詰まると Lv が上がる (%.2f → %.2f)" % [gen0.level, g_rush.level])
	_check(gen0.events[3].t == 5.0 and gen0.gizmos[0].t == 3.0 and gen0.breaks[0][0] == 9.0, "元の gen は変わらない")

	var g_hell: Dictionary = Mods.apply(gen0, hell)
	_check(absf(g_hell.events[0].shots[0].size - 8.1) < 1e-6 and g_hell.level > gen0.level, "地獄: 弾サイズ 6.0 → 8.1 で Lv も上がる (%.2f → %.2f)" % [gen0.level, g_hell.level])
	# 同じ shot を複数のイベントが共有していても、サイズは二重に掛からない
	var shared := {"events": [_ev(1.0, 5), _ev(2.0, 5)], "gizmos": [], "warn_lead": 0.6, "speed": 150.0, "size": 6.0, "stars": 3.0,
		"rating": {"mean": 0.0, "p95": 0.0, "peak": 0.0, "score": 0.0}, "level": 1.0}
	shared.events[0].shots[0].speed = 150.0
	shared.events[1].shots = shared.events[0].shots
	var g_sh: Dictionary = Mods.apply(shared, hell)
	_check(absf(g_sh.events[0].shots[0].size - 8.1) < 1e-6 and absf(g_sh.events[1].shots[0].size - 8.1) < 1e-6 and shared.events[0].shots[0].size == 6.0,
		"共有した shot でもサイズは 1 回だけ掛かる")

	# 重ねると、効果ごとに乗算される
	var g_all: Dictionary = Mods.apply(gen0, all4)
	_check(g_all.level > g_hell.level and g_all.level > g_rush.level and g_all.level > g_gale.level, "重ねると Lv はさらに上がる (%.2f)" % g_all.level)

	# 21) 自機サイズ: 当たり判定の半径が 3 倍になる(標準も PLAYER_SIZE_MUL 倍)。距離 9px の静止弾に、通常は当たらず、巨人なら当たる
	for mod_ids in [[], ["giant"]]:
		a = _make(true, 10.0, [], [], Mods.params(mod_ids))
		sim = a[0]
		f = a[1]
		f.add(sim.player_pos + Vector2(9, 0), Vector2.ZERO, 6.0, 0, 0.0)
		now = _run(sim, 0.0, 2)
		if mod_ids.is_empty():
			_check(absf(sim.player_r - 3.5 * GameSim.PLAYER_SIZE_MUL) < 1e-9 and sim.hits == 0, "MOD なし: 自機の当たり判定 %.2fpx、9px 先の弾には当たらない" % sim.player_r)
		else:
			_check(absf(sim.player_r - 10.5 * GameSim.PLAYER_SIZE_MUL) < 1e-9 and sim.hits == 1, "巨人: 自機の当たり判定 %.2fpx(3 倍)、同じ弾に当たる" % sim.player_r)

	# --- イントロのスキップ ---
	# 20) 最初に弾を撃つイベントの時刻を持つ(弾を撃たないイベントは飛ばす)
	var empty_ev := {"t": 1.0, "pos": Vector2.ZERO, "warn": true, "shots": [], "sfx": ""}
	a = _make(false, 100.0, [], [empty_ev, _ev(12.0, 5), _ev(13.0, 5)])
	_check(a[0].first_fire_time == 12.0, "first_fire_time は最初に弾を撃つイベント (%.2f)" % a[0].first_fire_time)
	a = _make(false, 100.0, [], [])
	_check(a[0].first_fire_time < 0.0, "弾がなければ first_fire_time は -1")

	# --- 自機の周りが落ち着いているか(is_calm) / 休憩中の一掃 / クリア ---
	var pc := Vector2(480, 612)   # 自機の位置
	var bf := BulletField.new()
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "弾が 1 発もなければ落ち着いている")
	bf.add(pc + Vector2(100, 0), Vector2.ZERO, 6.0, 0)
	_check(not bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "近く(100px)の弾があれば落ち着いていない")
	bf.clear()
	bf.add(pc + Vector2(300, 0), Vector2.ZERO, 6.0, 0)
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "300px 先で止まっている弾は無視できる")
	bf.clear()
	bf.add(pc + Vector2(300, 0), Vector2(-200, 0), 6.0, 0)
	_check(not bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "遠くても、自機に向かってくる弾(1.5 秒で到達)は落ち着いていない")
	bf.clear()
	bf.add(pc + Vector2(300, 0), Vector2(200, 0), 6.0, 0)
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "遠ざかる弾は無視できる")
	bf.clear()
	bf.add(pc + Vector2(300, 0), Vector2(-200, -150), 6.0, 0)
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "自機の脇(進路が 50px 以上離れる)を通る弾は無視できる")
	bf.clear()
	bf.add(pc + Vector2(900, 0), Vector2(-100, 0), 6.0, 0)
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "向かってきても、3 秒以内に届かない弾は無視できる")
	bf.clear()
	bf.add(pc + Vector2(200, -300), Vector2(0, 100), 6.0, 0, 0.0, 1.0)
	_check(bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "旋回する弾も、先を調べて届かなければ無視できる")
	bf.clear()
	bf.add(pc + Vector2(200, 0), Vector2(-200, 0), 6.0, 0, 0.0, 0.3)
	_check(not bf.is_calm(pc, 3.5, 120.0, 50.0, 3.0), "旋回する弾でも、自機に向かってくれば落ち着いていない")
	var fast := _ev(1.0, 12)
	fast.shots[0].speed = 500.0
	# 休憩 [3, 10]: 弾が抜けたら一掃してカウントダウンを始める(休憩の終わり = 10)
	a = _make(true, 100.0, [[3.0, 10.0]], [fast, _ev(11.0, 1)])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	now = _run(sim, 0.0, int(2.9 / DT))
	_check(f.count > 0 and sim.break_clear_t < 0.0, "休憩の前は弾があり、一掃していない")
	now = _run(sim, now, int(1.5 / DT))
	_check(sim.break_clear_t >= 3.0 and f.count == 0, "休憩中、弾が抜けたら一掃する (t=%.2f, 残り %d 発)" % [sim.break_clear_t, f.count])
	_check(absf(sim.break_end_t - 10.0) < 1e-6, "カウントダウンの終点は休憩の終わり (%.2f)" % sim.break_end_t)
	now = _run(sim, now, int(6.0 / DT))
	_check(sim.break_clear_t < 0.0, "休憩が終わったらカウントダウンの状態を戻す")
	# 自機の近くに止まった弾があるあいだは、休憩中でも一掃しない。自機から遠い弾しかなければ、止まっていても一掃する
	a = _make(true, 100.0, [[3.0, 10.0]], [_ev(11.0, 1)])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	f.add(sim.player_pos + Vector2(100, 0), Vector2.ZERO, 6.0, 0)
	now = _run(sim, 0.0, int(5.0 / DT))
	_check(sim.break_clear_t < 0.0 and f.count == 1, "自機の近く(100px)に弾が残っていれば、休憩中でも一掃しない")
	a = _make(true, 100.0, [[3.0, 10.0]], [_ev(11.0, 1)])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	f.add(Vector2(60, 60), Vector2.ZERO, 6.0, 0)   # 自機(480, 612)から 690px
	now = _run(sim, 0.0, int(3.5 / DT))
	_check(sim.break_clear_t >= 3.0 and f.count == 0, "自機から遠い弾しかなければ、止まっていても休憩の始めに一掃する (t=%.2f)" % sim.break_clear_t)

	# クリア: 最後の弾幕を撃ち終え、弾が抜けたらすぐクリア(end_time を待たない)。弾は消えている
	a = _make(true, 100.0, [], [fast])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	now = 0.0
	while not sim.finished and now < 30.0:
		now = _run(sim, now, 1)
	_check(sim.finished and not sim.failed and now < 5.0, "撃ち終えて弾が抜けたら、end_time を待たずにクリア (t=%.2f)" % now)
	_check(f.count == 0 and sim.score_progress == 1.0 and sim.progress == 1.0, "クリア時は弾が消え、スコア進捗・進行率が 1")
	# 自機の近くに止まった弾が残り続けても、撃ち終えて CLEAR_TIMEOUT 秒でクリア(消える)
	var near_ev := _ev(1.0, 5)
	near_ev.pos = Vector2(GameSim.ARENA.x * 0.5 + 105.0, GameSim.ARENA.y * 0.85)
	a = _make(true, 100.0, [], [near_ev])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	now = 0.0
	while not sim.finished and now < 30.0:
		now = _run(sim, now, 1)
	_check(sim.finished and absf(now - (1.0 + GameSim.CLEAR_TIMEOUT)) < 0.1 and f.count == 0, "弾が残り続けても、撃ち終えて %.0f 秒でクリア (t=%.2f)" % [GameSim.CLEAR_TIMEOUT, now])
	# 自機から遠い弾しかなければ(止まっていても)、撃ち終えてすぐクリア
	a = _make(true, 100.0, [], [_ev(1.0, 5)])
	sim = a[0]
	f = a[1]
	sim.debug_invincible = true
	now = 0.0
	while not sim.finished and now < 30.0:
		now = _run(sim, now, 1)
	_check(sim.finished and now < 1.5 and f.count == 0, "自機から遠い弾しかなければ、撃ち終えてすぐクリア (t=%.2f)" % now)

	# --- 練習 MOD / 暗闇 MOD / ランク ---
	var p_prac := Mods.params(["practice"])
	_check(p_prac.practice and is_equal_approx(p_prac.score_mul, 0.5) and not p_prac.dark, "練習 MOD: practice=true、ベーススコア ×0.5")
	var p_dark := Mods.params(["dark"])
	_check(p_dark.dark and is_equal_approx(p_dark.score_mul, 1.06) and not p_dark.practice, "暗闇 MOD: dark=true、ベーススコア ×1.06")
	var p_both := Mods.params(["practice", "dark", "rush"])
	_check(is_equal_approx(p_both.score_mul, 0.5 * 1.06 * 1.12) and p_both.practice and p_both.dark, "練習 + 暗闇 + 加速: 倍率は乗算 (%.4f)" % p_both.score_mul)
	_check(not Mods.params([]).practice and not Mods.params([]).dark, "MOD なしなら practice / dark は false")
	# 練習 MOD: setup() の mods だけでゲージ 0 でも続行する。ベーススコアは半分
	a = _make(false, 10.0, [], [], p_prac)
	sim = a[0]
	f = a[1]
	_put_bullet_on_player(sim, f)
	now = _run(sim, 0.0, int(1.0 / DT))
	_check(sim.practice and not sim.failed and sim.gauge == 0.0, "練習 MOD: ゲージが 0 になってもゲームオーバーにならない")
	_check(is_equal_approx(sim.score_base, 500000.0), "練習 MOD: ベーススコア 500,000")
	# 弾幕に効かない MOD(練習・暗闇)は、Lv を変えない
	var fast_a := _ev(1.0, 10)
	fast_a.shots[0].speed = 150.0
	var fast_b := _ev(2.0, 10)
	fast_b.shots[0].speed = 150.0
	var gen_n: Dictionary = {"events": [fast_a, fast_b], "gizmos": [], "warn_lead": 0.6, "speed": 150.0, "size": 6.0, "stars": 3.0,
		"rating": PatternGen.measure([fast_a, fast_b]), "level": 2.5, "breaks": []}
	var g_n: Dictionary = Mods.apply(gen_n, Mods.params(["practice", "dark"]))
	_check(is_equal_approx(g_n.level, 2.5) and is_equal_approx(g_n.base_level, 2.5), "練習・暗闇だけなら Lv は変わらない")
	# 暗闇 MOD: 発射地点の印を、発射から FIRE_MARK_TIME 秒だけ残す
	a = _make(true, 20.0, [], [_ev(1.0, 3), _ev(15.0, 1)], p_dark)
	sim = a[0]
	f = a[1]
	now = _run(sim, 0.0, int(1.1 / DT))
	_check(sim.track_fires and sim.recent_fires.size() == 1, "暗闇 MOD: 発射地点の印が 1 つ残っている")
	now = _run(sim, now, int((GameSim.FIRE_MARK_TIME + 0.2) / DT))
	_check(sim.recent_fires.is_empty(), "発射地点の印は %.1f 秒で消える" % GameSim.FIRE_MARK_TIME)
	a = _make(true, 10.0, [], [_ev(1.0, 3)])
	now = _run(a[0], 0.0, int(1.1 / DT))
	_check(not a[0].track_fires and a[0].recent_fires.is_empty(), "暗闇でなければ印は記録しない")
	# ランク: ノーミス = SS、それ以外は達成率(スコア ÷ ベーススコア)で S〜F、ゲームオーバーは "-"
	_check(GameSim.rank_of(false, 0, 1000000.0, 1000000.0) == "SS", "被弾 0 回 = SS")
	_check(GameSim.rank_of(false, 0, 500000.0, 500000.0) == "SS", "練習 MOD でもノーミスは SS")
	_check(GameSim.rank_of(false, 1, 990000.0, 1000000.0) == "S", "達成率 0.99 = S")
	_check(GameSim.rank_of(false, 3, 900000.0, 1000000.0) == "A", "達成率 0.90 = A")
	_check(GameSim.rank_of(false, 3, 750000.0, 1000000.0) == "B", "達成率 0.75 = B")
	_check(GameSim.rank_of(false, 3, 600000.0, 1000000.0) == "C", "達成率 0.60 = C")
	_check(GameSim.rank_of(false, 3, 450000.0, 1000000.0) == "D", "達成率 0.45 = D")
	_check(GameSim.rank_of(false, 3, 300000.0, 1000000.0) == "F", "達成率 0.30 = F")
	_check(GameSim.rank_of(false, 3, 225000.0, 500000.0) == "D" and GameSim.rank_of(false, 3, 300000.0, 500000.0) == "C", "ランクは MOD の倍率を打ち消した達成率で決まる(練習 ×0.5 でも同じ)")
	_check(GameSim.rank_of(true, 5, 0.0, 1000000.0) == "-", "ゲームオーバーはランクなし")
	var bf2 := BulletField.new()
	_check(bf2.vis_r1 == 0.0, "見える範囲の制限は既定でオフ")

	# --- 被ダメージ係数の時定数は、弾が飛んでいる時間に応じて伸びる(長い曲が不利にならない) ---
	var tau_of := func(span: float, brks: Array) -> float:
		var aa := _make(true, 1000.0, brks, [_ev(1.0, 1), _ev(1.0 + span, 1)])
		return aa[0].damage_tau
	_check(is_equal_approx(tau_of.call(30.0, []), GameSim.DAMAGE_TAU), "短い譜面(30 秒)の τ は従来どおり")
	_check(is_equal_approx(tau_of.call(120.0, []), GameSim.DAMAGE_TAU), "基準(120 秒)の τ は従来どおり")
	_check(is_equal_approx(tau_of.call(300.0, []), GameSim.DAMAGE_TAU * 2.5), "300 秒の τ は 2.5 倍")
	_check(is_equal_approx(tau_of.call(300.0, [[101.0, 201.0]]), GameSim.DAMAGE_TAU * 200.0 / 120.0), "休憩地帯(100 秒)は弾が飛んでいない時間として除く")
	var dmg_long := _make(true, 1000.0, [], [_ev(1.0, 1), _ev(301.0, 1)])
	var dmg_short := _make(true, 1000.0, [], [_ev(1.0, 1), _ev(31.0, 1)])
	for pair in [dmg_long, dmg_short]:
		pair[0].debug_invincible = false
		_put_bullet_on_player(pair[0], pair[1])
		_run(pair[0], 0.0, int(0.15 / DT))   # どちらも同じ時間だけ被弾する
	_check(is_equal_approx(dmg_long[0].damage_total, dmg_short[0].damage_total) and dmg_long[0].damage_total > 0.3, "同じだけ被弾している (累計ダメージ %.3f)" % dmg_long[0].damage_total)
	_check(dmg_long[0].damage_factor > dmg_short[0].damage_factor, "同じ被弾なら、長い曲のほうが係数が高い (%.3f > %.3f)" % [dmg_long[0].damage_factor, dmg_short[0].damage_factor])
	_check(absf(dmg_short[0].damage_factor - exp(-dmg_short[0].damage_total / GameSim.DAMAGE_TAU)) < 1e-9, "短い譜面の係数は従来の式 exp(−ダメージ ÷ 2) のまま")

	# --- キアイ / 拍の位相(背景・弾の光に使う) ---
	var kbm := Beatmap.new()
	kbm.timing_points = [
		{"time": 1000.0, "beat_length": 500.0, "uninherited": true, "kiai": false, "meter": 4},
		{"time": 5000.0, "beat_length": -100.0, "uninherited": false, "kiai": true, "meter": 4},
		{"time": 9000.0, "beat_length": -100.0, "uninherited": false, "kiai": false, "meter": 4},
		{"time": 10000.0, "beat_length": 400.0, "uninherited": true, "kiai": false, "meter": 4},
	]
	_check(not kbm.kiai_at(3000.0) and kbm.kiai_at(5000.0) and kbm.kiai_at(8999.0) and not kbm.kiai_at(9000.0), "キアイの区間 [5000, 9000) ms")
	_check(absf(kbm.beat_phase_at(1000.0)) < 1e-9 and absf(kbm.beat_phase_at(1250.0) - 0.5) < 1e-9, "赤線 1000ms・1 拍 500ms: 1000ms で位相 0、1250ms で 0.5")
	_check(absf(kbm.beat_phase_at(6100.0) - 0.2) < 1e-9, "緑線(継承)をまたいでも、直前の赤線が基準 (6100ms → 0.2)")
	_check(absf(kbm.beat_phase_at(10100.0) - 0.25) < 1e-9, "テンポが変わった赤線(10000ms・1 拍 400ms)からは、新しい拍で数える (10100ms → 0.25)")
	_check(kbm.beat_phase_at(500.0) >= 0.0 and kbm.beat_phase_at(500.0) < 1.0, "最初の赤線より前でも、位相は 0..1 に収まる")

	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
