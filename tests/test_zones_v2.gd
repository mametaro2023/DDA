extends SceneTree
## 特殊エリア(MOD「弾幕 v2」。scripts/game/zone_gen_v2.gd・zone_area.gd)の単体テスト。
##   ・生成: 決定的・フレーズごとに 1 つ(または 1 組)・小節の頭・予告・休憩と重ならない・系統と種類が★に応じて変わる・中央に居続けられない
##   ・効果(GameSim): 精密・癒し・稼ぎ・試練のグレイズの上乗せ・時の淀み(弾の速さ)・協力の報告
## godot --headless --path . --script tests/test_zones_v2.gd [-- stats]   (stats を付けると、譜面ごとの内訳を出す)

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const ZoneArea = preload("res://scripts/game/zone_area.gd")
const Mods = preload("res://scripts/mods.gd")

const DIR := "C:/Desktop/my_apps/DDA/"
const DT := 0.01
const MID := Vector2(480, 360)

var _fail := 0
var _stats := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	_stats = OS.get_cmdline_user_args().has("stats")
	_test_shapes()
	_test_generation()
	_test_effects()
	_test_coop()
	print("test_zones_v2: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


func _find(file: String, version: String):
	var l := OszLoader.new()
	if not l.open(DIR + file):
		return null
	for bm in l.difficulties:
		if bm.version == version:
			return bm
	return null


# --- 形 ---

func _test_shapes() -> void:
	var field := Rect2(0, 0, 960, 720)
	var half := ZoneArea.rect(0.0, 0.0, 0.5, 1.0)
	_check(ZoneArea.contains(half, Vector2(100, 600), field, 0.0) and not ZoneArea.contains(half, Vector2(600, 100), field, 0.0), "半面: 左半分の中だけ")
	var disc := ZoneArea.disc(0.5, 0.5, 0.3)
	_check(ZoneArea.contains(disc, MID, field, 0.0) and not ZoneArea.contains(disc, Vector2(40, 40), field, 0.0) and absf(ZoneArea.world_radius(disc, field) - 216.0) < 1e-6, "円: 半径は短い辺の 0.3 倍(216px)")
	var sweep := ZoneArea.rect(0.0, 0.0, 0.3, 1.0, Vector2(0.7, 0.0))
	_check(ZoneArea.contains(sweep, Vector2(100, 300), field, 0.0) and not ZoneArea.contains(sweep, Vector2(100, 300), field, 1.0) and ZoneArea.contains(sweep, Vector2(900, 300), field, 1.0)
		and ZoneArea.contains(sweep, Vector2(480, 300), field, 0.5), "流れる帯: 進み具合 0 で左端・0.5 で中央・1 で右端")
	# 小さい動ける範囲(小型化)に合わせて拡縮する
	var small := Rect2(240, 180, 480, 360)
	_check(ZoneArea.contains(half, Vector2(300, 300), small, 0.0) and not ZoneArea.contains(half, Vector2(500, 300), small, 0.0) and ZoneArea.bounds(half, small, 0.0).size.is_equal_approx(Vector2(240, 360)),
		"小型化: 動ける範囲に対する割合で拡縮する")
	_check(absf(ZoneArea.area_fraction(half) - 0.5) < 1e-6 and absf(ZoneArea.area_fraction(disc) - PI * 0.09 * 0.75) < 1e-6, "面積の割合")
	_check(ZoneArea.family_of("slow") == "trial" and ZoneArea.family_of("heal") == "boon" and ZoneArea.family_of("warp") == "warp" and ZoneArea.family_of("haste") == "trial" and ZoneArea.family_of("flow") == "trial" and ZoneArea.family_of("x") == "", "系統(試練・恩恵・変質。時の急流・流れは試練)")


# --- 生成 ---

func _stat_line(label: String, g: Dictionary) -> void:
	var fam := {}
	var types := {}
	var shapes := {}
	for z in g.zones:
		fam[z.fam] = int(fam.get(z.fam, 0)) + 1
		for a in z.areas:
			types[a.type] = int(types.get(a.type, 0)) + 1
			shapes[str(a.shape.k) + ("~" if (a.shape.get("mv", Vector2.ZERO) as Vector2) != Vector2.ZERO else "")] = int(shapes.get(str(a.shape.k) + ("~" if (a.shape.get("mv", Vector2.ZERO) as Vector2) != Vector2.ZERO else ""), 0)) + 1
	print("  %s ★%.2f  %d 回  系統 %s  種類 %s  形 %s" % [label, g.stars, g.zones.size(), str(fam), str(types), str(shapes)])


func _test_generation() -> void:
	var easy = _find("320118 Reol - No title.osz", "Irre's Beginner")
	var hard = _find("813569 Laur - Sound Chimera.osz", "Chimera")
	var insane = _find("241526 Soleily - Renatus.osz", "Insane")
	var ge := PatternGenV2.generate(easy)
	var gh := PatternGenV2.generate(hard)
	var gi := PatternGenV2.generate(insane)
	var g1 := PatternGen.generate(hard)
	if _stats:
		_stat_line("Beginner", ge)
		_stat_line("Renatus Insane", gi)
		_stat_line("Chimera", gh)
	_check(str(ge.zones) == str(PatternGenV2.generate(easy).zones), "決定的(同じ譜面なら同じ予定)")
	_check(g1.zones.size() > 0 and g1.zones[0].has("cells") and not g1.zones[0].has("areas"), "MOD なし(v1)は、今までどおり 3×3 のマスの危険エリア")
	_check(ge.zones.size() >= 2 and gh.zones.size() >= 10 and gi.zones.size() >= 6, "エリアの予定がある(入門 %d 回・Renatus Insane %d 回・Chimera %d 回)" % [ge.zones.size(), gi.zones.size(), gh.zones.size()])
	# 形式: areas 1〜2 個・系統・種類・時刻
	var ok := true
	var ordered := true
	var t_first: float = hard.first_time() / 1000.0
	var before_first := false
	for z in gh.zones:
		if not z.has("areas") or z.areas.size() < 1 or z.areas.size() > 2 or not ["trial", "boon", "pair"].has(z.fam):
			ok = false
		if (z.fam == "pair") != (z.areas.size() == 2):
			ok = false
		for a in z.areas:
			if ZoneArea.family_of(str(a.type)) == "" or GameSim.zone_name(str(a.type)) == "":
				ok = false
		if float(z.lead) <= 0.0 or float(z.end) <= float(z.t):
			ordered = false
		if float(z.t) - float(z.lead) < t_first - 0.001:
			before_first = true
	for i in range(1, gh.zones.size()):
		if float(gh.zones[i].t) < float(gh.zones[i - 1].end) - 0.001:
			ordered = false
	_check(ok, "各エリアは 1 つまたは 1 組(対は 2 つ)で、系統・種類が正しい")
	_check(ordered, "エリアは時刻順で重ならず、予告・終わりが正しい")
	_check(not before_first, "最初の弾の発射前には、予告も出ない")
	# 小節の頭から始まる(最初のフレーズだけは、最初のノーツから始まるので除く)
	var starts := PatternGen.measure_starts(hard)
	var aligned := 0
	for z in gh.zones:
		for m in starts:
			if absf(float(m[0]) - float(z.t)) < 0.003:
				aligned += 1
				break
	_check(aligned == gh.zones.size(), "エリアの発動は、小節の頭に合っている(%d / %d)" % [aligned, gh.zones.size()])
	# 予告は、直前の 1〜3 小節ぶん(★が高いと短い)。フレーズの半分を超えない
	var lead_ok := true
	for z in gh.zones:
		if float(z.lead) < 0.7 or float(z.lead) > 8.0:
			lead_ok = false
	_check(lead_ok, "予告の長さが、小節の長さの範囲に入っている")
	# 休憩地帯と重ならない(予告を含めて)。休憩のある譜面で
	var with_break = null
	var sol := OszLoader.new()
	sol.open(DIR + "241526 Soleily - Renatus.osz")
	for bm in sol.difficulties:
		if bm.version == "Hard" and not bm.breaks.is_empty():
			with_break = bm
	if with_break != null:
		var gb := PatternGenV2.generate(with_break)
		var clash := 0
		for z in gb.zones:
			for b in gb.breaks:
				if float(z.t) - float(z.lead) < float(b[1]) and float(z.end) > float(b[0]):
					clash += 1
		_check(clash == 0 and gb.zones.size() >= 3, "休憩地帯と重ならない(%d 回中 重なり %d)" % [gb.zones.size(), clash])
	# ★に応じて: 低いと恩恵が多く、高いと対・試練が多い。毒・精密は、★が低いと出ない
	var boon_e := _share(ge.zones, "boon")
	var boon_h := _share(gh.zones, "boon")
	_check(boon_e > boon_h, "★が低いほど恩恵が多い(入門 %.0f%% → Chimera %.0f%%)" % [boon_e * 100.0, boon_h * 100.0])
	var te := _types(ge.zones)
	var th := _types(gh.zones)
	_check(not te.has("poison") and not te.has("precise"), "入門には、毒・精密が出ない(%s)" % str(te.keys()))
	var ti := _types(gi.zones)
	_check(th.has("slow") and th.has("fragile") and th.has("warp") and th.has("bonus") and th.has("precise") and ti.has("poison"), "高難度には、試練・恩恵・変質が出る(Chimera %s・Renatus Insane の毒 %s)" % [str(th.keys()), str(ti.has("poison"))])
	_check(th.size() >= 5, "高難度は、種類が 5 つ以上出る(%d 種類)" % th.size())
	var flow_ok := true
	var flow_n := 0
	for g in [gh, gi]:
		for z in g.zones:
			for a in z.areas:
				if a.type == "flow":
					flow_n += 1
					if not a.has("dir") or absf((a.dir as Vector2).length() - 1.0) > 1e-6:
						flow_ok = false
				elif a.has("dir"):
					flow_ok = false
	_check(th.has("flow") and th.has("haste") and flow_ok and flow_n >= 3, "流れ・時の急流が出る。流れだけが、押す向き(単位ベクトル)を持つ(流れ %d 個)" % flow_n)
	_check(not te.has("haste") and not te.has("flow"), "入門(★が低い)には、時の急流・流れは出ない")
	# 譜面の性格で形・種類が変わる(Chimera の中に複数の形)
	var shape_kinds := {}
	for z in gh.zones:
		for a in z.areas:
			shape_kinds[str(a.shape.k) + str((a.shape.get("mv", Vector2.ZERO) as Vector2) != Vector2.ZERO)] = true
	_check(shape_kinds.size() >= 3, "1 譜面の中に、複数の形が出る(%d 通り)" % shape_kinds.size())
	# 中央に居続けられない: 中央の点が、試練(対の試練側を含む)の中にいる時間の割合
	var c_h := _trial_time_at(gh.zones, MID)
	var c_i := _trial_time_at(gi.zones, MID)
	if _stats:
		print("  中央の点が試練の中にいる時間の割合: Chimera %.0f%% / Renatus Insane %.0f%%" % [c_h * 100.0, c_i * 100.0])
	_check(c_h >= 0.15 and c_i >= 0.12, "中央に居続けると、試練を受ける時間が長い(Chimera %.0f%%・Renatus Insane %.0f%%)" % [c_h * 100.0, c_i * 100.0])
	# 同じ場所に居続けても安全でいられる時間は長くない: 盤面の格子点のうち、最悪の点の試練の割合
	var worst := 0.0
	var best := 1.0
	for gx in range(1, 6):
		for gy in range(1, 6):
			var p := Vector2(960.0 * gx / 6.0, 720.0 * gy / 6.0)
			var f := _trial_time_at(gh.zones, p)
			worst = maxf(worst, f)
			best = minf(best, f)
	_check(best >= 0.04, "Chimera: どの場所に居続けても、試練を受ける時間が 4%% 以上ある(最小 %.0f%%・最大 %.0f%%)" % [best * 100.0, worst * 100.0])
	# 安全な場所はいつもある: 試練のエリアは、動ける範囲の半分以下
	var safe_ok := true
	for z in gh.zones:
		var cov := 0.0
		for a in z.areas:
			if ZoneArea.family_of(str(a.type)) == "trial":
				cov += ZoneArea.area_fraction(a.shape)
		if cov > 0.5001:
			safe_ok = false
	_check(safe_ok, "試練に入るエリアの面積は、動ける範囲の半分以下(安全な場所が残る)")
	# MOD(加速)で時刻が詰まる。形式も保たれる
	var v2p := Mods.params(["v2", "rush"])
	var rush := Mods.apply(gh, v2p)
	_check(rush.zones.size() == gh.zones.size() and absf(float(rush.zones[3].t) - float(gh.zones[3].t) / v2p.rate) < 1e-6 and rush.zones[3].has("areas"), "MOD(加速)で、エリアの時刻も 1/%.2f になる" % v2p.rate)
	# 難易度(Lv)・弾幕は、エリアの有無で変わらない
	var gh_nz := gh.duplicate()
	gh_nz["zones"] = []
	_check(absf(float(gh.level) - float(gh_nz.level)) < 1e-9, "難易度(Lv)にエリアは入らない")


func _share(zones: Array, fam: String) -> float:
	var n := 0
	for z in zones:
		if z.fam == fam:
			n += 1
	return float(n) / maxf(float(zones.size()), 1.0)


func _types(zones: Array) -> Dictionary:
	var out := {}
	for z in zones:
		for a in z.areas:
			out[a.type] = true
	return out


## 点 p が、試練の中にいる時間の割合(エリアが出ている時間のうち。動く帯も、進み具合ごとに調べる)。
func _trial_time_at(zones: Array, p: Vector2) -> float:
	var field := Rect2(0, 0, 960, 720)
	var inside := 0.0
	var total := 0.0
	for z in zones:
		var span: float = float(z.end) - float(z.t)
		total += span
		for step in range(10):
			var now: float = float(z.t) + span * (float(step) + 0.5) / 10.0
			var u := ZoneArea.progress(z, now)
			for a in z.areas:
				if ZoneArea.family_of(str(a.type)) == "trial" and ZoneArea.contains(a.shape, p, field, u):
					inside += span / 10.0
					break
	return inside / maxf(total, 1.0)


# --- 効果 ---

## 動かない弾を 1 つ置くだけの sim(エリアの確認用)。zones を渡す。
func _make(zones: Array, n := 1, host := true, breaks := []) -> Array:
	var shot := {"n": 1, "speed": 0.0, "a0": 0.0, "spread": TAU, "fan": false, "aim": false, "size": 6.0, "color": 0, "turn": 0.0}
	var events := [{"t": 0.1, "pos": Vector2(30, 30), "warn": false, "shots": [shot], "sfx": ""},
		{"t": 90.0, "pos": Vector2(30, 30), "warn": false, "shots": [shot], "sfx": ""}]
	var f := BulletField.new()
	var s := GameSim.new()
	s.setup(f, {"events": events, "gizmos": [], "warn_lead": 0.6, "breaks": breaks, "zones": zones}, 100.0, false, {})
	if n > 1:
		s.setup_coop(n, host)
	return [s, f]


func _zone(areas: Array, t := 0.0, end := 50.0) -> Dictionary:
	return {"t": t, "end": end, "lead": 1.0, "cells": [], "areas": areas, "fam": "trial", "motif": "ring"}


func _all(type: String) -> Dictionary:
	return {"shape": ZoneArea.rect(0.0, 0.0, 1.0, 1.0), "type": type}


func _run(s, from: float, secs: float, move_fn = null) -> float:
	var now := from
	var end := from + secs
	while now < end:
		var mv := Vector2.ZERO
		if move_fn != null:
			mv = move_fn.call(now)
		s.step(now, DT, mv, false)
		now += DT
	return now


func _test_effects() -> void:
	var right := func(_n: float) -> Vector2: return Vector2(1, 0)
	# 精密: 当たり判定 0.6 倍(通常は当たる距離の弾に当たらない)・移動 0.75 倍
	var a := _make([_zone([_all("precise")])])
	var s = a[0]
	s.player_pos = MID
	s.field.add(MID + Vector2(7.5, 0), Vector2.ZERO, 6.0, 0, 0.0)
	_run(s, 0.0, 0.05)
	var b := _make([])
	var s0 = b[0]
	s0.player_pos = MID
	s0.field.add(MID + Vector2(7.5, 0), Vector2.ZERO, 6.0, 0, 0.0)
	_run(s0, 0.0, 0.05)
	_check(s0.gauge < 1.0 and s.gauge == 1.0 and absf(s.hit_mult - GameSim.ZONE_PRECISE_HIT) < 1e-9, "精密: 通常は当たる距離(7.5px)の弾に当たらない(当たり判定 %.1f 倍)" % s.hit_mult)
	var s1 = _make([_zone([_all("precise")])])[0]
	s1.player_pos = MID
	_run(s1, 0.0, 0.5, right)
	var s2 = _make([])[0]
	s2.player_pos = MID
	_run(s2, 0.0, 0.5, right)
	_check(absf((s1.player_pos.x - MID.x) / (s2.player_pos.x - MID.x) - GameSim.ZONE_PRECISE_SPEED) < 0.03, "精密: 移動が %.2f 倍" % GameSim.ZONE_PRECISE_SPEED)
	_check(absf(s.hit_mult_at(MID, 0.05) - GameSim.ZONE_PRECISE_HIT) < 1e-9, "他の人の当たり判定の倍率も、精密のエリアの中は %.1f 倍" % GameSim.ZONE_PRECISE_HIT)
	# 癒し: ゲージが毎秒 5% 回復(累計ダメージからは引かない)。休憩の間は回復しない
	var s3 = _make([_zone([_all("heal")])])[0]
	s3.gauge = 0.5
	s3.player_pos = MID
	_run(s3, 0.0, 2.0)
	var s3b = _make([])[0]
	s3b.gauge = 0.5
	s3b.player_pos = MID
	_run(s3b, 0.0, 2.0)
	_check(absf((s3.gauge - s3b.gauge) - 0.10) < 0.01 and s3.damage_total == 0.0 and s3.zone_debuff == "heal", "癒し: 2 秒で約 10%% 回復する(エリアなしより +%.3f)" % (s3.gauge - s3b.gauge))
	var s3c = _make([_zone([_all("heal")])], 1, true, [[0.0, 50.0]])[0]
	s3c.gauge = 0.5
	s3c.player_pos = MID
	_run(s3c, 0.0, 2.0)
	_check(s3c.gauge == 0.5, "休憩の間は、癒しも効かない")
	# グレイズの上乗せ: 稼ぎ ×2(+1.0)・試練 ×1.5(+0.5)・エリアなし 0
	var gz := {}
	for t in ["bonus", "slow", "heal", ""]:
		var zs := [_zone([_all(t)])] if t != "" else []
		var sg = _make(zs)[0]
		sg.player_pos = MID
		sg.field.add(MID + Vector2(24, 0), Vector2.ZERO, 6.0, 0, 0.0)   # 当たらず、かすり(グレイズ)の距離
		_run(sg, 0.0, 0.05)
		gz[t] = [sg.graze, sg.graze_bonus, sg.score_graze]
	_check(int(gz["bonus"][0]) == 1 and absf(float(gz["bonus"][1]) - GameSim.ZONE_GRAZE_BONUS) < 1e-9, "稼ぎ: グレイズ 1 回に、上乗せ %.1f(グレイズ数は 1 のまま)" % float(gz["bonus"][1]))
	_check(absf(float(gz["slow"][1]) - GameSim.ZONE_GRAZE_TRIAL) < 1e-9, "試練のエリア: グレイズの上乗せ %.1f(リスクの見返り)" % float(gz["slow"][1]))
	_check(float(gz["heal"][1]) == 0.0 and float(gz[""][1]) == 0.0 and float(gz["bonus"][2]) > float(gz["slow"][2]) and float(gz["slow"][2]) > float(gz[""][2]), "恩恵(稼ぎ以外)・エリアなしは上乗せなし。ボーナス点は 稼ぎ > 試練 > なし")
	# 稼ぎのグレイズは、失っている被ダメージ係数を取り戻す(失うほど、戻る量が大きい。damage_total・DAMAGE 表示は変えない)
	var rf := {}
	for t in ["bonus", "slow", ""]:
		for dmg in [0.0, 0.3, 0.9]:
			var zr := [_zone([_all(t)])] if t != "" else []
			var sr = _make(zr)[0]
			sr.damage_total = dmg
			sr.player_pos = MID
			sr.field.add(MID + Vector2(24, 0), Vector2.ZERO, 6.0, 0, 0.0)
			_run(sr, 0.0, 0.05)
			rf["%s%.1f" % [t, dmg]] = sr
	var lost03: float = 1.0 - exp(-0.3 / rf["bonus0.3"].damage_tau)
	var lost09: float = 1.0 - exp(-0.9 / rf["bonus0.9"].damage_tau)
	var gain03: float = rf["bonus0.3"].damage_factor - (1.0 - lost03)
	var gain09: float = rf["bonus0.9"].damage_factor - (1.0 - lost09)
	_check(absf(gain03 - lost03 * GameSim.ZONE_GRAZE_REFUND) < 1e-9, "稼ぎ: グレイズ 1 回で、失った係数の %.1f%% を取り戻す(+%.5f)" % [GameSim.ZONE_GRAZE_REFUND * 100.0, gain03])
	_check(gain09 > gain03 * 2.0 and rf["bonus0.9"].damage_total == 0.9, "失った係数が大きいほど、戻る量も大きい(+%.5f > +%.5f)。damage_total は変わらない" % [gain09, gain03])
	_check(rf["bonus0.0"].damage_factor == 1.0 and rf["bonus0.0"].damage_refund == 0.0, "失っていなければ、何も戻らない(係数は 1 を超えない)")
	_check(rf["slow0.9"].damage_refund == 0.0 and rf["0.9"].damage_refund == 0.0, "稼ぎ以外(試練・エリアなし)では、係数は戻らない")
	# 試練の効果は、v1 と同じ(鈍足・脆弱・毒)
	var s4 =_make([_zone([{"shape": ZoneArea.rect(0.0, 0.0, 0.5, 1.0), "type": "slow"}])])[0]
	s4.player_pos = Vector2(100, 360)
	var x0: float = s4.player_pos.x
	_run(s4, 0.0, 0.5, right)
	var s5 = _make([])[0]
	s5.player_pos = Vector2(100, 360)
	_run(s5, 0.0, 0.5, right)
	_check(absf((s4.player_pos.x - x0) / (s5.player_pos.x - x0) - GameSim.ZONE_SLOW) < 0.05, "鈍足(形のエリア): 移動が %.2f 倍(左半面の中)" % GameSim.ZONE_SLOW)
	var s6 = _make([_zone([{"shape": ZoneArea.rect(0.0, 0.0, 0.5, 1.0), "type": "slow"}])])[0]
	s6.player_pos = Vector2(700, 360)
	_run(s6, 0.0, 0.1)
	_check(s6.zone_debuff == "", "形の外では、何も起きない")
	var s7 = _make([_zone([_all("poison")])])[0]
	s7.player_pos = MID
	_run(s7, 0.0, 2.0)
	_check(absf((1.0 - s7.gauge) - 0.2) < 0.04, "毒(形のエリア): 2 秒でゲージが約 20%% 減る(%.3f)" % (1.0 - s7.gauge))
	# 対: 左半面が試練・右半面が恩恵。位置で効果が変わる
	var pair := _zone([{"shape": ZoneArea.rect(0.0, 0.0, 0.5, 1.0), "type": "poison"}, {"shape": ZoneArea.rect(0.5, 0.0, 1.0, 1.0), "type": "heal"}])
	var s8 = _make([pair])[0]
	s8.player_pos = Vector2(200, 360)
	_run(s8, 0.0, 0.05)
	var l_type: String = s8.zone_debuff
	s8.player_pos = Vector2(800, 360)
	_run(s8, 0.05, 0.05)
	_check(l_type == "poison" and s8.zone_debuff == "heal", "対: 左は毒・右は癒し(位置で変わる)")
	# 時の淀み: エリアの中の弾が、なめらかに 0.55 倍の速さへ落ちる(急に遅くならない)。外は変わらない。自機の位置には依存しない
	var warp := _zone([{"shape": ZoneArea.rect(0.5, 0.0, 1.0, 1.0), "type": "warp"}])
	var sw = _make([warp])[0]
	sw.player_pos = Vector2(100, 700)
	sw.field.add(Vector2(600, 300), Vector2(100, 0), 5.0, 0, 0.0)    # 淀みの中
	sw.field.add(Vector2(200, 300), Vector2(100, 0), 5.0, 0, 0.0)    # 淀みの外(左半分)
	_run(sw, 0.0, 0.05)
	var ts_early: float = sw.field.tscale[0]
	_check(ts_early > 0.9 and ts_early < 1.0 and sw.field.tscale[1] == 1.0, "時の淀み: 入った直後に、急には遅くならない(0.05 秒で %.2f 倍)・外は変わらない" % ts_early)
	_run(sw, 0.05, 1.0)
	var x1: float = sw.field.pos[0].x
	var o1: float = sw.field.pos[1].x
	_run(sw, 1.05, 0.4)
	var inside_dx: float = sw.field.pos[0].x - x1
	var outside_dx: float = sw.field.pos[1].x - o1
	_check(absf(inside_dx - 100.0 * 0.4 * GameSim.ZONE_WARP) < 1.0 and absf(outside_dx - 40.0) < 1.0, "時の淀み: 落ち着いたあと、中の弾は %.2f 倍の速さ(0.4 秒で %.1f px)・外は変わらない(%.1f px)" % [GameSim.ZONE_WARP, inside_dx, outside_dx])
	_check(sw.zone_debuff == "" and sw.zone_area_type == "", "時の淀み: 自機がエリアの外なら、何もない")
	sw.player_pos = Vector2(700, 300)
	_run(sw, 1.45, 0.05)
	_check(sw.zone_debuff == "" and sw.zone_area_type == "warp" and sw.zone_speed_mul() == 1.0, "時の淀みは、自機の中にいても、自機には何も効かない(移動の倍率 1)")
	# エリアが消えたあと、弾の速さがゆっくり戻る(急に速くならない)
	var wr := _zone([{"shape": ZoneArea.rect(0.5, 0.0, 1.0, 1.0), "type": "warp"}], 0.0, 3.0)
	var swr = _make([wr])[0]
	swr.player_pos = Vector2(100, 700)
	swr.field.add(Vector2(600, 100), Vector2(0, 40), 5.0, 0, 0.0)
	_run(swr, 0.0, 3.0)
	_check(absf(swr.field.tscale[0] - GameSim.ZONE_WARP) < 0.01, "時の淀み: 終わる直前は、%.2f 倍で落ち着いている" % swr.field.tscale[0])
	_run(swr, 3.0, 0.1)
	var ts_after: float = swr.field.tscale[0]
	_check(ts_after > GameSim.ZONE_WARP and ts_after < 0.7, "終わった直後(0.1 秒後)は、まだ遅いまま(%.2f 倍)" % ts_after)
	_run(swr, 3.1, 0.5)
	var ts_mid: float = swr.field.tscale[0]
	_check(ts_mid > 0.7 and ts_mid < 0.95, "終わって 0.6 秒後も、途中(%.2f 倍)" % ts_mid)
	_run(swr, 3.6, 1.5)
	_check(swr.field.tscale[0] == 1.0 and not swr.field._ts_active, "終わって約 2 秒後には、元の速さへ戻る")
	# 時の急流: エリアの中の弾が 1.5 倍の速さ(試練。なめらかに速くなる)。自機には効かないが、中でのグレイズには上乗せがつく
	var hz := _zone([{"shape": ZoneArea.rect(0.5, 0.0, 1.0, 1.0), "type": "haste"}], 0.0, 5.0)
	var sh = _make([hz])[0]
	sh.player_pos = Vector2(700, 650)
	sh.field.add(Vector2(600, 100), Vector2(0, 40), 5.0, 0, 0.0)
	_run(sh, 0.0, 0.05)
	_check(sh.field.tscale[0] > 1.0 and sh.field.tscale[0] < 1.1, "時の急流: 入った直後は、急には速くならない(%.2f 倍)" % sh.field.tscale[0])
	_run(sh, 0.05, 1.0)
	_check(absf(sh.field.tscale[0] - GameSim.ZONE_HASTE) < 0.01, "時の急流: 落ち着くと %.2f 倍" % GameSim.ZONE_HASTE)
	_check(sh.zone_debuff == "" and sh.zone_area_type == "haste" and absf(sh.zone_graze_mul() - GameSim.ZONE_GRAZE_TRIAL) < 1e-9, "時の急流: 自機には効かず、中でのグレイズには、試練の上乗せがつく")
	_run(sh, 1.05, 4.0)   # 5 秒で終わる
	_run(sh, 5.05, 0.1)
	_check(sh.field.tscale[0] > 1.0 and sh.field.tscale[0] < GameSim.ZONE_HASTE, "時の急流が終わった直後も、急には遅くならない(%.2f 倍)" % sh.field.tscale[0])
	# 流れ: 入力がなくても、向きへ押される(110px/s)。逆向きに動けば、押し返せる。マウス操作でも押される
	var fz := _zone([{"shape": ZoneArea.rect(0.0, 0.0, 1.0, 1.0), "type": "flow", "dir": Vector2(1, 0)}])
	var sf = _make([fz])[0]
	sf.player_pos = Vector2(200, 360)
	_run(sf, 0.0, 1.0)
	_check(absf((sf.player_pos.x - 200.0) - GameSim.ZONE_FLOW_SPEED) < 2.0 and absf(sf.player_pos.y - 360.0) < 0.01 and sf.zone_debuff == "flow", "流れ: 入力がなくても、1 秒で %.0f px 押される(%.1f px)" % [GameSim.ZONE_FLOW_SPEED, sf.player_pos.x - 200.0])
	var left := func(_n: float) -> Vector2: return Vector2(-1, 0)
	var sf2 = _make([fz])[0]
	sf2.player_pos = Vector2(500, 360)
	_run(sf2, 0.0, 1.0, left)
	_check(absf((sf2.player_pos.x - 500.0) - (GameSim.ZONE_FLOW_SPEED - GameSim.PLAYER_SPEED)) < 3.0, "流れ: 逆向きに進むと、押されたぶん遅くなる(1 秒で %.0f px)" % (sf2.player_pos.x - 500.0))
	var sf3 = _make([fz])[0]
	sf3.player_pos = Vector2(200, 360)
	sf3.step_relative(0.0, 0.1, Vector2.ZERO, false)
	_check(absf((sf3.player_pos.x - 200.0) - GameSim.ZONE_FLOW_SPEED * 0.1) < 0.01, "流れ: マウス操作(相対移動)でも、押される")
	var sf4 = _make([_zone([{"shape": ZoneArea.rect(0.0, 0.0, 0.5, 1.0), "type": "flow", "dir": Vector2(0, 1)}])])[0]
	sf4.player_pos = Vector2(700, 300)
	_run(sf4, 0.0, 0.5)
	_check(sf4.player_pos == Vector2(700, 300) and sf4.zone_push == Vector2.ZERO, "流れ: エリアの外では、押されない")
	# 淀みは、予告の間は効かない。円の淀みも効く
	var sw2 = _make([_zone([{"shape": ZoneArea.disc(0.5, 0.5, 0.3), "type": "warp"}], 2.0, 6.0)])[0]
	sw2.player_pos = Vector2(100, 700)
	sw2.field.add(Vector2(480, 200), Vector2(0, 40), 5.0, 0, 0.0)
	_run(sw2, 0.0, 1.0)
	_check(sw2.field.tscale[0] == 1.0 and absf(sw2.field.pos[0].y - 240.0) < 0.5, "時の淀み: 予告の間は効かない")
	sw2.field.pos[0] = Vector2(480, 300)
	_run(sw2, 2.0, 1.0)
	_check(sw2.field.tscale[0] < 0.7, "時の淀み(円): 発動したら、円の中の弾が遅くなる(%.2f 倍)" % sw2.field.tscale[0])
	# 動く帯: 自機がいるかどうかは、時刻で決まる
	var sweep := ZoneArea.rect(0.0, 0.0, 0.3, 1.0, Vector2(0.7, 0.0))
	var sz = _make([_zone([{"shape": sweep, "type": "slow"}], 0.0, 10.0)])[0]
	sz.player_pos = Vector2(100, 300)
	_run(sz, 0.0, 0.05)
	var early: String = sz.zone_debuff
	_run(sz, 5.0, 0.05)
	var late: String = sz.zone_debuff
	sz.player_pos = Vector2(480, 300)
	_run(sz, 5.05, 0.05)
	_check(early == "slow" and late == "" and sz.zone_debuff == "slow", "動く帯: 発動直後は左端・半ばには中央に来る")
	# 撃破(MOD)ではエリアを出さない
	var boss_sim := GameSim.new()
	var bf := BulletField.new()
	boss_sim.setup(bf, {"events": [], "gizmos": [], "warn_lead": 0.6, "breaks": [], "zones": [_zone([_all("poison")])]}, 100.0, false, {"boss": true})
	_check(boss_sim.zones.is_empty(), "撃破 MOD では、エリアは出ない")


func _test_coop() -> void:
	# 参加者の癒し・グレイズの上乗せは、自分では反映せず、ホストへ報告する
	var cl = _make([_zone([_all("heal")])], 2, false)
	var sc = cl[0]
	sc.player_pos = MID
	_run(sc, 0.0, 2.0)
	var rep: Dictionary = sc.take_contact()
	_check(rep.get("hl", 0.0) > 0.01 and sc.gauge == 1.0, "参加者: 癒しは自分のゲージには足さず、報告に溜める(%.3f 秒ぶん)" % rep.get("hl", 0.0))
	var host = _make([], 2, true)
	host[0].gauge = 0.5
	host[0].ext_report(0.0, 0, 0, 0.0, rep.hl, 0.0)
	_check(absf((host[0].gauge - 0.5) - rep.hl / 0.5) < 1e-6, "ホスト: 共有ゲージ(2 人で満タン = 0.5s)に換算して回復する(+%.3f)" % (host[0].gauge - 0.5))
	var cg = _make([_zone([_all("bonus")])], 2, false)
	var sg = cg[0]
	sg.player_pos = MID
	sg.field.add(MID + Vector2(24, 0), Vector2.ZERO, 6.0, 0, 0.0)
	_run(sg, 0.0, 0.05)
	var rep2: Dictionary = sg.take_contact()
	_check(absf(rep2.get("zb", 0.0) - GameSim.ZONE_GRAZE_BONUS) < 1e-9 and rep2.z == 1, "参加者: グレイズの上乗せも報告する(グレイズ %d・上乗せ %.1f)" % [rep2.z, rep2.get("zb", 0.0)])
	host[0].ext_report(0.0, rep2.z, 0, 0.0, 0.0, rep2.zb)
	_check(absf(host[0].graze_bonus - GameSim.ZONE_GRAZE_BONUS) < 1e-9, "ホスト: 上乗せを、ボーナス点のグレイズに足す")
	_check(rep2.get("zr", 0) == 1 and sg.damage_refund == 0.0, "参加者: 稼ぎのグレイズの数も報告する(係数の回復はホストが決める)")
	var hr = _make([], 2, true)[0]
	hr.damage_total = 0.6
	hr.ext_report(0.0, rep2.z, 0, 0.0, 0.0, rep2.zb, rep2.zr)
	_check(hr.damage_refund > 0.0 and hr.damage_total == 0.6 and hr.damage_factor > exp(-0.6 / hr.damage_tau), "ホスト: 係数を取り戻す(共有の係数が +%.5f)" % (hr.damage_factor - exp(-0.6 / hr.damage_tau)))
	var cr = _make([], 2, false)[0]
	cr.apply_net_state(hr.net_state())
	_check(absf(cr.damage_factor - hr.damage_factor) < 1e-9, "参加者: 共有の状態で、同じ係数になる")
	# 報告するものがなければ、空
	var idle = _make([], 2, false)
	_check(idle[0].take_contact().is_empty(), "何もなければ、報告は空")
