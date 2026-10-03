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
##   drain_mul    … その被弾時間にかかる倍率(複数なら乗算)。弾幕 v2 は ×1.2(250ms → 300ms。回復は割合なので、絶対値でも自動で増える)。地獄(150ms)と併用なら 180ms
##   low_protect  … ゲージ 20% 以下で被ダメージ半減するか。1 つでも false なら false
##   practice     … ゲージが 0 になってもゲームオーバーにならない(練習)。1 つでも true なら true
##   dark         … 自機の周囲しか弾が見えない(描画だけ。判定・難易度は変わらない)。1 つでも true なら true
##   field_scale  … 自機が動ける範囲(盤面の中央の長方形)の縦横の倍率。発射位置は変わらない。複数なら小さいほう
##   boss         … 発射位置へ動くボスを、自機の自動の連射で倒す(scripts/game/boss.gd)。倒すまで曲が繰り返し、危険エリアは出ない。ひとり用。1 つでも true なら true
##   gen_v2       … 弾幕の作り方を v2(scripts/game/pattern_gen_v2.gd)に切り替える。生成の段階で効くので、apply() は何もしない。1 つでも true なら true
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
	# 小型化・撃破のベーススコアの加算は仮の値(弾幕を変えないので Lv には出ない。遊んで見直す)
	{
		"id": "shrink", "name": "小型化", "tag": "SHRINK", "color": Color(0.45, 0.95, 0.75),
		"desc": "自機が動ける範囲が、盤面の中央の縦横 50% になる(発射位置は今までどおり。危険エリアも範囲の中) / ベーススコア +10%",
		"field_scale": 0.5, "score_mul": 1.10,
	},
	{
		"id": "boss", "name": "撃破", "tag": "BOSS", "color": Color(1.0, 0.5, 0.42),
		"desc": "発射位置を追って動くボスを連射で倒す / 倒すまで曲が繰り返す・当てると回復・危険エリアなし(ひとり用) / ベーススコア +5%",
		"boss": true, "score_mul": 1.05, "solo": true,
	},
	# 弾幕 v2: 難しくする MOD ではなく、弾幕の作り方の切り替え(スコア倍率 ×1.0)。難易度(Lv)は v2 の弾幕で測る
	{
		"id": "v2", "name": "弾幕 v2", "tag": "V2", "color": Color(0.45, 0.85, 1.0),
		"desc": "譜面ごとに特徴の出る別の弾幕(連打は渦・ジャンプは交差・スライダーは幕など。止まって再発進する弾・分裂する弾もある) / 体力 300ms(+20%) / ベーススコアは変わらない",
		"gen_v2": true, "drain_mul": 1.2, "score_mul": 1.0,
	},
	{
		"id": "practice", "name": "練習", "tag": "PRACTICE", "color": Color(1.0, 0.82, 0.35),
		"desc": "ゲージが 0 になってもゲームオーバーにならず、最後まで続けられる / ベーススコア −50%",
		"practice": true, "score_mul": 0.5,
	},
]


## マルチプレイで使えない MOD(solo)を除いた id の配列。
static func multi_ok(ids: Array) -> Array:
	return ids.filter(func(id): return not bool(find(str(id)).get("solo", false)))


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
		"drain_mul": 1.0,
		"low_protect": true,
		"practice": false,
		"dark": false,
		"field_scale": 1.0,
		"boss": false,
		"gen_v2": false,
	}
	for id in ids:
		var m := find(str(id))
		if m.is_empty() or p.ids.has(m.id):
			continue
		p.ids.append(m.id)
		for key in ["size_mul", "speed_mul", "count_mul", "player_scale", "rate", "score_mul"]:
			p[key] *= float(m.get(key, 1.0))
		p.drain_time = minf(p.drain_time, float(m.get("drain_time", GameSim.GAUGE_DRAIN_TIME)))
		p.drain_mul *= float(m.get("drain_mul", 1.0))
		p.low_protect = p.low_protect and bool(m.get("low_protect", true))
		p.practice = p.practice or bool(m.get("practice", false))
		p.dark = p.dark or bool(m.get("dark", false))
		p.field_scale = minf(p.field_scale, float(m.get("field_scale", 1.0)))
		p.boss = p.boss or bool(m.get("boss", false))
		p.gen_v2 = p.gen_v2 or bool(m.get("gen_v2", false))
	p.drain_time *= p.drain_mul   # 最終の被弾時間(min の結果に、倍率をかける)
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
			if s.get("keep_n", false):   # 弾幕 v2 の壁の弾など、本数を変えると形が崩れるもの(弾数の倍率は掛けない)
				shots.append(s2)
				continue
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
	var rating := PatternGen.measure(events, out.get("breaks", []), float(gen.size) * float(p.size_mul) if bool(gen.get("size_weight", false)) else 0.0)   # 休憩地帯は、再生速度を反映したもの。弾幕 v2 は弾ごとの大きさも数える
	var speed: float = float(gen.speed) * float(p.speed_mul)
	var size: float = float(gen.size) * float(p.size_mul)
	out.rating = rating
	out.speed = speed
	out.size = size
	out.level = PatternGen.level_of(rating.score, speed, size, PatternGen.PLAYER_HIT_R * float(p.player_scale), rating.duration, float(gen.get("speed_ref", PatternGen.BASE_SPEED)))
	return out
