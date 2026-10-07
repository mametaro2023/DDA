extends RefCounted
## 1 回のサバイバルの状態(UI・音に依存しない。ヘッドレスで回せる)。docs/survival_plan.md。
## 何曲目か・目標の Lv・持ち越すゲージ・強化の段・曲ごとの点・合計点・乱数の種を持つ。
## 流れ: start → (pick_next → 曲を遊ぶ → song_done → 選べる回数だけ roll_choices / choose)を繰り返す → over になったら終わり。
##
## ## スコア
## 最終スコア = Σ(その曲のスコア × f(Lv))、f(Lv) = (Lv / F_REF)^2。
## その曲のスコア = 1 曲ずつのプレイと同じ点(クリアなら最終点)。倒れた・あきらめた曲は、そのときまでの点(クリアした場合の点 × 進み具合)。
## Lv = その曲で実際に遊んだ譜面の Lv(MOD 込み)。
##
## ## 体力(サバイバルだけの決まり)
## 体力の量は「初期の体力」(強化なし。MOD 込みの、ゲージ満タンぶんの被弾時間)を 1 とした絶対量で数える。「最大ゲージ」の強化は、この上限だけを増やす。
## 回復(自然回復・曲の間の回復・癒しのエリア)と、被ダメージ半減の境目は、初期の体力に対する量で決める(体力を増やしても、回復の絶対量は増えない)。
## ## 経験値とレベル(S2)
## 雑魚を倒して落ちた玉を取ると経験値が入る(scripts/game/enemies.gd)。経験値は曲をまたいで貯まり、XP_BASE + XP_STEP × いまのレベル で次のレベルへ上がる。
## 曲の途中でレベルが上がっても止めない。曲の間に、上がったレベルの数だけ 3 択を選ぶ。雑魚の HP は、何曲目かで少しずつ増える(ENEMY_HP_STEP)。
##
## 回復は「主に曲の間」: 曲の中の自然回復は毎秒 0.25%(ふつうは 1.5%。強化を 3 段とると 1%)にして、曲の中で削られたぶんが次の曲まで残るようにし、
## そのかわり曲の間に 35% 回復する。被ダメージ半減は 30% 以下(ふつうは 20%。リトライできないぶんの安全網)。身代わりだけは、いまの体力に対する割合(40%)。

const Upgrades = preload("res://scripts/survival/upgrades.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const Mods = preload("res://scripts/mods.gd")

const START_LEVELS := [2.0, 4.0, 6.0]   # 準備画面で選べる、開始の Lv
const LV_STEP := 0.3                    # 1 曲ごとに上がる目標の Lv
const BET_LV := 0.5                     # 背水: 次の曲の目標の Lv の上乗せ
const F_REF := 4.0                      # f(Lv) = (Lv / F_REF)^2
const BETWEEN_HEAL := 0.35              # 曲の間の回復(初期の体力に対する割合。回復の主な機会)
const BETWEEN_HEAL_STEP := 0.05         # 強化「曲の間の回復」の 1 段(同)
const MAX_GAUGE_STEP := 0.15            # 強化「最大ゲージ」の 1 段(初期の体力に対する割合。上限が増えるだけで、いまの体力は増えない)
const REGEN := 0.0025                   # 曲の中の自然回復(初期の体力に対する割合 / 秒。60 秒で 15%)
const REGEN_STEP := 0.0025              # 強化「自然回復」の 1 段(同)
const XP_BASE := 20.0                   # レベル 0 → 1 に要る経験値
const XP_STEP := 12.0                   # レベルが 1 上がるごとに、次に要る経験値が増える量
const BET_XP_MUL := 2.0                 # 背水: 次の曲の経験値の倍率
const ENEMY_HP_STEP := 0.12             # 雑魚の HP: 1 曲ごとに +12%
const LOW_LINE := 0.30                  # 被ダメージ半減の境目(初期の体力に対する割合。MOD「天国」の 35% のほうが高ければ、そちら)
const GUARD_GAUGE := 0.4                # 身代わりで踏みとどまったときのゲージ
## 付けられない MOD(練習 = 倒れない / 撃破 = 曲が繰り返す)
const BANNED_MODS := ["practice", "boss"]

var run_seed := 0
var rng := RandomNumberGenerator.new()
var start_level := 4.0
var mod_ids: Array = []
var gauge := 1.0                 # 次の曲を始めるときの体力(初期の体力 = 1 の絶対量。上限は max_gauge())
var levels := {}                 # 強化の id → 段
var guard := 0                   # 身代わりの残り
var bet_next := false            # 背水: 次の曲の目標の Lv を上げる
var songs: Array = []            # 遊んだ曲 [{title, version, md5, key, level, score, f, points, failed, gave_up, played_s, extra_mods}]
var total := 0.0                 # 合計点
var picks := 0                   # まだ選んでいない 3 択の回数
var xp := 0.0                    # 経験値の通算
var xp_level := 0                # レベル(経験値から決まる)
var over := false                # 終わった(倒れた・あきらめた)
var used_keys := {}              # 出した曲のキー → 何回出したか
var picked_upgrades: Array = []  # 選んだ強化の id(選んだ順)
var keyboard := false            # キーボードで遊んだ


## 始める。seed_n = 0 なら、時刻から決める。
func start(p_start_level: float, p_mods: Array, seed_n := 0) -> void:
	start_level = p_start_level
	mod_ids = clean_mods(p_mods)
	run_seed = seed_n if seed_n != 0 else int(Time.get_ticks_usec() % 2147483647) ^ int(Time.get_unix_time_from_system())
	rng.seed = run_seed
	gauge = 1.0
	levels = {}
	guard = 0
	bet_next = false
	songs = []
	total = 0.0
	picks = 0
	xp = 0.0
	xp_level = 0
	over = false
	used_keys = {}
	picked_upgrades = []


## サバイバルで付けられない MOD を外した配列。
static func clean_mods(ids: Array) -> Array:
	return ids.filter(func(id): return not BANNED_MODS.has(str(id)))


## 点の倍率 f(Lv)。
static func f_of(lv: float) -> float:
	return pow(maxf(lv, 0.0) / F_REF, 2.0)


## 次が何曲目か(1 から)。
func next_no() -> int:
	return songs.size() + 1


## 次の曲の目標の Lv。
func target_level() -> float:
	return start_level + LV_STEP * float(songs.size()) + (BET_LV if bet_next else 0.0)


func level_of(id: String) -> int:
	return int(levels.get(id, 0))


## 選べない強化(MOD「無回復」では、自然回復の強化は効かない)。
func excluded_upgrades() -> Array:
	var out: Array = []
	if not bool(Mods.params(mod_ids).regen):
		out.append("regen")
	if guard > 0:
		out.append("guard")
	return out


## プレイ画面(GameScreen.survival)へ渡す値。
func game_params() -> Dictionary:
	return {
		"gauge": gauge_frac(),
		"drain_mul": max_gauge(),
		"regen": REGEN + REGEN_STEP * level_of("regen"),
		"low_line": LOW_LINE,
		"guard": guard,
		"guard_gauge": GUARD_GAUGE,
		"no": next_no(),
		"total": total,
		"xp": xp,
		"power": level_of("power"), "rate": level_of("rate"), "wide": level_of("wide"), "magnet": level_of("magnet"),
		"xp_mul": BET_XP_MUL if bet_next else 1.0,
		"hp_mul": 1.0 + ENEMY_HP_STEP * float(songs.size()),
	}


## レベル lv から lv + 1 に要る経験値。
static func xp_need(lv: int) -> float:
	return XP_BASE + XP_STEP * float(lv)


## 経験値の通算 total のときのレベル。
static func level_for_xp(total_xp: float) -> int:
	var lv := 0
	var acc := 0.0
	while acc + xp_need(lv) <= total_xp + 0.0001 and lv < 999:
		acc += xp_need(lv)
		lv += 1
	return lv


## 経験値の通算 total のときの {level, into(いまのレベルに入ってからの量), need(次までに要る量)}。
static func xp_progress(total_xp: float) -> Dictionary:
	var lv := 0
	var acc := 0.0
	while acc + xp_need(lv) <= total_xp + 0.0001 and lv < 999:
		acc += xp_need(lv)
		lv += 1
	return {"level": lv, "into": total_xp - acc, "need": xp_need(lv)}


## 体力の上限(初期の体力 = 1)。
func max_gauge() -> float:
	return 1.0 + MAX_GAUGE_STEP * level_of("max_gauge")


## いまの体力の、上限に対する割合(ゲージの表示・プレイ画面へ渡す値)。
func gauge_frac() -> float:
	return clampf(gauge / max_gauge(), 0.0, 1.0)


## 曲の間の回復の量(初期の体力に対する割合)。
func between_heal() -> float:
	return BETWEEN_HEAL + BETWEEN_HEAL_STEP * level_of("between_heal")


## 1 曲が終わった(クリア・倒れた・あきらめた)。st: プレイ画面の結果(GameScreen._stats。title は「アーティスト - 曲名 [難易度]」)。info: 曲の情報 {key, extra_mods}。
## 戻り値: この曲の記録(songs に足したもの)。
func song_done(st: Dictionary, info: Dictionary = {}) -> Dictionary:
	var failed := bool(st.get("failed", false))
	var song_score: float = float(st.get("fail_score", 0.0)) if failed else float(st.get("score", 0.0))
	var lv := float(st.get("level", 0.0))
	var f := f_of(lv)
	var e := {
		"title": str(st.get("title", "")), "version": str(st.get("version", "")), "md5": str(st.get("md5", "")), "key": str(info.get("key", "")),
		"level": lv, "score": song_score, "f": f, "points": song_score * f, "failed": failed, "gave_up": bool(st.get("gave_up", false)),
		"played_s": float(st.get("play_s", 0.0)), "extra_mods": info.get("extra_mods", []), "hp_end": float(st.get("hp_end", 0.0)),
		"xp_got": float(st.get("xp_got", 0.0)), "kills": int(st.get("kills", 0)), "spawned": int(st.get("spawned", 0)),
		"level_from": xp_level, "level_to": xp_level,
	}
	xp += e.xp_got   # 倒れた曲で取った経験値も数える(記録に残すだけ。次の曲はない)
	xp_level = level_for_xp(xp)
	e.level_to = xp_level
	songs.append(e)
	total += e.points
	bet_next = false
	if bool(st.get("keyboard", false)):
		keyboard = true
	guard = int(st.get("guard_left", guard))
	if failed:
		over = true
		return e
	gauge = clampf(float(st.get("hp_end", gauge_frac())) * max_gauge() + between_heal(), 0.0, max_gauge())   # hp_end は、いまの体力に対する割合
	picks += int(e.level_to) - int(e.level_from)   # 上がったレベルの数だけ 3 択
	return e


## 3 択を引く(picks が残っているとき)。戻り値: id の配列。
func roll_choices(n := 3) -> Array:
	return Upgrades.roll(rng, levels, n, excluded_upgrades())


## 強化を 1 つ選ぶ。
func choose(id: String) -> void:
	var u := Upgrades.find(id)
	if u.is_empty() or picks <= 0:
		return
	picks -= 1
	picked_upgrades.append(id)
	match id:
		"guard":
			guard += 1
		"bet":
			bet_next = true
		_:
			levels[id] = level_of(id) + 1


## 届いた Lv(遊んだ曲の Lv の最大)。
func best_level() -> float:
	var m := 0.0
	for e in songs:
		m = maxf(m, float(e.level))
	return m


## クリアした曲の数(倒れた曲は数えない)。
func cleared() -> int:
	var n := 0
	for e in songs:
		if not bool(e.failed):
			n += 1
	return n


## 倒した雑魚の数の通算。
func total_kills() -> int:
	var n := 0
	for e in songs:
		n += int(e.get("kills", 0))
	return n


func played_seconds() -> float:
	var s := 0.0
	for e in songs:
		s += float(e.played_s)
	return s


## 記録に残す形。
func to_record() -> Dictionary:
	return {
		"total": total, "cleared": cleared(), "songs_n": songs.size(), "best_level": best_level(), "time_s": played_seconds(),
		"start_level": start_level, "mods": mod_ids.duplicate(), "keyboard": keyboard, "seed": run_seed,
		"app": str(ProjectSettings.get_setting("application/config/version", "")), "time": int(Time.get_unix_time_from_system()),
		"upgrades": picked_upgrades.duplicate(), "xp_level": xp_level, "kills": total_kills(),
		"songs": songs.map(func(e): return {"title": e.title, "version": e.version, "md5": e.md5, "level": e.level, "score": e.score, "f": e.f, "points": e.points, "failed": e.failed, "gave_up": e.gave_up, "hp_end": e.hp_end, "kills": e.kills, "spawned": e.spawned, "xp_got": e.xp_got}),   # hp_end: 曲を終えたときのゲージ(回復の量を見直すため)
	}
