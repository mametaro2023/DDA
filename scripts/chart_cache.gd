extends RefCounted
## 譜面の読み込み結果の保存(選曲で曲を選んだときの待ちを短くする)。
## 曲を選ぶと、全難易度の .osu を解析し(スライダーの曲線まで作る)、弾幕を生成していた。どちらも、同じ曲なら毎回同じ結果になるので、
## 1 度作ったら user://chart_cache に保存して、次からは読むだけにする(解析も生成もしない)。
##   中身 … {譜面の情報(Beatmap.to_meta。ノーツは含めない)・弾幕の生成結果(MOD 適用前)・最初に開く難易度}。難易度の並び(Lv 順)のまま
##   分け方 … 曲ごと・弾幕の作り方(v1 / v2)ごとに 1 ファイル。圧縮(zstd)して保存する
##   古くなる条件 … 曲のファイルの大きさ・更新時刻が変わった / 弾幕の作り方(stamp)が変わった。変わったら、キーが変わるので、読まない(古いファイルは prune が捨てる)
## 保存した譜面の Beatmap は「軽い版」(Beatmap.from_meta)で、ノーツ(hit_objects)は使うときまで読まない(MOD で弾幕を作り直すときなど)。
## 別スレッドから呼ばれる(曲の読み込みは別スレッド)。ファイルは、一時ファイルに書いてから置き換えるので、途中のものを読むことはない。

const SongLibrary = preload("res://scripts/song_library.gd")

const DIR := "user://chart_cache"
const FORMAT := 1                  # 保存の形式。変えたら上げる(古いものは読まない)
const MAGIC := 0x44434331          # "DCC1"
const MAX_BYTES := 512 * 1024 * 1024   # 保存の合計の上限。超えたら、古く作ったものから捨てる(prune)
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


## 保存のファイル名(曲の場所・大きさ・更新時刻・弾幕の作り方(v1 / v2)・stamp から決まる)。
static func file_of(path: String, v2: bool) -> String:
	var key := "%s|%d|%d|%s|%s" % [SongLibrary.norm(path), SongLibrary.file_size(path), FileAccess.get_modified_time(path), "v2" if v2 else "v1", stamp()]
	return "%s/%s.dcc" % [DIR, key.md5_text()]


## 保存したものを読む。{bms: [譜面の情報, ...], gens: [弾幕, ...], first_md5: 最初に開く難易度の識別子}。なければ(読めなければ)空の辞書。
static func load_entry(path: String, v2: bool) -> Dictionary:
	if not enabled:
		return {}
	var file := file_of(path, v2)
	if not FileAccess.file_exists(file):
		return {}
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return {}
	var out := {}
	if f.get_32() == MAGIC and int(f.get_32()) == FORMAT:
		var raw_size := int(f.get_64())
		var packed := f.get_buffer(f.get_length() - f.get_position())
		if raw_size > 0 and not packed.is_empty():
			var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
			var data = bytes_to_var(raw) if raw.size() == raw_size else null
			if data is Dictionary and data.get("bms") is Array and data.get("gens") is Array and (data.bms as Array).size() == (data.gens as Array).size() and not (data.bms as Array).is_empty():
				out = data
	f.close()
	if out.is_empty():
		DirAccess.remove_absolute(file)   # 壊れている: 捨てる(次に作り直す)
	return out


## 保存する。entry = {bms, gens, first_md5}。失敗しても何も起きない(保存は、あれば速くなるだけのもの)。
static func save_entry(path: String, v2: bool, entry: Dictionary) -> void:
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := file_of(path, v2)
	var raw := var_to_bytes(entry)
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


## 保存の合計が MAX_BYTES を超えていたら、作った時刻の古いものから捨てる。使っていない一時ファイル(1 日より古い)も捨てる。起動のあと 1 回、別スレッドで呼ぶ。
static func prune() -> void:
	var files: Array = []
	var total := 0
	var now := Time.get_unix_time_from_system()
	for name in DirAccess.get_files_at(DIR):
		var p := "%s/%s" % [DIR, name]
		var t := FileAccess.get_modified_time(p)
		if name.ends_with(".tmp"):
			if now - float(t) > 86400.0:
				DirAccess.remove_absolute(p)
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		var size := f.get_length() if f != null else 0
		if f != null:
			f.close()
		files.append([t, p, size])
		total += size
	if total <= MAX_BYTES:
		return
	files.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for e in files:
		if total <= MAX_BYTES:
			break
		DirAccess.remove_absolute(str(e[1]))
		total -= int(e[2])
