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
##   drain_time   … ゲージ満タンぶんの被弾時間(秒)。指定した MOD が複数なら短いほう(指定がなければ GameSim.GAUGE_DRAIN_TIME)
##   drain_mul    … その被弾時間にかかる倍率(複数なら乗算)。弾幕 v2(MOD「弾幕 v1」を付けていないとき)は ×1.2 が自動で掛かる(250ms → 300ms。回復は割合なので、絶対値でも自動で増える)。地獄(150ms)と併用なら 180ms、天国(500ms)なら 600ms
##   low_protect  … 低体力で被ダメージ半減するか。1 つでも false なら false
##   low_threshold … 被ダメージが半減になるゲージの境目(初期 GameSim.GAUGE_LOW_THRESHOLD = 20%)。複数なら大きいほう
##   regen        … 被弾していないときの自然回復があるか。1 つでも false なら false(癒しのエリア・撃破で当てたときの回復は別で、そのまま)
##   practice     … ゲージが 0 になってもゲームオーバーにならない(練習)。1 つでも true なら true
##   dark         … 自機の周囲しか弾が見えない(描画だけ。判定・難易度は変わらない)。1 つでも true なら true
##   field_scale  … 自機が動ける範囲(盤面の中央の長方形)の縦横の倍率。発射位置は変わらない。複数なら小さいほう
##   boss         … 発射位置へ動くボスを、自機の自動の連射で倒す(scripts/game/boss.gd)。倒すまで曲が繰り返し、危険エリアは出ない。ひとり用。1 つでも true なら true
##   gen_v1       … 弾幕の作り方を、旧い v1(scripts/game/pattern_gen.gd)に切り替える MOD「弾幕 v1」。生成の段階で効くので、apply() は何もしない。1 つでも true なら true
##   gen_v2       … 弾幕の作り方が v2(scripts/game/pattern_gen_v2.gd。初期状態)か。gen_v1 でなければ true(MOD の効果ではなく、gen_v1 から決まる)
##   excl         … 同時に付けられない MOD の id(片方を付けると、もう片方は外れる。conflicts() は両向きに見る。params() は後のほうを無視する)
## MOD を足すときは ALL に 1 件足すだけ(メニュー・HUD・リザルトは ALL を見て表示する)。
##
## ## 難易度は MOD を適用した弾幕で計算し直す
## apply() は、生成済みの弾幕(PatternGen.generate の結果)に MOD の効果を掛け、その弾幕で画面内の弾数 N(t) と Lv を
## 測り直す。譜面ごとの生成(弾数の自動調整)には影響させない: MOD で難しくなった分は、そのまま Lv に出る。

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")

## ベーススコアの加算(score_mul)の決め方: その MOD で上がる Lv(手元の 46 譜面の平均で、暴風雨 +56% / 巨人 +34% / 加速 +30% / 地獄 +16% / 暗闇 0%)の
## およそ 0.2 倍を基準にし(緩やかな加算)、Lv に出ない厳しさがあるもの(地獄: 体力 250→150ms・低体力の半減なし / 暗闇: 見えにくさ)は +5% ずつ上乗せした。
## 易しくする MOD の減算は、同じ量だけ難しくする MOD の加算の 3〜4 倍にした(稼ぎに使えないように)。tools/difficulty_study.gd の mods で測った値(46 譜面・弾幕 v2):
##   減速: Lv −25%(0.2 倍の決まりなら −5%)。ボット(強・弱の 2 体)が途中で倒れた数は 15 → 4(加速は 15 → 24)。→ −20%
##   天国: Lv −15%(弾サイズ)に加え、倒れるまでの被弾時間が約 2.25 倍(360 → 810ms。地獄の 0.5 倍の逆向き。地獄の +5% に当たる分が約 −6%)。
##         0.2 倍の決まりなら約 −9%。ボットが倒れた数は 15 → 0(どの MOD よりも易しい)。→ −35%(倒れない「練習」の −50% よりは小さく)
##   無回復: ボットが倒れた数は 15 → 26(加速と同じくらい)だが、加算はユーザーの指定で +3%
## v0.15(SIZE_EXP 1.0 → 1.3)で測り直した(mods jobs=14 sexp=1.0 と 1.3 を、同じ 46 譜面・同じ測り方で比べた。Lv の比は v2 の表で数える):
##   MOD で上がる Lv: 巨人 +42.5% → +57.4%(1.35 倍)/ 地獄 +19.5% → +25.1%(1.29 倍)/ 天国 −16.2% → −21.2%(1.31 倍)。暴風雨・加速・減速は ±1% 以内で変わらない。
##   加算の Lv の部分を、この比で大きくした: 巨人 +7% → +9% / 地獄(Lv の部分 +3% → +4%、体力の上乗せ +5% はそのまま)+8% → +9% / 天国 −35% → −40%(同じ 4.4 倍の決まり)。
## MOD や譜面の仕様を変えたら、測り直して見直す。
## 弾幕 v2(初期状態)の被弾時間の倍率(250ms → 300ms)
const V2_DRAIN_MUL := 1.2

const ALL := [
	{
		"id": "hell", "name": "地獄", "tag": "HELL", "color": Color(1.0, 0.32, 0.3),
		"desc": "弾サイズ +35% / 体力 150ms / 低体力の被ダメージ半減なし / ベーススコア +9%",
		"size_mul": 1.35, "drain_time": 0.15, "low_protect": false, "score_mul": 1.09, "excl": ["heaven"],
	},
	{
		"id": "storm", "name": "暴風雨", "tag": "STORM", "color": Color(0.5, 0.8, 1.0),
		"desc": "弾の量 +50% / 弾の速度 +50% / ベーススコア +11%",
		"count_mul": 1.5, "speed_mul": 1.5, "score_mul": 1.11,
	},
	{
		"id": "giant", "name": "巨人", "tag": "GIANT", "color": Color(1.0, 0.75, 0.35),
		"desc": "自機サイズ +100% / ベーススコア +9%",
		"player_scale": 2.0, "score_mul": 1.09,
	},
	{
		"id": "rush", "name": "加速", "tag": "RUSH", "color": Color(0.82, 0.6, 1.0),
		"desc": "譜面の再生速度 +50%(曲の音程も上がる) / ベーススコア +6%",
		"rate": 1.5, "score_mul": 1.06, "excl": ["slow"],
	},
	{
		"id": "dark", "name": "暗闇", "tag": "DARK", "color": Color(0.55, 0.65, 0.95),
		"desc": "自機の周囲しか弾が見えない(離れるほど消える。発射地点は見える) / ベーススコア +5%",
		"dark": true, "score_mul": 1.05,
	},
	# 小型化・無回復・撃破のベーススコアの加算は、遊んだ感触で決めた値(弾幕を変えないので Lv には出ない)
	{
		"id": "shrink", "name": "小型化", "tag": "SHRINK", "color": Color(0.45, 0.95, 0.75),
		"desc": "自機が動ける範囲が、盤面の中央の縦横 50% になる(発射位置は今までどおり。危険エリアも範囲の中) / ベーススコア +4%",
		"field_scale": 0.5, "score_mul": 1.04,
	},
	{
		"id": "noregen", "name": "無回復", "tag": "NOREGEN", "color": Color(0.85, 0.62, 0.5),
		"desc": "被弾していないときの自然回復がなくなる(癒しのエリア・撃破で当てたときの回復は今までどおり) / ベーススコア +3%",
		"regen": false, "score_mul": 1.03,
	},
	{
		"id": "boss", "name": "撃破", "tag": "BOSS", "color": Color(1.0, 0.5, 0.42),
		"desc": "発射位置を追って動くボスを連射で倒す / 倒すまで曲が繰り返す・当てると回復・危険エリアなし(ひとり用) / ベーススコア +5%",
		"boss": true, "score_mul": 1.05, "solo": true,
	},
	# 易しくする MOD(ベーススコアは減る)。減らし方は、難しくする MOD の加算より大きくした(上の score_mul の決め方)
	{
		"id": "heaven", "name": "天国", "tag": "HEAVEN", "color": Color(1.0, 0.72, 0.88),
		"desc": "弾サイズ −30% / 体力 500ms / 体力 35% 以下で被ダメージ半減(通常は 20%) / ベーススコア −40%",
		"size_mul": 0.7, "drain_time": 0.5, "low_threshold": 0.35, "score_mul": 0.6, "excl": ["hell"],
	},
	{
		"id": "slow", "name": "減速", "tag": "SLOW", "color": Color(0.62, 0.9, 0.45),
		"desc": "譜面の再生速度 ×2/3(曲の音程も下がる) / ベーススコア −20%",
		"rate": 2.0 / 3.0, "score_mul": 0.8, "excl": ["rush"],
	},
	# 弾幕 v1: 難しくする MOD ではなく、旧い弾幕の作り方への切り替え(スコア倍率 ×1.0)。初期状態は弾幕 v2。難易度(Lv)は v1 の弾幕で測る
	{
		"id": "v1", "name": "弾幕 v1", "tag": "V1", "color": Color(0.45, 0.85, 1.0),
		"desc": "旧い弾幕の作り方(ノーツの位置から均等に撃つ、どの譜面も似た形の弾幕) / 危険エリアが旧来の 3×3 のマスに(デバフを受ける) / 体力 250ms(弾幕 v2 は 300ms) / ベーススコアは変わらない",
		"gen_v1": true, "score_mul": 1.0,
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


## a と b は同時に付けられないか(どちらかの excl に、もう片方が入っている)。
static func conflicts(a: String, b: String) -> bool:
	return a != b and ((find(a).get("excl", []) as Array).has(b) or (find(b).get("excl", []) as Array).has(a))


## ids に id を付けた(on)/外した配列を返す。付けるときは、同時に付けられないものを外す(外した id は removed に入る)。
static func toggled(ids: Array, id: String, on: bool, removed: Array = []) -> Array:
	var out := ids.duplicate()
	if on:
		for x in ids:
			if conflicts(str(x), id):
				out.erase(x)
				removed.append(x)
		if not out.has(id):
			out.append(id)
	else:
		out.erase(id)
	return out


## 付けた MOD(id の配列)の効果を合成する。未知の id・重複・同時に付けられないもの(後のほう)は無視する。
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
		"low_threshold": GameSim.GAUGE_LOW_THRESHOLD,
		"regen": true,
		"practice": false,
		"dark": false,
		"field_scale": 1.0,
		"boss": false,
		"gen_v1": false,
		"gen_v2": true,
	}
	var drain := INF   # MOD が指定した被弾時間のうち、短いもの(なければ初期値)
	for id in ids:
		var m := find(str(id))
		if m.is_empty() or p.ids.has(m.id):
			continue
		if p.ids.any(func(x): return conflicts(x, m.id)):   # 同時に付けられないもの: 先に付いているほうを残す
			continue
		p.ids.append(m.id)
		for key in ["size_mul", "speed_mul", "count_mul", "player_scale", "rate", "score_mul"]:
			p[key] *= float(m.get(key, 1.0))
		if m.has("drain_time"):
			drain = minf(drain, float(m.drain_time))
		p.drain_mul *= float(m.get("drain_mul", 1.0))
		p.low_protect = p.low_protect and bool(m.get("low_protect", true))
		p.low_threshold = maxf(p.low_threshold, float(m.get("low_threshold", 0.0)))
		p.regen = p.regen and bool(m.get("regen", true))
		p.practice = p.practice or bool(m.get("practice", false))
		p.dark = p.dark or bool(m.get("dark", false))
		p.field_scale = minf(p.field_scale, float(m.get("field_scale", 1.0)))
		p.boss = p.boss or bool(m.get("boss", false))
		p.gen_v1 = p.gen_v1 or bool(m.get("gen_v1", false))
	if drain < INF:
		p.drain_time = drain
	p.gen_v2 = not p.gen_v1   # 弾幕の作り方は v2 が初期状態。MOD「弾幕 v1」を付けたときだけ v1
	if p.gen_v2:
		p.drain_mul *= V2_DRAIN_MUL   # 弾幕 v2 は体力 +20%(MOD の地獄などと併用なら、その被弾時間に掛かる)
	p.drain_time *= p.drain_mul   # 最終の被弾時間(min の結果に、倍率をかける)
	return p


## 付けた MOD の表示名(例: "地獄 + 加速")。なければ空文字。
static func names(ids: Array) -> String:
	var out: Array = []
	for id in params(ids).ids:
		out.append(find(id).name)
	return " + ".join(out)


## この MOD の組み合わせが、弾幕(発射の一覧)を変えない(= 難易度の統計だけで Lv が分かる)か。練習・暗闇などは変えない。
## 加速・弾数・弾速・弾の大きさ・自機の大きさは変える。
static func pattern_neutral(p: Dictionary) -> bool:
	return is_equal_approx(p.rate, 1.0) and is_equal_approx(p.count_mul, 1.0) and is_equal_approx(p.size_mul, 1.0) \
			and is_equal_approx(p.speed_mul, 1.0) and is_equal_approx(p.player_scale, 1.0)


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
	if p.ids.is_empty() or pattern_neutral(p):
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
	var sexp := float(gen.get("size_exp", PatternGen.SIZE_EXP))   # 弾幕を作ったときと同じ指数で測る(前の版のリプレイは、前の指数)
	var rating := PatternGen.measure(events, out.get("breaks", []), float(gen.size) * float(p.size_mul) if bool(gen.get("size_weight", false)) else 0.0, sexp)   # 休憩地帯は、再生速度を反映したもの。弾幕 v2 は弾ごとの大きさも数える
	var speed: float = float(gen.speed) * float(p.speed_mul)
	var size: float = float(gen.size) * float(p.size_mul)
	out.rating = rating
	out.speed = speed
	out.size = size
	out.level = PatternGen.level_of(rating.score, speed, size, PatternGen.PLAYER_HIT_R * float(p.player_scale), rating.duration, float(gen.get("speed_ref", PatternGen.BASE_SPEED)), gen.get("table", PatternGen.TARGET_TABLE), sexp)
	return out
