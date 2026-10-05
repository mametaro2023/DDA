extends RefCounted
## プレイ記録(この PC の中だけ。送信しない)。譜面の難易度(識別子 = Beatmap.md5)ごとに、クリアしたプレイの上位 KEEP 件をスコア順に残す。
## 各記録は、そのプレイのリプレイ(scripts/replay.gd)のファイル名(replay)を持つ。記録から外れたら、そのリプレイも消す。
## 保存先は user://records.json。選曲画面(lazer 風)が、選んだ難易度の記録と、曲ごとの最高ランクを出すのに使う。
## 残すのはひとりで遊んでクリアしたものだけ(ゲームオーバー・マルチプレイは残さない)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const Replay = preload("res://scripts/replay.gd")

const PATH := "user://records.json"
const VERSION := 1
const KEEP := 10

## 保存先(確認用に差し替えられる)
static var path := PATH
## false のあいだは、記録を残さない(開発用の確認・スクリーンショットで、使う人の記録を汚さないため)
static var enabled := true
static var _data := {}        # md5 → [{score, rank, hits, graze, damage, mods, level, t}, ...](スコアの高い順)
static var _loaded := false


## 読み込み直す(確認用。保存先を変えたときなど)。
static func reload() -> void:
	_data = {}
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and int(parsed.get("v", 0)) == VERSION and parsed.get("maps") is Dictionary:
		_data = parsed.maps


static func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": VERSION, "maps": _data}))
	f.close()


## プレイの結果(stats)から、残す 1 件を作る。クリアしていない・ひとり用でない(マルチ)・識別子がないときは、空の辞書。
static func entry_from_stats(stats: Dictionary) -> Dictionary:
	if bool(stats.get("failed", true)) or stats.has("mp") or str(stats.get("md5", "")) == "":
		return {}
	var score_base: float = float(stats.get("score_base", 1000000.0))
	var e := {
		"score": int(round(float(stats.score))),
		"rank": GameSim.rank_of(false, int(stats.hits), float(stats.score), score_base),
		"hits": int(stats.hits), "graze": int(stats.graze), "damage": float(stats.get("damage", 0.0)),
		"mods": (stats.get("mod_ids", []) as Array).duplicate(), "level": float(stats.get("level", 0.0)),
		"t": int(Time.get_unix_time_from_system()),
		"replay": str(stats.get("replay", "")),
	}
	if bool(stats.get("keyboard", false)):   # キーボードで遊んだ記録(マウスのときは持たない)
		e.kb = true
	return e


## 1 件を足す。上位 KEEP 件に入らなければ捨てる。戻り値: これまでの最高を超えた(初めての記録も含む)なら true。
static func add(md5: String, entry: Dictionary) -> bool:
	if md5 == "" or entry.is_empty():
		return false
	_load()
	var list: Array = _data.get(md5, [])
	var prev_best := int(list[0].score) if not list.is_empty() else -1
	list.append(entry)
	list.sort_custom(func(a, b): return int(a.score) > int(b.score))   # 同点は、先に出たほうが上(安定ソート)
	if list.size() > KEEP:
		for dropped in list.slice(KEEP):   # 記録から外れたプレイのリプレイは、もう要らない(いま足したプレイは、結果画面から見られるよう残す。直近の件数の整理で消える)
			if str(dropped.get("replay", "")) != str(entry.get("replay", "")):
				Replay.remove(str(dropped.get("replay", "")))
		list.resize(KEEP)
	_data[md5] = list
	_save()
	return int(entry.score) > prev_best


## stats(GameScreen._stats の形)が、残してよいクリアなら記録する。新記録なら true。
static func record_stats(stats: Dictionary) -> bool:
	if not enabled:
		return false
	return add(str(stats.get("md5", "")), entry_from_stats(stats))


## 記録に載っているリプレイのファイル名(整理で消さない)。
static func replay_names() -> Array:
	_load()
	var out: Array = []
	for md5 in _data:
		for e in _data[md5]:
			var n := str(e.get("replay", ""))
			if n != "":
				out.append(n)
	return out


## その難易度の上位 n 件(スコアの高い順)。
static func top(md5: String, n := 5) -> Array:
	_load()
	var list: Array = _data.get(md5, [])
	return list.slice(0, mini(n, list.size()))


## その難易度の最高の記録(なければ空の辞書)。
static func best(md5: String) -> Dictionary:
	_load()
	var list: Array = _data.get(md5, [])
	return list[0] if not list.is_empty() else {}


## 曲全体(ids = その曲の難易度の識別子の一覧)での、最高ランクの記録(最高スコアの 1 件。なければ空の辞書)。
static func best_of_song(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		var b := best(str(id))
		if not b.is_empty() and (out.is_empty() or int(b.score) > int(out.score)):
			out = b
	return out
