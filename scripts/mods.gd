extends RefCounted
## MOD(プレイ前に付けるかどうかを選ぶ、難易度・スコアの修飾)。
##
## 1 つの MOD は「効果の辞書」。複数付けたときは、効果ごとに次のように合成する(倍率はすべて乗算):
##   size_mul     … 弾サイズの倍率
##   speed_mul    … 弾速の倍率
##   count_mul    … 弾数(1 回の発射ごとの n)の倍率
##   player_scale … 自機サイズ(当たり判定・見た目)の倍率
##   rate         … 譜面の再生速度(曲と弾幕の発射が rate 倍で進む。弾速は変わらない)
##   score_mul    … ベーススコア 1,000,000 にかかる倍率(グレイズボーナスにはかからない)。6%2 つなら 1.06 × 1.06
##   drain_time   … ゲージ満タンぶんの被弾時間(秒)。複数なら短いほう
##   low_protect  … ゲージ 20% 以下で被ダメージ半減するか。1 つでも false なら false
##   practice     … ゲージが 0 になってもゲームオーバーにならない(練習)。1 つでも true なら true
##   dark         … 自機の周囲しか弾が見えない(描画だけ。判定・難易度は変わらない)。1 つでも true なら true
## MOD を足すときは ALL に 1 件足すだけ(メニュー・HUD・リザルトは ALL を見て表示する)。
##
## ## 難易度は MOD を適用した弾幕で計算し直す
## apply() は、生成済みの弾幕(PatternGen.generate の結果)に MOD の効果を掛け、その弾幕で画面内の弾数 N(t) と Lv を
## 測り直す。譜面ごとの生成(弾数の自動調整)には影響させない: MOD で難しくなった分は、そのまま Lv に出る。

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

## ベーススコアの加算(score_mul)の決め方: その MOD で上がる Lv(手元の 46 譜面の平均で、暴風雨 +56% / 巨人 +34% / 加速 +30% / 地獄 +16% / 暗闇 0%)の
## およそ 0.2 倍を基準にし(緩やかな加算)、Lv に出ない厳しさがあるもの(地獄: 体力 250→150ms・低体力の半減なし / 暗闇: 見えにくさ)は +5% ずつ上乗せした。
## MOD や譜面の仕様を変えたら、測り直して見直す。
const ALL := [
	{
		"id": "hell", "name": "地獄", "tag": "HELL", "color": Color(1.0, 0.32, 0.3),
		"desc": "弾サイズ +35% / 体力 150ms / 低体力の被ダメージ半減なし / ベーススコア +8%",
		"size_mul": 1.35, "drain_time": 0.15, "low_protect": false, "score_mul": 1.08,
	},
	{
		"id": "storm", "name": "暴風雨", "tag": "STORM", "color": Color(0.5, 0.8, 1.0),
		"desc": "弾の量 +50% / 弾の速度 +50% / ベーススコア +11%",
		"count_mul": 1.5, "speed_mul": 1.5, "score_mul": 1.11,
	},
	{
		"id": "giant", "name": "巨人", "tag": "GIANT", "color": Color(1.0, 0.75, 0.35),
		"desc": "自機サイズ +100% / ベーススコア +7%",
		"player_scale": 2.0, "score_mul": 1.07,
	},
	{
		"id": "rush", "name": "加速", "tag": "RUSH", "color": Color(0.82, 0.6, 1.0),
		"desc": "譜面の再生速度 +50%(曲の音程も上がる) / ベーススコア +6%",
		"rate": 1.5, "score_mul": 1.06,
	},
	{
		"id": "dark", "name": "暗闇", "tag": "DARK", "color": Color(0.55, 0.65, 0.95),
		"desc": "自機の周囲しか弾が見えない(離れるほど消える。発射地点は見える) / ベーススコア +5%",
		"dark": true, "score_mul": 1.05,
	},
	{
		"id": "practice", "name": "練習", "tag": "PRACTICE", "color": Color(1.0, 0.82, 0.35),
		"desc": "ゲージが 0 になってもゲームオーバーにならず、最後まで続けられる / ベーススコア −50%",
		"practice": true, "score_mul": 0.5,
	},
]


## MOD の id から定義を引く(なければ空の辞書)。
static func find(id: String) -> Dictionary:
	for m in ALL:
		if m.id == id:
			return m
	return {}


## 付けた MOD(id の配列)の効果を合成する。未知の id・重複は無視する。
static func params(ids: Array) -> Dictionary:
	var p := {
		"ids": [],
		"size_mul": 1.0,
		"speed_mul": 1.0,
		"count_mul": 1.0,
		"player_scale": 1.0,
		"rate": 1.0,
		"score_mul": 1.0,
		"drain_time": GameSim.GAUGE_DRAIN_TIME,
		"low_protect": true,
		"practice": false,
		"dark": false,
	}
	for id in ids:
		var m := find(str(id))
		if m.is_empty() or p.ids.has(m.id):
			continue
		p.ids.append(m.id)
		for key in ["size_mul", "speed_mul", "count_mul", "player_scale", "rate", "score_mul"]:
			p[key] *= float(m.get(key, 1.0))
		p.drain_time = minf(p.drain_time, float(m.get("drain_time", GameSim.GAUGE_DRAIN_TIME)))
		p.low_protect = p.low_protect and bool(m.get("low_protect", true))
		p.practice = p.practice or bool(m.get("practice", false))
		p.dark = p.dark or bool(m.get("dark", false))
	return p


## 付けた MOD の表示名(例: "地獄 + 加速")。なければ空文字。
static func names(ids: Array) -> String:
	var out: Array = []
	for id in params(ids).ids:
		out.append(find(id).name)
	return " + ".join(out)


## 生成済みの弾幕に MOD を適用した新しい gen を返す(元の gen は変えない)。
## events / gizmos / breaks / rating / level / speed / size を MOD 適用後のものに置き換える(base_level = 適用前の Lv)。
##   - 弾数: 各ショットの n に count_mul を掛ける。端数は次のショットへ持ち越すので、合計はほぼ count_mul 倍になる
##   - 弾速・弾サイズ: そのまま倍率を掛ける
##   - 再生速度: イベント・ギズモ・休憩地帯の時刻を 1/rate にする(予兆の長さ・弾速は実時間のまま)
##   - 自機サイズ: 弾幕は変わらない。Lv の計算(危険半径)にだけ入る
static func apply(gen: Dictionary, p: Dictionary) -> Dictionary:
	var out := gen.duplicate()
	out["base_level"] = gen.level
	out["time_rate"] = 1.0
	# 弾幕に効かない MOD(練習・暗闇など)だけなら、測り直しは要らない(Lv はそのまま)
	var neutral: bool = is_equal_approx(p.rate, 1.0) and is_equal_approx(p.count_mul, 1.0) and is_equal_approx(p.size_mul, 1.0) \
			and is_equal_approx(p.speed_mul, 1.0) and is_equal_approx(p.player_scale, 1.0)
	if p.ids.is_empty() or neutral:
		return out
	var rate: float = p.rate
	var count_mul: float = p.count_mul
	var events: Array = []
	var carry := 0.0
	for e in gen.events:
		var e2: Dictionary = e.duplicate()
		e2.t = float(e.t) / rate
		var shots: Array = []
		for s in e.shots:
			var s2: Dictionary = s.duplicate()
			s2.size = float(s.size) * float(p.size_mul)
			s2.speed = float(s.speed) * float(p.speed_mul)
			var want := float(s.n) * count_mul + carry
			var n2 := maxi(int(floor(want + 0.000001)), 1)
			carry = want - n2
			s2.n = n2
			shots.append(s2)
		e2.shots = shots
		events.append(e2)
	out.events = events
	if not is_equal_approx(rate, 1.0):
		var gizmos: Array = []
		for g in gen.gizmos:
			var g2: Dictionary = g.duplicate()
			for key in ["t", "end", "span"]:
				if g2.has(key):
					g2[key] = float(g[key]) / rate
			gizmos.append(g2)
		out.gizmos = gizmos
		var zones2: Array = []
		for z in gen.get("zones", []):
			var z2: Dictionary = z.duplicate()
			for key in ["t", "end", "lead"]:
				z2[key] = float(z[key]) / rate
			zones2.append(z2)
		out.zones = zones2
		var breaks: Array = []
		for b in gen.get("breaks", []):
			breaks.append([float(b[0]) / rate, float(b[1]) / rate])
		out.breaks = breaks
	out["time_rate"] = rate
	# MOD 適用後の弾幕で難易度を測り直す
	var rating := PatternGen.measure(events, out.get("breaks", []))   # 休憩地帯は、再生速度を反映したもの
	var speed: float = float(gen.speed) * float(p.speed_mul)
	var size: float = float(gen.size) * float(p.size_mul)
	out.rating = rating
	out.speed = speed
	out.size = size
	out.level = PatternGen.level_of(rating.score, speed, size, PatternGen.PLAYER_HIT_R * float(p.player_scale), rating.duration)
	return out
