extends RefCounted
## リザルトの中身(UI を持たない)。プレイの結果(stats)から、ランク・達成率・体力グラフの系列・マルチプレイの成績の一覧を作る。
## リザルト画面(classic も、別の UI も)は、これを使って表示するだけにする(docs/ui_plan.md の §2.3)。
## stats の形は GameScreen._stats() が正。net はマルチプレイのとき通信層(他の人の最終成績 net.results を読む)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")

var stats: Dictionary
var net

var failed := false
var is_mp := false
var versus := false
var score := 0                 # 表示するスコア(四捨五入。プレイ中の表示と同じ)
var score_base := 1000000.0
var rank := "-"
var ratio := 0.0               # 達成率(ゲームオーバーなら到達度。撃破では、ボスを削った割合)


func setup(p_stats: Dictionary, p_net = null) -> void:
	stats = p_stats
	is_mp = p_stats.has("mp")
	net = p_net if is_mp else null
	versus = is_mp and p_stats.mp.mode == "versus"
	failed = bool(p_stats.failed)
	# クリアしたときだけスコアが残る。ランクは、ノーミスなら SS、それ以外は達成率(スコア ÷ ベーススコア)で S〜F
	score = int(round(p_stats.score))   # プレイ中の表示(四捨五入)と同じにする。切り捨てだと 1 ずれる
	score_base = float(p_stats.get("score_base", 1000000.0))
	rank = GameSim.rank_of(failed, int(p_stats.hits), float(p_stats.score), score_base)
	ratio = clampf(float(p_stats.progress), 0.0, 1.0) if failed else clampf(float(p_stats.score) / maxf(score_base, 1.0), 0.0, 1.0)
	if failed and p_stats.has("boss"):   # 撃破: 曲が繰り返すので、到達度の代わりにボスを削った割合
		ratio = clampf(1.0 - float(p_stats.boss.hp_left), 0.0, 1.0)


## MOD によるベーススコアの倍率の注記(なければ空)。
func mod_note() -> String:
	if absf(score_base - 1000000.0) < 1.0:
		return ""
	return "MOD  ×%.4f" % (score_base / 1000000.0)


## 体力グラフの中身。own_color: ひとり・協力の体力の線の色(体力に応じて変わる by_hp の線なので、基準の色)。
## 返す辞書: {series(HpGraph.set_data に渡す線の一覧), t0, t1(横軸の範囲・秒), legend(凡例 [{name, color, me} / {label}])}。
## ひとりと協力は自分の(チームの)体力の 1 本、対戦は参加者の体力を色分けして重ねる(他の人の分は届いたものから)。
func graph(own_color: Color) -> Dictionary:
	var series: Array = []
	var legend: Array = []
	var own := HpGraph.points_from_log(stats.get("hp_log", PackedFloat32Array()), float(stats.get("hp_step", 0.25)),
		float(stats.get("hp_t_end", 0.0)), float(stats.get("hp_end", 0.0)))
	if versus:
		var res: Dictionary = net.results if net != null else {}
		for p in stats.mp.players:
			var col: Color = MpGame.SLOT_COLORS[int(p.slot) % MpGame.SLOT_COLORS.size()]
			var me: bool = int(p.id) == int(stats.mp.my_id)
			var pts := PackedVector2Array()
			var dead := false
			if me:
				pts = own
				dead = failed
			elif res.has(p.id) and res[p.id].get("hp", []) is Array and (res[p.id].hp as Array).size() >= 2:
				pts = HpGraph.points_from_samples(res[p.id].hp, float(res[p.id].get("dur", 0.0)))
				dead = bool(res[p.id].get("failed", false))
			if pts.size() >= 2:
				series.append({"pts": pts, "color": col, "thick": 3.0 if me else 2.0, "fill": me, "end_mark": dead})
			legend.append({"name": str(p.name), "color": col, "me": me})
	else:
		series.append({"pts": own, "color": own_color, "thick": 3.0, "by_hp": true, "end_mark": failed})
		if is_mp:
			legend.append({"label": "チーム共通の体力"})
	# 横軸は、最初のノーツから最後のノーツまで(ゲームオーバーなら、線は途中で終わる)
	var ff: float = float(stats.get("first_fire", -1.0))
	var lf: float = float(stats.get("last_fire", -1.0))
	var t0 := 0.0
	var t1 := 1.0
	if ff >= 0.0 and lf > ff:
		t0 = ff
		t1 = lf
		for s in series:
			s.pts = HpGraph.clip_range(s.pts, t0, t1)
		series = series.filter(func(s): return (s.pts as PackedVector2Array).size() >= 2)
	else:   # ノーツの時刻が分からない(古い記録など): 記録の全体
		for s in series:
			t1 = maxf(t1, (s.pts as PackedVector2Array)[(s.pts as PackedVector2Array).size() - 1].x)
	return {"series": series, "t0": t0, "t1": t1, "legend": legend}


## マルチプレイの成績の一覧。対戦はスコアの高い順(1 位に lead。全員が終えたら all_done)、協力は 1 人ずつ。
## 自分の分は、通信を待たずにこの画面の値を使う。まだ終えていない人は res が null(「プレイ中」)。
## 返す辞書: {rows [{id, name, slot, res, place, lead, rank(対戦で終えた人だけ。それ以外は "")}], versus, all_done, base}
func board() -> Dictionary:
	var mp: Dictionary = stats.mp
	var res: Dictionary = net.results.duplicate() if net != null else {}
	res[int(mp.my_id)] = {"score": float(stats.score), "hits": int(stats.hits) if versus else int(res.get(int(mp.my_id), {}).get("hits", stats.hits)),
		"graze": int(res.get(int(mp.my_id), {}).get("graze", stats.graze)), "hit_ms": int(res.get(int(mp.my_id), {}).get("hit_ms", stats.hit_ms)),
		"dmg": float(res.get(int(mp.my_id), {}).get("dmg", stats.get("own_damage", stats.damage)))}
	var rows: Array = []
	for p in mp.players:
		if net != null and p.id != int(mp.my_id) and not net.players.has(p.id) and not res.has(p.id):
			continue   # 終える前に去った人
		rows.append({"id": p.id, "name": p.name, "slot": p.slot, "res": res.get(p.id)})
	if versus:
		rows.sort_custom(func(a, b):
			if (a.res != null) != (b.res != null):
				return a.res != null
			if a.res == null:
				return a.slot < b.slot
			return float(a.res.score) > float(b.res.score))
	var all_done := true
	for r in rows:
		if r.res == null:
			all_done = false
	var place := 0
	for r in rows:
		place += 1
		r["place"] = place
		r["lead"] = versus and place == 1 and r.res != null
		r["rank"] = GameSim.rank_of(false, int(r.res.hits), float(r.res.score), score_base) if versus and r.res != null else ""
	return {"rows": rows, "versus": versus, "all_done": all_done, "base": score_base}
