extends RefCounted
## 曲(.osz)の置き場所の探索。選曲画面とタイトル画面が共通で使う。
## 探す場所: プロジェクト直下(開発時) / songs / 実行ファイルの隣 / 実行ファイルの隣の songs / ユーザーデータ内の songs
## (配布版は、実行ファイルの隣の songs フォルダに .osz を入れる)。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const OsuParser = preload("res://scripts/osu/osu_parser.gd")


## パスを比べるための形(区切りを / にそろえ、余分な / ・ . を除き、大文字小文字を区別しない)。
## 同じ場所が、実行ファイルの位置と res:// から別の書き方で得られても(ドライブ文字の大小など)、同じと分かるようにする。
static func norm(p: String) -> String:
	return p.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


static func search_dirs() -> Array:
	var dirs: Array = []
	var seen := {}
	var proj := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path().get_base_dir()
	for d in [proj, proj.path_join("songs"), exe, exe.path_join("songs"),
			ProjectSettings.globalize_path("user://songs")]:
		d = str(d).replace("\\", "/")
		var key := norm(d)
		if not seen.has(key):
			seen[key] = true
			dirs.append(d)
	return dirs


## 見つかった .osz のパス。同じファイルは 1 つにする(場所の書き方が違うものも、同じ名前・同じ大きさのものも)。
static func find_all() -> Array:
	var out: Array = []
	var seen := {}
	for d in search_dirs():
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".osz"):
				var p: String = str(d).path_join(f).replace("\\", "/")
				if _is_new(seen, p):
					out.append(p)
	return out


## 追加してよいファイルか(すでに数えたものと同じなら false)。同じと見なすのは、パスが同じ、または名前と大きさが同じ。
static func _is_new(seen: Dictionary, p: String) -> bool:
	var k1 := norm(p)
	var f := FileAccess.open(p, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	if f != null:
		f.close()
	var k2 := "%s|%d" % [p.get_file().to_lower(), size]
	if seen.has(k1) or (size >= 0 and seen.has(k2)):
		return false
	seen[k1] = true
	seen[k2] = true
	return true


## いま置き場にある .osz を、軽く数える(フォルダの見張り用。ファイルは開かない)。"名前|大きさ" → パス。find_all と同じく、同じ名前・大きさは 1 つ。
static func snapshot() -> Dictionary:
	var out := {}
	for d in search_dirs():
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".osz"):
				var p: String = str(d).path_join(f).replace("\\", "/")
				var k := "%s|%d" % [f.to_lower(), file_size(p)]
				if not out.has(k):
					out[k] = p
	return out


static func file_size(p: String) -> int:
	var fh := FileAccess.open(p, FileAccess.READ)
	if fh == null:
		return -1
	var n := fh.get_length()
	fh.close()
	return n


## ユーザーデータ内の songs フォルダ(なければ作る)。ここにも .osz を置ける。
static func ensure_user_dir() -> String:
	var d := ProjectSettings.globalize_path("user://songs")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## 譜面の識別子(Beatmap.md5 = OsuParser.play_key)から、その譜面を含む .osz を探す(マルチプレイで、部屋の曲を持っているかの確認)。
## 見つかったら {path, file}、なければ空の辞書。.osz の中の .osu の文字を見て識別子を数えるだけ(譜面の解析はしない)ので軽い。
static func find_by_md5(md5: String) -> Dictionary:
	for path in find_all():
		var ids: Dictionary = info(path).ids
		if ids.has(md5):
			return {"path": path, "file": ids[md5]}
	return {}


# --- 曲の索引(.osz を全部開かずに、一覧に出す情報を得る) ---

const INDEX_PATH := "user://song_index.json"
const INDEX_VERSION := 1

## 場所+大きさ+更新時刻 → 情報。ファイルに保存して、次の起動でも .osz を開き直さない(曲が多くても選曲画面がすぐ開く)。
static var _index := {}
static var _index_loaded := false
static var _index_dirty := false


## その .osz の要約: {ok, error, title, artist, md5(先頭の難易度の識別子), ids(識別子 → .osu のファイル名)}。
## ok は、osu!standard の譜面が入っているか。中身を解析せず文字を見るだけなので軽く、結果は保存される。
static func info(path: String) -> Dictionary:
	_load_index()
	var size := -1
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh != null:
		size = fh.get_length()
		fh.close()
	var ck := "%s|%d|%d" % [norm(path), size, FileAccess.get_modified_time(path)]
	if _index.has(ck):
		return _index[ck]
	var out := {"ok": false, "error": "", "title": "", "artist": "", "md5": "", "ids": {}}
	var z := ZIPReader.new()
	var err := z.open(path)
	if err != OK:
		out.error = "osz を開けません: %s (%s)" % [path.get_file(), error_string(err)]
	else:
		var names: Array = []
		for f in z.get_files():
			if f.to_lower().ends_with(".osu"):
				names.append(f)
		names.sort()
		var best := ""
		for f in names:
			var text := z.read_file(f).get_string_from_utf8()
			var key := OsuParser.play_key(text)
			out.ids[key] = f
			var q := OsuParser.quick_info(text)
			if q.mode == 0 and q.objects > 0:
				if not out.ok:
					out.title = q.title
					out.artist = q.artist
				out.ok = true
				if best == "" or key < best:
					best = key
		z.close()
		out.md5 = best
		if not out.ok:
			out.error = "osu!standard の譜面が見つかりません"
	_index[ck] = out
	_index_dirty = true
	return out


static func _load_index() -> void:
	if _index_loaded:
		return
	_index_loaded = true
	var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary and int(data.get("v", 0)) == INDEX_VERSION and data.get("items") is Dictionary:
		_index = data.items


## 索引を保存する(変わったときだけ)。使われなくなった曲の分は捨てる(keep: 今ある曲のパスの一覧。空なら全部残す)。
static func save_index(keep: Array = []) -> void:
	if not _index_loaded:
		return
	if not keep.is_empty():
		var alive := {}
		for p in keep:
			var s := -1
			var fh := FileAccess.open(str(p), FileAccess.READ)
			if fh != null:
				s = fh.get_length()
				fh.close()
			alive["%s|%d|%d" % [norm(str(p)), s, FileAccess.get_modified_time(str(p))]] = true
		for k in _index.keys():
			if not alive.has(k):
				_index.erase(k)
				_index_dirty = true
	if not _index_dirty:
		return
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": INDEX_VERSION, "items": _index}))
	f.close()
	_index_dirty = false
