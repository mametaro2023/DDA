extends RefCounted
## 譜面の読み込み結果の保存(選曲で曲を選んだときの待ちを短くし、全曲の難易度を、あらかじめ用意しておけるようにする)。
## 曲を選ぶと、全難易度の .osu を解析し(スライダーの曲線まで作る)、弾幕を生成していた。どちらも、同じ曲なら毎回同じ結果になるので、
## 1 度作ったら user://chart_cache に保存して、次からは読むだけにする。保存は、大きさの違う 2 つに分ける:
##   統計(.dcs)… 曲ごと・弾幕の作り方(v1 / v2)ごとに 1 ファイル。全難易度の「譜面の情報(Beatmap.to_meta。ノーツは含めない)」と、
##                 弾幕の「統計」(Lv・★・弾速・弾の大きさ・弾数の統計など。発射の一覧は含めない。stub_of)。1 譜面あたり 1 KB 足らず。
##                 難易度の表示・難易度順・長さ順には、これだけで足りる。全曲ぶん、あらかじめ裏で作っておける(SongBrowser.start_prep)。
##   発射の一覧(.dce)… 譜面ごと・弾幕の作り方ごとに 1 ファイル。プレイに使う弾幕の全部(発射・印・エリア)。1 譜面あたり 10〜25 KB(圧縮後)。
##                 選んだ(遊ぶ)譜面だけを残し、合計が MAX_EVENT_BYTES を超えたら、古いものから捨てる。なければ、その場で作る(1 譜面 50〜130 ms)。
## 古くなる条件: 曲のファイルの大きさ・更新時刻が変わった / 弾幕の作り方(stamp)が変わった。変わったら、ファイル名が変わるので、読まない(古いものは prune が捨てる)。
## 統計から作った譜面は「軽い版」(Beatmap.from_meta)で、ノーツ(hit_objects)は使うときまで読まない。
## 別スレッドから呼ばれる(曲の読み込みは別スレッド)。ファイルは、一時ファイルに書いてから置き換えるので、途中のものを読むことはない。

const SongLibrary = preload("res://scripts/song_library.gd")

const DIR := "user://chart_cache"
const FORMAT := 2                  # 保存の形式。変えたら上げる(古いものは読まない)
const MAGIC := 0x44434332          # "DCC2"
const MAX_EVENT_BYTES := 96 * 1024 * 1024    # 発射の一覧の合計の上限。超えたら、古く作ったものから捨てる(prune)
const MAX_STATS_BYTES := 128 * 1024 * 1024   # 統計の合計の上限(1 曲 数 KB なので、何万曲でも収まる)
## 統計(stub)に入れない、大きい項目(発射・印・エリア)
const BIG_KEYS := ["events", "gizmos", "zones", "v2", "spins"]
## 弾幕の生成・譜面の解析に関わるスクリプト(ソースから動かしているとき、これらの更新時刻が変わったら、保存は古いものとして読まない)
const STAMP_SCRIPTS := [
	"res://scripts/game/pattern_gen.gd", "res://scripts/game/pattern_gen_v2.gd", "res://scripts/game/zone_gen_v2.gd",
	"res://scripts/game/zone_area.gd", "res://scripts/game/chart_profile.gd", "res://scripts/game/bullet_field.gd",
	"res://scripts/osu/beatmap.gd", "res://scripts/osu/osu_parser.gd", "res://scripts/osu/star_rating.gd", "res://scripts/osu/slider_path.gd",
]

## 開発用: false にすると、保存も読み込みもしない(毎回解析・生成する)
static var enabled := true
static var _stamp := ""
static var _stamp_mutex := Mutex.new()


## 弾幕の作り方の版。アプリの版 + (ソースから動かしているとき)生成に関わるスクリプトの更新時刻。書き出した版では、更新時刻は 0 なので、アプリの版だけで決まる。
static func stamp() -> String:
	_stamp_mutex.lock()
	if _stamp == "":
		var total := 0
		for f in STAMP_SCRIPTS:
			total += FileAccess.get_modified_time(f)
		_stamp = "%s|%d|%d" % [str(ProjectSettings.get_setting("application/config/version", "")), FORMAT, total]
	var out := _stamp
	_stamp_mutex.unlock()
	return out


## stamp の短い印(SongArt に残す難易度が、いまの弾幕の作り方で測ったものかの確認用)。
static func stamp_tag() -> String:
	return stamp().md5_text().left(8)


static func _name(path: String, v2: bool, extra: String) -> String:
	var key := "%s|%d|%d|%s|%s|%s" % [SongLibrary.norm(path), SongLibrary.file_size(path), FileAccess.get_modified_time(path), "v2" if v2 else "v1", stamp(), extra]
	return key.md5_text()


## 統計の保存のファイル名(曲の場所・大きさ・更新時刻・弾幕の作り方・stamp から決まる)。
static func stats_file(path: String, v2: bool) -> String:
	return "%s/%s.dcs" % [DIR, _name(path, v2, "s")]


## 発射の一覧の保存のファイル名(上の条件 + 譜面の識別子)。
static func events_file(path: String, chart_id: String, v2: bool) -> String:
	return "%s/%s.dce" % [DIR, _name(path, v2, "e|" + chart_id)]


## 弾幕から、統計だけを取り出す(発射の一覧などの大きい項目は除く)。n_events = 発射の数。stub = true の印がつく(まだ発射の一覧を持っていない)。
static func stub_of(gen: Dictionary) -> Dictionary:
	var out := {}
	for k in gen.keys():
		if not BIG_KEYS.has(k):
			out[k] = gen[k]
	out["n_events"] = (gen.events as Array).size() if gen.has("events") else int(gen.get("n_events", 0))
	out["stub"] = true
	return out


## 統計か(発射の一覧を持っていない弾幕か)。
static func is_stub(gen: Dictionary) -> bool:
	return bool(gen.get("stub", false))


# --- 読み書き ---

## ファイルを読んで、中身(Variant)を返す。なければ・壊れていれば null(壊れたファイルは消す)。
static func _read(file: String) -> Variant:
	if not FileAccess.file_exists(file):
		return null
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return null
	var out = null
	if f.get_32() == MAGIC and int(f.get_32()) == FORMAT:
		var raw_size := int(f.get_64())
		var packed := f.get_buffer(f.get_length() - f.get_position())
		if raw_size > 0 and not packed.is_empty():
			var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
			if raw.size() == raw_size:
				out = bytes_to_var(raw)
	f.close()
	if out == null:
		DirAccess.remove_absolute(file)   # 壊れている: 捨てる(次に作り直す)
	return out


static func _write(file: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var raw := var_to_bytes(data)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := "%s.%d.tmp" % [file, Time.get_ticks_usec()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(MAGIC)
	f.store_32(FORMAT)
	f.store_64(raw.size())
	f.store_buffer(packed)
	f.close()
	if DirAccess.rename_absolute(tmp, file) != OK:   # すでにあるファイルを置き換えられなかった(同時に保存した): 一時ファイルは捨てる
		DirAccess.remove_absolute(tmp)


## 統計を読む。{bms: [譜面の情報, ...], stubs: [統計, ...], first_md5: 最初に開く難易度の識別子}(難易度は Lv 順)。なければ空の辞書。
static func load_stats(path: String, v2: bool) -> Dictionary:
	if not enabled:
		return {}
	var data = _read(stats_file(path, v2))
	if data is Dictionary and data.get("bms") is Array and data.get("stubs") is Array and (data.bms as Array).size() == (data.stubs as Array).size() and not (data.bms as Array).is_empty():
		return data
	return {}


## 統計を保存する。entry = {bms, stubs, first_md5}。失敗しても何も起きない(保存は、あれば速くなるだけのもの)。
static func save_stats(path: String, v2: bool, entry: Dictionary) -> void:
	if enabled:
		_write(stats_file(path, v2), entry)


## 統計が保存してあるか(読まずに、ファイルがあるかだけ)。
static func has_stats(path: String, v2: bool) -> bool:
	return enabled and FileAccess.file_exists(stats_file(path, v2))


## 1 譜面の弾幕(発射の一覧を含む全部)を読む。なければ空の辞書。
static func load_events(path: String, chart_id: String, v2: bool) -> Dictionary:
	if not enabled:
		return {}
	var data = _read(events_file(path, chart_id, v2))
	return data if data is Dictionary and data.has("events") else {}


static func save_events(path: String, chart_id: String, v2: bool, gen: Dictionary) -> void:
	if enabled and gen.has("events"):
		_write(events_file(path, chart_id, v2), gen)


## 保存の整理: 前の形式のファイル(.dcc)と古い一時ファイルを捨て、種類ごとの合計が上限を超えていたら、作った時刻の古いものから捨てる。
## 起動のあと 1 回、別スレッドで呼ぶ。
static func prune() -> void:
	if not DirAccess.dir_exists_absolute(DIR):   # まだ 1 度も保存していない
		return
	var now := Time.get_unix_time_from_system()
	var kinds := {"dce": [[], 0, MAX_EVENT_BYTES], "dcs": [[], 0, MAX_STATS_BYTES]}   # 拡張子 → [[時刻, パス, 大きさ], 合計, 上限]
	for name in DirAccess.get_files_at(DIR):
		var p := "%s/%s" % [DIR, name]
		var ext := name.get_extension()
		var t := FileAccess.get_modified_time(p)
		if ext == "tmp":
			if now - float(t) > 86400.0:
				DirAccess.remove_absolute(p)
			continue
		if not kinds.has(ext):   # 前の形式(.dcc)など
			DirAccess.remove_absolute(p)
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		var size := f.get_length() if f != null else 0
		if f != null:
			f.close()
		kinds[ext][0].append([t, p, size])
		kinds[ext][1] += size
	for ext in kinds.keys():
		var files: Array = kinds[ext][0]
		var total: int = kinds[ext][1]
		if total <= int(kinds[ext][2]):
			continue
		files.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		for e in files:
			if total <= int(kinds[ext][2]):
				break
			DirAccess.remove_absolute(str(e[1]))
			total -= int(e[2])
