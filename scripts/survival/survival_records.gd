extends RefCounted
## サバイバルの記録(この PC の中だけ。送信しない)。合計点の高い順に、上位 KEEP 件を残す。保存先は user://survival_records.json。
## 1 件は SurvivalRun.to_record() の形(合計点・クリアした曲数・届いた Lv・時間・開始 Lv・MOD・入力の種類・乱数の種・曲ごとの内訳・選んだ強化)。
## 1 曲ずつの記録(records.gd)とは別(条件が違うので混ぜない)。

const PATH := "user://survival_records.json"
const VERSION := 1
const KEEP := 20

static var path := PATH
## false のあいだは残さない(開発用の確認で、使う人の記録を汚さないため)
static var enabled := true
static var _list: Array = []
static var _loaded := false


static func reload() -> void:
	_list = []
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
	if parsed is Dictionary and int(parsed.get("v", 0)) == VERSION and parsed.get("runs") is Array:
		_list = parsed.runs


static func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": VERSION, "runs": _list}))
	f.close()


## 1 件足す。戻り値: これまでの最高を超えたか(1 曲も遊んでいない記録は残さない)。
static func add(rec: Dictionary) -> bool:
	_load()
	if int(rec.get("songs_n", 0)) <= 0:
		return false
	var prev := best()
	var is_best := prev.is_empty() or float(rec.total) > float(prev.total)
	if not enabled:
		return is_best
	_list.append(rec)
	_list.sort_custom(func(a, b): return float(a.total) > float(b.total))
	if _list.size() > KEEP:
		_list.resize(KEEP)
	_save()
	return is_best


## 合計点の高い順の上位 n 件。
static func top(n := KEEP) -> Array:
	_load()
	return _list.slice(0, n)


## いちばん高い記録(なければ空の辞書)。
static func best() -> Dictionary:
	_load()
	return _list[0] if not _list.is_empty() else {}
