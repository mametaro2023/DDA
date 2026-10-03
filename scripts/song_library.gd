extends RefCounted
## 曲(.osz)の置き場所の探索。選曲画面とタイトル画面が共通で使う。
## 設定で有効にすると、osu! の Songs フォルダ(osu!stable が .osz を展開して並べたもの)の中の曲も、コピーせずにそのまま一覧に加える
## (曲のパスは、その曲のフォルダ。OszLoader が .osz と同じように開く)。
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


## 見つかった曲のパス(.osz と、osu! の Songs の中の曲のフォルダ)。.osz は find_osz、osu! の曲は索引ができたぶんだけ(待たない)。
static func find_all() -> Array:
	var out := find_osz()
	var seen := {}
	for p in out:
		seen[norm(str(p))] = true
	for d in osu_song_dirs():
		if not seen.has(norm(str(d))):
			out.append(d)
	return out


## 見つかった .osz のパス。同じファイルは 1 つにする(場所の書き方が違うものも、同じ名前・同じ大きさのものも)。
static func find_osz() -> Array:
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
	if OszLoader.is_folder(p):   # フォルダ(osu! の Songs の中の曲)は大きさを持たない
		return -1
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
	for path in find_osz():
		var ids: Dictionary = info(path).ids
		if ids.has(md5):
			return {"path": path, "file": ids[md5]}
	var found := {}
	_index_mutex.lock()   # osu! の曲は、できている索引だけを見る(2 秒ごとに呼ばれるので、ファイルには触らない)
	for e in _warm_ready:
		if e.info.ids.has(md5):
			found = {"path": e.path, "file": e.info.ids[md5]}
			break
	_index_mutex.unlock()
	return found


# --- 曲の索引(.osz を全部開かずに、一覧に出す情報を得る) ---

const INDEX_PATH := "user://song_index.json"
const INDEX_VERSION := 2   # 2: 読めない理由の文言を変えた(入っていた譜面のモードを添える)

## 場所+大きさ+更新時刻 → 情報。ファイルに保存して、次の起動でも .osz を開き直さない(曲が多くても選曲画面がすぐ開く)。
static var _index := {}
static var _index_loaded := false
static var _index_dirty := false
static var _index_mutex := Mutex.new()   # 索引は、主スレッドと裏の作業(start_osu_warmup)の両方から使う
static var _save_mutex := Mutex.new()    # 索引ファイルへの書き出しは 1 つずつ


## 索引のキー: 場所+大きさ+更新時刻(ファイルが差し替わったら別物)。
static func index_key(path: String) -> String:
	return "%s|%d|%d" % [norm(path), file_size(path), FileAccess.get_modified_time(path)]


## その .osz(または osu! の Songs の中の曲のフォルダ)の要約: {ok, error, title, artist, md5(先頭の難易度の識別子), ids(識別子 → .osu のファイル名)}。
## ok は、osu!standard の譜面が入っているか。中身を解析せず文字を見るだけなので軽く、結果は保存される。
static func info(path: String) -> Dictionary:
	var is_dir := OszLoader.is_folder(path)
	var ck := index_key(path)
	_index_mutex.lock()
	_load_index()
	var hit = _index.get(ck)
	_index_mutex.unlock()
	if hit != null:
		return hit
	var out := {"ok": false, "error": "", "title": "", "artist": "", "md5": "", "ids": {}}
	var z := ZIPReader.new()
	var err := OK if is_dir else z.open(path)
	if err != OK:
		out.error = OszLoader.zip_error_message(err)
	else:
		var names: Array = []
		for f in (DirAccess.get_files_at(path) if is_dir else z.get_files()):
			if f.to_lower().ends_with(".osu"):
				names.append(f)
		names.sort()
		var best := ""
		var modes: Array = []
		for f in names:
			var text := (FileAccess.get_file_as_bytes(path.path_join(f)) if is_dir else z.read_file(f)).get_string_from_utf8()
			var key := OsuParser.play_key(text)
			out.ids[key] = f
			var q := OsuParser.quick_info(text)
			modes.append(int(q.mode))
			if q.mode == 0 and q.objects > 0:
				if not out.ok:
					out.title = q.title
					out.artist = q.artist
				out.ok = true
				if best == "" or key < best:
					best = key
		if not is_dir:
			z.close()
		out.md5 = best
		if not out.ok:
			out.error = OszLoader.no_standard_message(modes)
	_index_mutex.lock()
	_index[ck] = out
	_index_dirty = true
	_index_mutex.unlock()
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
	var alive := {}
	for p in keep:
		alive[index_key(str(p))] = true
	_index_mutex.lock()
	if not _index_loaded:
		_index_mutex.unlock()
		return
	if not keep.is_empty():
		var osu_prefix := (norm(osu_dir) + "/") if osu_dir != "" else ""   # osu! の曲の分は、裏の作業が整理するので、ここでは捨てない
		for k in _index.keys():
			if not alive.has(k) and not (osu_prefix != "" and str(k).begins_with(osu_prefix)):
				_index.erase(k)
				_index_dirty = true
	if not _index_dirty:
		_index_mutex.unlock()
		return
	var snapshot := _index.duplicate()   # 書き出し(曲が多いと重い)は、索引を使えなくしないよう、ロックの外で行う
	_index_dirty = false
	_index_mutex.unlock()
	_save_mutex.lock()
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"v": INDEX_VERSION, "items": snapshot}))
		f.close()
	_save_mutex.unlock()
	if f == null:
		_index_mutex.lock()
		_index_dirty = true
		_index_mutex.unlock()


# --- osu! の Songs フォルダ ---
# 何千曲もあっても画面が止まらないよう、重い処理(フォルダの一覧・曲ごとの索引づくり)は、すべて裏のスレッドで行う。
# 主スレッドは、できたぶんを読むだけ(osu_song_dirs / take_ready / find_by_md5)。画面は、できた曲から順に足していく。

## 使う osu! の Songs フォルダ(空なら使わない)。設定から apply_osu_settings で決める。
static var osu_dir := ""
static var osu_gen := 0                 # apply_osu_settings のたびに増える(できた曲の一覧が作り直されるので、画面が足し直す印)
static var _warm_thread: Thread
static var _warm_stop := false
static var _warm_ready: Array = []      # 索引ができた曲(osu!standard の譜面があるもの)。{path, info} が、できた順に増える。_index_mutex で守る
static var _warm_known := {}            # 索引を見終えた曲のパス(読めない曲も含む)。_index_mutex で守る
static var _warm_total := 0             # Songs の中のフォルダの数(進み具合の表示用)


## 設定(Settings.load_all の辞書)から、osu! の Songs フォルダを決める。osu_songs が切れていれば使わない。
## osu_songs_dir が空なら、osu! の標準の場所から探す。場所が変わるので、裏の作業は止めて、できた曲の一覧は捨てる(start_osu_warmup で作り直す)。
static func apply_osu_settings(st: Dictionary) -> void:
	stop_warmup()
	osu_gen += 1
	osu_dir = ""
	if bool(st.get("osu_songs", false)):
		var d := str(st.get("osu_songs_dir", "")).replace("\\", "/")
		osu_dir = d if d != "" else detect_osu_songs()
	_index_mutex.lock()
	_warm_ready = []
	_warm_known = {}
	_warm_total = 0
	_index_mutex.unlock()


## osu!stable の Songs フォルダを探す。%LOCALAPPDATA%\osu! の中の設定ファイル(osu!.<ユーザー名>.cfg)の BeatmapDirectory を優先し、
## なければ、その中の Songs。見つからなければ空。
static func detect_osu_songs() -> String:
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if local == "":
		return ""
	var root := local.path_join("osu!")
	if not DirAccess.dir_exists_absolute(root):
		return ""
	for f in DirAccess.get_files_at(root):
		if f.to_lower().begins_with("osu!.") and f.to_lower().ends_with(".cfg"):
			var dir := beatmap_directory(FileAccess.get_file_as_string(root.path_join(f)), root)
			if dir != "" and DirAccess.dir_exists_absolute(dir):
				return dir
	var songs := root.path_join("Songs")   # Windows は大文字小文字を区別しない(実際のフォルダの綴りが songs でも開ける)
	return songs if DirAccess.dir_exists_absolute(songs) else ""


## osu!.<ユーザー名>.cfg の中の「BeatmapDirectory = …」。相対パスは osu! のフォルダ(root)からの位置。なければ空。
static func beatmap_directory(cfg_text: String, root: String) -> String:
	for line in cfg_text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("BeatmapDirectory"):
			var v := l.substr(l.find("=") + 1).strip_edges().replace("\\", "/") if l.contains("=") else ""
			if v == "":
				return ""
			return v if (v.contains(":") or v.begins_with("/")) else root.path_join(v).simplify_path()
	return ""


## 索引ができた osu! の曲のフォルダ(osu!standard の譜面があるもの)。裏の作業の途中なら、できたぶんだけ。待たずにすぐ返る。
static func osu_song_dirs() -> Array:
	var out: Array = []
	_index_mutex.lock()
	for e in _warm_ready:
		out.append(e.path)
	_index_mutex.unlock()
	return out


## 索引ができた曲の数。
static func ready_count() -> int:
	_index_mutex.lock()
	var n := _warm_ready.size()
	_index_mutex.unlock()
	return n


## 索引ができた曲を、from 番目から最大 max 個({path, info} の配列)。選曲画面が、画面を止めずに少しずつ足すために使う。
static func take_ready(from: int, max: int) -> Array:
	_index_mutex.lock()
	var out := _warm_ready.slice(from, from + max)
	_index_mutex.unlock()
	return out


## 裏の作業の進み具合: {running, done(見終えた数), total(Songs の中のフォルダの数)}。
static func warm_progress() -> Dictionary:
	_index_mutex.lock()
	var out := {"running": _warm_thread != null and _warm_thread.is_alive(), "done": _warm_known.size(), "total": _warm_total}
	_index_mutex.unlock()
	return out


## 裏の作業を始める(動いていれば何もしない)。Songs の中のフォルダを調べて、索引のない曲の索引を作り、できた曲から _warm_ready に足す。
## 見終えた曲は飛ばすので、あとから呼び直すと、増えた曲だけ調べる。
static func start_osu_warmup() -> void:
	if osu_dir == "" or (_warm_thread != null and _warm_thread.is_alive()):
		return
	stop_warmup()   # 終わっているスレッドを片づける
	_warm_stop = false
	_warm_thread = Thread.new()
	_warm_thread.start(_warm.bind(osu_dir), Thread.PRIORITY_LOW)


static func _warm(dir: String) -> void:
	var subs := DirAccess.get_directories_at(dir)
	_index_mutex.lock()
	_warm_total = subs.size()
	_index_mutex.unlock()
	var alive := {}   # この回に見た曲の索引のキー(終わりに、なくなった曲の分を索引から捨てる)
	var n := 0
	for sub in subs:
		if _warm_stop:
			return
		var p := dir.path_join(sub).replace("\\", "/")
		alive[index_key(p)] = true
		_index_mutex.lock()
		var known := _warm_known.has(p)
		_index_mutex.unlock()
		if known:
			continue
		var inf := info(p)
		_index_mutex.lock()
		_warm_known[p] = true
		if inf.ok:
			_warm_ready.append({"path": p, "info": inf})
		_index_mutex.unlock()
		n += 1
		if n % 500 == 0:   # 途中で閉じられても、ここまでは残す
			save_index()
	_index_mutex.lock()
	var prefix := norm(dir) + "/"
	for k in _index.keys():
		if str(k).begins_with(prefix) and not alive.has(k):
			_index.erase(k)
			_index_dirty = true
	_index_mutex.unlock()
	save_index()


## 裏の作業を止めて待つ(終了時・設定が変わるとき)。動いていなければ何もしない。1 曲ぶんで止まるので、すぐ終わる。
static func stop_warmup() -> void:
	if _warm_thread == null:
		return
	_warm_stop = true
	_warm_thread.wait_to_finish()
	_warm_thread = null
