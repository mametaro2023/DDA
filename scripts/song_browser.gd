extends RefCounted
## 選曲の中身(UI を持たない)。曲の一覧・選んでいる曲と難易度・曲の読み込み(別スレッド)・弾幕の生成と難易度の測定・プレイへ渡すものの用意。
## 選曲画面(classic も、別の UI も)は、これを 1 つ持ち、signal を購読して表示するだけにする(docs/ui_plan.md の §2.4)。
##
## 曲を選ぶ(select_song)と、重い読み込み(.osz を開く・弾幕の生成・画像/音声の読み込み)は別スレッドで行い、
## 終わると song_loaded が出る(そのあいだに別の曲を選び直したら、前の結果は捨てる)。

## 曲を選んだ(読み込みの開始。old は選ぶ前の番号、-1 なら未選択)。画面は、すぐ表示を切り替える(読み込み中の見た目にする)
signal song_changing(old: int, new: int)
## 読み込みが終わった。状態(loader・gens・ratings・diff_sel など)は更新済み。res の image・audio・audio_from は、画面が背景・試聴に使う
signal song_loaded(res: Dictionary)
## 読み込みに失敗した(選んでいた番号は、前の曲に戻してある。bad は失敗した曲の番号)
signal song_load_failed(error: String, bad: int)
## MOD で弾幕の作り方(v1 / v2)が変わったので、同じ曲を読み直し始めた(終わると song_loaded。res.reload = true)。画面は読み込み中の見た目にする
signal song_reloading
## 選んでいる曲の、k 番の譜面の弾幕(発射の一覧を含む全部)が、そろった(統計だけだった弾幕が、プレイに使える形になった)。画面は、プレイを押せるようにする
signal gen_ready(k: int)

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const Records = preload("res://scripts/records.gd")
const SongArt = preload("res://scripts/song_art.gd")
const ChartCache = preload("res://scripts/chart_cache.gd")

## 設定の辞書(画面と同じものを共有する。mods・last_song・last_diff を読み書きする)
var settings: Dictionary = {}

var songs: Array = []           # [{path, title, artist, key, key2, md5, ids(難易度の識別子の一覧), mtime(ファイルの更新時刻), folder(osu! の Songs の曲)}]
var loader                      # 選択中の OszLoader
var gens: Array = []            # 難易度リストと同じ並びの、MOD 適用前の弾幕(生成結果)
var gens_v2 := false            # gens が弾幕 v2(MOD)で作ったものか
var ratings: Array = []         # 同じ並びの Danmaku 難易度(MOD 適用後)
var song_sel := -1
var diff_sel := -1
var last_error := ""
var job := 0                    # 曲の読み込み(別スレッド)の通し番号。最新のものだけ使う
var job_pending := false        # 読み込み中か
var prev_sel := -1              # 読み込み中の曲を選ぶ前に選んでいた曲(読めなかったときに戻す)
var full_audio: AudioStream     # 選んでいる曲の、全体の音声(試聴用は途中から切り出したもの。プレイ画面へ渡す)
var full_audio_file := ""

var _song_keys := {}            # key → songs の番号(重複の確認が、曲が何千あっても速いように)
var _song_key2s := {}           # key2(名前|大きさ) → 番号
var _song_md5s := {}            # 譜面の識別子 → 番号
var _osu_cursor := 0            # osu! の Songs の曲(SongLibrary.take_ready)を、どこまで一覧に足したか
var _osu_gen := 0               # 足している osu! の曲の一覧の世代(SongLibrary.osu_gen)。変わったら、足し直す
var _want_key := ""             # 前回選んでいた曲(まだ一覧に出ていなければ、出たときに選ぶ)
var auto_sel_idx := -1          # 自動で選んだ曲の番号(その曲のまま、ユーザーが触っていないときだけ、前回の曲に選び直す)
var _restore_key := ""          # 一覧を作り直す間、選んでいた曲(足し直されたときに、選択を戻す)
var _reload_keep := ""          # 弾幕の作り方が変わって読み直すとき: 選んでいた難易度の version(空なら、ふつうの選曲)
var _closed := false
var _full_pending := {}         # 発射の一覧を用意している譜面の番号(ensure_full)
static var loading_now := false   # 曲を読み込み中か(裏の準備は、この間は待つ)
static var _pruned := false     # 保存した譜面の整理(ChartCache.prune)を、もうしたか(起動のあと 1 回)


## 画面を離れる(以後に届く読み込みの結果は捨てる)。
func close() -> void:
	_closed = true


# --- 曲の検出 ---
## .osz は開いたときにすべて足す。osu! の Songs の曲は、裏で索引ができた曲から、pump で少しずつ足す(何千曲あっても画面が止まらない)。

func clear_songs() -> void:
	songs.clear()
	_song_keys.clear()
	_song_key2s.clear()
	_song_md5s.clear()


## 一覧を作り直す(画面を開いたとき)。読めなかった曲があれば、その知らせの文を返す(なければ空)。
func scan() -> String:
	clear_songs()
	_osu_cursor = 0
	_want_key = SongLibrary.norm(str(settings.get("last_song", "")))
	_osu_gen = SongLibrary.osu_gen
	SongLibrary.start_osu_warmup()
	var paths := SongLibrary.find_osz()   # 同じファイルは 1 つにまとめて返る
	var failed := _add_songs(paths)
	SongLibrary.save_index(paths)
	return _failed_message(failed)


func _add_songs(paths: Array) -> Array:
	var failed: Array = []
	for p in paths:
		if add_song(p) < 0:
			failed.append(str(p).get_file())
	return failed


static func _failed_message(failed: Array) -> String:
	if failed.is_empty():
		return ""
	return "読み込めなかった曲: " + ", ".join(failed.slice(0, 3)) + (" ほか %d 件" % (failed.size() - 3) if failed.size() > 3 else "")   # 読めなかった曲は、黙って飛ばさず、名前を出す


## songs フォルダの中身が変わったとき・osu! の Songs の設定が変わったとき: 一覧を更新する。選んでいる曲はそのまま(読み込み直さない)。
## すでに一覧にある曲は作り直さず、増えた .osz を足し、なくなった曲を外す。osu! の Songs の設定が変わったときだけ、osu! の曲を足し直す。
## 返す辞書: {msg(知らせの文), rebuild(曲が外れた: 画面は行を作り直す。false なら、増えた分を足すだけでよい)}
func rescan() -> Dictionary:
	var cur := ""
	if song_sel >= 0 and song_sel < songs.size():
		cur = str(songs[song_sel].key)
	var osu_reset := SongLibrary.osu_gen != _osu_gen
	_osu_gen = SongLibrary.osu_gen
	SongLibrary.start_osu_warmup()
	var keep: Array = []
	for sg in songs:
		if sg.folder:
			if not osu_reset:
				keep.append(sg)
		elif FileAccess.file_exists(sg.path):
			keep.append(sg)
	var removed := keep.size() != songs.size()
	if removed:
		clear_songs()
		for sg in keep:
			_register(sg)
	if osu_reset:
		_osu_cursor = 0
		if cur != "" and not _song_keys.has(cur):
			_restore_key = cur   # 足し直されたときに、選択を戻す
	var paths := SongLibrary.find_osz()
	var failed := _add_songs(paths)
	SongLibrary.save_index(paths)
	song_sel = int(_song_keys.get(cur, -1))
	return {"msg": _failed_message(failed), "rebuild": removed}


## osu! の Songs の、索引ができた曲を、budget_us マイクロ秒まで一覧に足す(毎フレーム呼ぶ)。
## 返す辞書: {added(足した), select(この番号の曲を選ぶ。-1 = なし), restored(一覧を作り直す前に選んでいた曲を、song_sel に戻した)}
func pump(budget_us := 4000) -> Dictionary:
	var out := {"added": false, "select": -1, "restored": false, "prepped": false}
	_prep_mutex.lock()
	var got: Array = _prep_out
	_prep_out = []
	_prep_mutex.unlock()
	for r in got:   # 裏の準備ができた曲の Lv を、SongArt に残す(難易度順・難易度の表示に使う)
		SongArt.set_levels(str(r.key), bool(r.v2), r.levels)
		out.prepped = true
	if SongLibrary.osu_dir == "" or _osu_gen != SongLibrary.osu_gen:
		return out
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < budget_us:
		var batch := SongLibrary.take_ready(_osu_cursor, 10)
		if batch.is_empty():
			break
		_osu_cursor += batch.size()
		for e in batch:
			var n := songs.size()
			if _append(str(e.path), e.info, true) == n:
				out.added = true
	if not out.added:
		return out
	# 選び直すもの: 一覧を作り直す前に選んでいた曲(選択を戻す)/ 前回の曲(自動で選んだままなら、そこへ移す)/ 何も選ばれていなければ最初の曲
	if _restore_key != "" and _song_keys.has(_restore_key):
		song_sel = int(_song_keys[_restore_key])
		_restore_key = ""
		out.restored = true
	elif _want_key != "" and _song_keys.has(_want_key) and auto_sel_idx >= 0 and song_sel == auto_sel_idx and song_sel != int(_song_keys[_want_key]):
		auto_sel_idx = int(_song_keys[_want_key])   # ユーザーがまだ触っていないので、前回の曲へ
		out.select = auto_sel_idx
	elif song_sel < 0 and loader == null and not job_pending and _restore_key == "" and not songs.is_empty():
		auto_sel_idx = int(_song_keys.get(_want_key, 0))
		out.select = auto_sel_idx
	return out


## 一覧を作り直す前に選んでいた曲を、足し直されるのを待っているか(その間は、ほかの曲を自動で選ばない)。
func restoring() -> bool:
	return _restore_key != ""


## osu! の曲を調べている途中か(「曲がありません」を出さない・進み具合を出すため)。{running, done, total}
static func osu_progress() -> Dictionary:
	if SongLibrary.osu_dir == "":
		return {"running": false, "done": 0, "total": 0}
	return SongLibrary.warm_progress()


## 追加して一覧の番号を返す(重複は既存の番号、読めなければ -1。理由は last_error)。
func add_song(path: String) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	var size := SongLibrary.file_size(path)
	var key2 := "%s|%d" % [path.get_file().to_lower(), size]
	if _song_keys.has(key):   # すでに一覧にある(パスが同じ、または名前と大きさが同じ)
		return _song_keys[key]
	if size >= 0 and _song_key2s.has(key2):
		return _song_key2s[key2]
	var info := SongLibrary.info(path)   # 曲を全部は開かずに、題名などを得る(結果は保存されて、次からは開き直さない)
	if not info.ok:
		last_error = str(info.error)
		return -1
	return _append(path, info, false)


## 索引の要約(info)から、一覧に足して番号を返す(重複は既存の番号)。folder = osu! の Songs の曲(ファイルの大きさは見ない)。
func _append(path: String, info: Dictionary, folder: bool) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	if _song_keys.has(key):
		return _song_keys[key]
	var key2 := "%s|%d" % [path.get_file().to_lower(), -1 if folder else SongLibrary.file_size(path)]
	if not folder and _song_key2s.has(key2):
		return _song_key2s[key2]
	if _song_md5s.has(info.md5):   # 別の名前で同じ曲が入っている(譜面の中身が同じ)ときも、1 つにする
		return _song_md5s[info.md5]
	var ids = info.get("ids", {})
	var sg := {"path": path, "title": info.title, "artist": info.artist, "key": key, "key2": key2, "md5": info.md5,
		"ids": (ids as Dictionary).keys() if ids is Dictionary else [], "mtime": FileAccess.get_modified_time(path), "folder": folder}
	_register(sg)
	return songs.size() - 1


func _register(sg: Dictionary) -> void:
	songs.append(sg)
	var idx := songs.size() - 1
	_song_keys[sg.key] = idx
	_song_key2s[sg.key2] = idx
	_song_md5s[sg.md5] = idx


# --- 検索と並び替え(表示用) ---

## 並び替えの種類 [id, 名前]。設定の song_sort に、id を保存する
const SORT_MODES := [["title", "曲名"], ["artist", "アーティスト"], ["added", "追加順"], ["rank", "ランク"], ["diff", "難易度"], ["length", "長さ"]]
## ランク順の並び(左ほど上)。記録のない曲は、いちばん後ろ
const RANK_ORDER := ["SS", "S", "A", "B", "C", "D", "F"]

## 曲(ids = 難易度の識別子の一覧)の最高記録を返す関数(確認用に差し替えられる)。既定はプレイ記録(Records)
var best_of: Callable = func(ids: Array) -> Dictionary: return Records.best_of_song(ids)
## 曲 i の譜面の一覧 [[譜面の識別子, 難易度名, Lv], ...] を返す関数。難易度順(chart_view)が使う。
## 既定は何も返さない。選曲画面が、SongArt に保存した推定の★・測った Lv で差し替える(確認用にも差し替えられる)
var charts_of: Callable = func(_i: int) -> Array: return []
## 曲 i の長さ(秒)を返す関数。長さ順が使う。分からない曲は 0 以下(長さ順では、いちばん後ろ)。選曲画面が、SongArt に保存した長さで差し替える(確認用にも差し替えられる)
var length_of: Callable = func(_i: int) -> float: return -1.0

## 検索の文字(空なら全部)。曲名・アーティストに含まれる曲だけを出す(大文字小文字・空白は区別しない)
var query := ""
var sort_mode := "title"


## 検索で比べる形(小文字にして、空白を除く)。
static func normalize(s: String) -> String:
	return s.to_lower().replace(" ", "").replace("　", "")


## i 番の曲が、いまの検索に合うか。
func matches(i: int) -> bool:
	var q := normalize(query)
	if q == "":
		return true
	return normalize(str(songs[i].title)).contains(q) or normalize(str(songs[i].artist)).contains(q)


## 表示する曲の番号(songs の添字)を、いまの並び順で返す。songs 自体の並びと番号は変えない(選択の番号は、これまでどおり)。
func view() -> Array:
	var out: Array = []
	for i in range(songs.size()):
		if matches(i):
			out.append(i)
	match sort_mode:
		"artist":
			out.sort_custom(func(a, b): return _cmp(str(songs[a].artist).to_lower(), str(songs[b].artist).to_lower(), str(songs[a].title).to_lower(), str(songs[b].title).to_lower(), a, b))
		"added":   # 新しく追加(ファイルの更新)した順
			out.sort_custom(func(a, b):
				if int(songs[a].mtime) != int(songs[b].mtime):
					return int(songs[a].mtime) > int(songs[b].mtime)
				return a < b)
		"length":   # 短い順(長さが分からない曲は後ろ。同じ長さなら曲名順)
			var lens := {}
			for i in out:
				lens[i] = floorf(float(length_of.call(i)))
			out.sort_custom(func(a, b):
				var ua: bool = lens[a] <= 0.0
				var ub: bool = lens[b] <= 0.0
				if ua != ub:
					return ub
				if not ua and lens[a] != lens[b]:
					return lens[a] < lens[b]
				return _cmp(str(songs[a].title).to_lower(), str(songs[b].title).to_lower(), str(songs[a].artist).to_lower(), str(songs[b].artist).to_lower(), a, b))
		"rank":   # 最高ランクの高い順(同じなら最高スコアの高い順、記録のない曲は後ろに曲名順)
			var key := {}
			for i in out:
				var b: Dictionary = best_of.call(songs[i].get("ids", []))
				var r := RANK_ORDER.find(str(b.get("rank", ""))) if not b.is_empty() else RANK_ORDER.size()
				key[i] = [r if r >= 0 else RANK_ORDER.size() - 1, -int(b.get("score", 0))]
			out.sort_custom(func(a, b):
				if key[a] != key[b]:
					return key[a][0] < key[b][0] or (key[a][0] == key[b][0] and key[a][1] < key[b][1])
				return _cmp(str(songs[a].title).to_lower(), str(songs[b].title).to_lower(), str(songs[a].artist).to_lower(), str(songs[b].artist).to_lower(), a, b))
		_:
			out.sort_custom(func(a, b): return _cmp(str(songs[a].title).to_lower(), str(songs[b].title).to_lower(), str(songs[a].artist).to_lower(), str(songs[b].artist).to_lower(), a, b))
	return out


## 難易度順(sort_mode == "diff")か。このときの一覧は、曲ごとではなく、譜面(曲 × 難易度)を 1 つずつ並べる(chart_view)。
func chart_mode() -> bool:
	return sort_mode == "diff"


## 難易度順の一覧: 検索に合う曲の譜面を、1 つずつバラして、Lv の低い順に並べる(同じ Lv は、曲名 → 元の番号 → 難易度名の順)。
## 要素は {s: 曲の番号, id: 譜面の識別子, name: 難易度名, lv: Lv}。まだ難易度が分かっていない曲(charts_of が空を返す曲)は、出ない。
func chart_view() -> Array:
	var out: Array = []
	for i in range(songs.size()):
		if not matches(i):
			continue
		for d in charts_of.call(i):
			out.append({"s": i, "id": str(d[0]), "name": str(d[1]), "lv": snappedf(float(d[2]), 0.01)})   # 画面に出る小数 2 桁で比べる
	var titles := {}
	for c in out:
		if not titles.has(c.s):
			titles[c.s] = str(songs[c.s].title).to_lower()
	out.sort_custom(func(a, b):
		if a.lv != b.lv:
			return a.lv < b.lv
		if titles[a.s] != titles[b.s]:
			return titles[a.s] < titles[b.s]
		if a.s != b.s:
			return a.s < b.s
		return str(a.name) < str(b.name))
	return out


## 第 1 キー・第 2 キー・元の番号の順に比べる(a が前なら true)。
static func _cmp(k1a: String, k1b: String, k2a: String, k2b: String, ia: int, ib: int) -> bool:
	if k1a != k1b:
		return k1a < k1b
	if k2a != k2b:
		return k2a < k2b
	return ia < ib


## 表示している曲のうち、from の次(dir = 1)・前(dir = -1)の番号。端なら from のまま、表示している曲がなければ -1。from が表示にないときは、先頭(末尾)。
func step_in_view(from: int, dir: int) -> int:
	var v := view()
	if v.is_empty():
		return -1
	var k := v.find(from)
	if k < 0:
		return v[0] if dir > 0 else v[v.size() - 1]
	return v[clampi(k + dir, 0, v.size() - 1)]


## 直前にプレイした曲の番号(なければ 0)。
func last_song_index() -> int:
	return int(_song_keys.get(SongLibrary.norm(str(settings.last_song)), 0))


# --- 曲を選ぶ ---

## 曲を選ぶ。表示はすぐ切り替わり(song_changing)、重い読み込みは別スレッドで行って、終わったら song_loaded が出る。
## 同じ曲を(読み込み済み・読み込み中に)選び直したときは、何もせず false を返す。
func select_song(i: int) -> bool:
	if songs.is_empty():
		return false
	i = clampi(i, 0, songs.size() - 1)
	if i == song_sel and (loader != null or job_pending):
		return false
	prev_sel = song_sel if not job_pending else prev_sel
	var old := song_sel
	song_sel = i
	job += 1
	job_pending = true
	loading_now = true
	_reload_keep = ""
	song_changing.emit(old, i)
	_start_job(songs[i].path)
	return true


## MOD で弾幕の作り方(v1 / v2)が変わった・弾幕を変える MOD で全譜面の発射の一覧が要るようになったか(そうなら、reload_for_style で読み直す)。
func needs_style_reload() -> bool:
	if loader == null:
		return false
	var p := Mods.params(settings.mods)
	if bool(p.gen_v2) != gens_v2:
		return true
	# 統計だけの弾幕に、弾幕を変える MOD(加速・弾数など)を付けた: Lv を測り直すのに、全譜面の発射の一覧が要るので、読み直す
	return not Mods.pattern_neutral(p) and gens.any(func(g): return ChartCache.is_stub(g))


## 同じ曲を、今の弾幕の作り方で読み直す(選んでいた難易度はそのまま。弾幕は作り方ごとに覚えているので、戻すときは速い)。
func reload_for_style() -> void:
	if loader == null or job_pending or song_sel < 0 or song_sel >= songs.size():
		return
	_reload_keep = str(loader.difficulties[diff_sel].version) if diff_sel >= 0 else ""
	if _reload_keep == "":
		_reload_keep = " "
	job += 1
	job_pending = true
	loading_now = true
	song_reloading.emit()
	_start_job(songs[song_sel].path)


## 読み込み(別スレッド)を始める。結果は _on_load_done へ(いまの job のものだけが使われる)。
func _start_job(path: String) -> void:
	var my_job := job
	var p := Mods.params(settings.mods)
	var me: WeakRef = weakref(self)   # 読み込み中に画面が閉じられても、届け先がなければ捨てる
	WorkerThreadPool.add_task(func():
		var res := load_song(path, p)
		res["job"] = my_job
		var target: Object = me.get_ref()
		if target != null:
			target._on_load_done.call_deferred(res)
		elif res.get("loader") != null:
			res.loader.close())


## 前の曲の OszLoader を、別スレッドで手放す(主スレッドで手放すと止まる)。弾幕の一覧は、キャッシュ(_gen_cache)と共有しているので、ここでは壊さない。
func _release_later(old_loader) -> void:
	if old_loader == null:
		return
	WorkerThreadPool.add_task(func():
		old_loader.close()
		old_loader.difficulties.clear())


## 前の曲の弾幕を、別スレッドで手放す。保存から読んだ弾幕は、キャッシュ(_gen_cache)と共有していないので、ここで手放すと、解放だけで 20〜30 ms かかって、
## 画面が 1 フレーム止まる(一覧の動きが跳ぶ)。キャッシュと共有しているものは、手放しても解放されない(ここでは何も起きない)。
func _release_gens_later(old: Array) -> void:
	if old.is_empty():
		return
	var holder := {"g": old}   # 最後の参照を、別スレッドで外す(この関数が終わると、old の参照は holder だけになる)
	WorkerThreadPool.add_task(func(): holder.g = null)


func _on_load_done(res: Dictionary) -> void:
	if _closed or int(res.job) != job:   # 画面を離れた / 別の曲を選び直した
		if res.get("loader") != null:
			res.loader.close()
		if res.get("gens") is Array:
			_release_gens_later(res.gens)   # 捨てる弾幕の解放も、別スレッドで(曲を次々に選んだとき、画面が止まらない)
		return
	job_pending = false
	loading_now = false
	if not res.ok:
		_reload_keep = ""
		var bad := song_sel
		song_sel = prev_sel   # 選べなかったので、元の曲の選択に戻す
		song_load_failed.emit(str(res.error), bad)
		return
	_release_later(loader)   # 前の曲の譜面は、量が多く、ここで手放すと解放だけで十数 ms かかる
	loader = res.loader
	_release_gens_later(gens)
	gens = res.gens
	gens_v2 = bool(res.get("v2", false))
	_full_pending.clear()
	if song_sel >= 0 and song_sel < songs.size() and res.get("levels") is Dictionary:
		SongArt.set_levels(str(songs[song_sel].md5), gens_v2, res.levels)   # 測った Lv を残す(難易度順・難易度の表示に使う)
	full_audio = res.audio_full
	full_audio_file = str(res.audio_file)
	# 曲を移ったときは、前に選んでいた難易度に Lv がいちばん近いものを選ぶ(Lv 7 を遊んでいる人が、曲を変えるたびに易しい譜面に戻らない)。最初の 1 回は 3 番目
	var prev_lv := -1.0
	if diff_sel >= 0 and diff_sel < ratings.size():
		prev_lv = float(ratings[diff_sel].level)
	ratings = res.ratings
	diff_sel = mini(2, gens.size() - 1)
	if prev_lv >= 0.0:
		var best := INF
		for k3 in range(ratings.size()):
			var gap := absf(float(ratings[k3].level) - prev_lv)
			if gap < best:
				best = gap
				diff_sel = k3
	# 直前にプレイした曲に戻ったときは、そのとき選んだ難易度を選んだ状態にする
	if songs[song_sel].key == SongLibrary.norm(str(settings.last_song)) and settings.last_diff != "":
		for k2 in range(loader.difficulties.size()):
			if loader.difficulties[k2].version == settings.last_diff:
				diff_sel = k2
	res["reload"] = _reload_keep != ""
	if _reload_keep != "":   # 弾幕の作り方が変わった読み直し: 選んでいた難易度に戻す
		for k4 in range(loader.difficulties.size()):
			if str(loader.difficulties[k4].version) == _reload_keep:
				diff_sel = k4
		_reload_keep = ""
	song_loaded.emit(res)
	ensure_full(diff_sel)   # 選んでいる譜面の発射の一覧(統計だけのとき)を、裏で用意する
	if needs_style_reload():   # 読み込んでいるあいだに、弾幕 v2 の入り切りが変わっていた
		reload_for_style()


# --- 難易度 ---

## 全難易度について、今の MOD を適用した弾幕で難易度を測り直す。
func rate_all() -> void:
	var p := Mods.params(settings.mods)
	ratings = gens.map(func(g): return PatternGen.summary(Mods.apply(g, p)))


## 難易度を選ぶ(難易度の数の範囲に収める)。選べなければ -2、選べたら選ぶ前の番号を返す。
func select_diff(i: int) -> int:
	if ratings.is_empty() or loader == null:
		return -2
	i = clampi(i, 0, ratings.size() - 1)
	var old := diff_sel
	diff_sel = i
	ensure_full(i)
	return old


## 選択中の難易度の、MOD 適用後の Lv(難易度がなければ -1)。
func selected_level() -> float:
	if diff_sel < 0 or diff_sel >= ratings.size():
		return -1.0
	return float(ratings[diff_sel].level)


# --- プレイへ渡す ---

## 始められるか(曲を読み込み終わっていて、難易度を選んでいて、その譜面の発射の一覧がそろっている)。
func can_start() -> bool:
	return loader != null and diff_sel >= 0 and not job_pending and diff_sel < gens.size() and not ChartCache.is_stub(gens[diff_sel])


## 選んでいる譜面の発射の一覧を、まだ待っているか(統計だけで、用意の途中)。
func waiting_full() -> bool:
	return loader != null and diff_sel >= 0 and diff_sel < gens.size() and ChartCache.is_stub(gens[diff_sel])


## 選んだ曲・難易度を設定に覚えさせる(次に選曲画面を開いたとき、この状態で開く)。
func remember_selection() -> void:
	if song_sel >= 0:
		settings.last_song = songs[song_sel].path
		settings.last_diff = loader.difficulties[diff_sel].version
	Settings.save_all(settings)


## プレイ画面へ渡すもの {loader, bm, settings, pre, level}。pre は、選曲のときに作っておいたもの(弾幕・曲全体の音声)で、プレイ画面が作り直さず(読み直さず)に使う。
func launch_info() -> Dictionary:
	var bm = loader.difficulties[diff_sel]
	var pre := {"gen": gens[diff_sel]}
	if full_audio != null and bm.audio_filename == full_audio_file:
		pre["audio"] = full_audio
	return {"loader": loader, "bm": bm, "settings": settings, "pre": pre, "level": float(ratings[diff_sel].level)}


# --- 発射の一覧を、あとから用意する(統計だけで開いた曲) ---

## 選んでいる曲の k 番の譜面が統計だけ(stub)なら、発射の一覧を、別スレッドで用意する(保存してあれば読み、なければ作って保存する)。
## できたら gen_ready が出る(それまで can_start は false)。用意の途中に曲が変わったら、結果は捨てる。
func ensure_full(k: int) -> void:
	if loader == null or song_sel < 0 or song_sel >= songs.size() or k < 0 or k >= gens.size() or not ChartCache.is_stub(gens[k]) or _full_pending.has(k):
		return
	_full_pending[k] = true
	var from_loader = loader
	var path := str(songs[song_sel].path)
	var bm = loader.difficulties[k]
	var v2 := gens_v2
	var me: WeakRef = weakref(self)
	WorkerThreadPool.add_task(func():
		var full := full_gen_for(path, bm, v2, true)
		var target: Object = me.get_ref()
		if target != null:
			target._on_full_done.call_deferred(k, full, from_loader))


func _on_full_done(k: int, full: Dictionary, from_loader) -> void:
	if _closed or loader != from_loader or k >= gens.size():
		return
	_full_pending.erase(k)
	if not ChartCache.is_stub(gens[k]):
		return
	gens[k] = full
	gen_ready.emit(k)


# --- 全曲の難易度を、あらかじめ裏で用意する ---
## 保存(ChartCache)の統計がない曲を、別スレッドで 1 曲ずつ処理して(解析 → 全難易度の弾幕 → 統計を保存)、全曲の Lv をそろえる。
## 曲の読み込み中・プレイ中は待つ。結果は pump が受け取って、SongArt に Lv を残す。進み具合は prep_progress。

static var _prep_mutex := Mutex.new()
static var _prep_out: Array = []       # できた曲の結果 [{key, v2, levels}](pump が受け取る)
static var _prep_running := false
static var _prep_done := 0
static var _prep_total := 0
static var _prep_stop := false
static var _prep_failed := {}          # 読めなかった曲(パス)。何度も試さない


## 準備を始める(統計のない曲があれば)。始めたら true。すでに動いている・全部そろっているときは false。
func start_prep(v2: bool) -> bool:
	if _prep_running or not ChartCache.enabled:
		return false
	var todo: Array = []
	for sg in songs:
		if not ChartCache.has_stats(str(sg.path), v2) and not _prep_failed.has(str(sg.path)):
			todo.append([str(sg.path), str(sg.md5)])
	if todo.is_empty():
		return false
	_prep_mutex.lock()
	_prep_running = true
	_prep_stop = false
	_prep_done = 0
	_prep_total = todo.size()
	_prep_mutex.unlock()
	WorkerThreadPool.add_task(Callable(get_script(), "_prep_loop").bind(todo, v2), false, "chart prep")
	return true


## 準備を止める(画面を離れるとき)。処理中の 1 曲は、そのまま終わる。
static func stop_prep() -> void:
	_prep_stop = true


## 準備の進み具合 {running, done, total}。
static func prep_progress() -> Dictionary:
	_prep_mutex.lock()
	var out := {"running": _prep_running, "done": _prep_done, "total": _prep_total}
	_prep_mutex.unlock()
	return out


static func _prep_loop(todo: Array, v2: bool) -> void:
	for e in todo:
		while (SongArt.paused or loading_now) and not _prep_stop:   # プレイ中・曲の読み込み中は、譲る
			OS.delay_msec(150)
		if _prep_stop:
			break
		var levels := prep_song(str(e[0]), v2)
		_prep_mutex.lock()
		if not levels.is_empty():
			_prep_out.append({"key": str(e[1]), "v2": v2, "levels": levels})
		else:
			_prep_failed[str(e[0])] = true
		_prep_done += 1
		_prep_mutex.unlock()
		OS.delay_msec(40)   # 続けざまに走らせず、ほかの作業(画面・音)に譲る
	_prep_mutex.lock()
	_prep_running = false
	_prep_mutex.unlock()


## 1 曲の統計を作って保存する(別スレッドで動く)。戻り値: 譜面の識別子 → Lv(読めない曲は空)。曲の読み込み(load_song)と同じ並び・同じ中身。
static func prep_song(path: String, v2: bool) -> Dictionary:
	var l = OszLoader.new()
	if not l.open(path):
		return {}
	var first = l.difficulties[0]
	var made := _generate_all(l, v2, false)   # 1 スレッド(画面・音に、できるだけ響かないように)
	var gens: Array = made.gens
	ChartCache.save_stats(path, v2, {"bms": l.difficulties.map(func(b): return b.to_meta()), "stubs": gens.map(func(g): return ChartCache.stub_of(g)), "first_md5": str(first.md5)})
	var levels := {}
	for k in range(gens.size()):
		levels[str(l.difficulties[k].md5)] = float(gens[k].level)
	l.close()
	return levels


# --- 読み込み(別スレッドで動く部分) ---

## 弾幕のキャッシュ(曲のファイル → 難易度の並び順と、MOD 適用前の弾幕)。別スレッドからも使うので、Mutex で守る。新しく使ったものを末尾にして、古いものから捨てる。
const GEN_CACHE_MAX := 10
static var _gen_cache: Dictionary = {}
static var _gen_cache_keys: Array = []
static var _gen_mutex := Mutex.new()


static func _gen_cache_get(key: String, count: int) -> Dictionary:
	_gen_mutex.lock()
	var hit: Dictionary = {}
	if _gen_cache.has(key) and (_gen_cache[key].order as Array).size() == count:
		hit = _gen_cache[key]
		_gen_cache_keys.erase(key)
		_gen_cache_keys.append(key)
	_gen_mutex.unlock()
	return hit


static func _gen_cache_put(key: String, order: Array, gens_made: Array) -> void:
	_gen_mutex.lock()
	_gen_cache[key] = {"order": order, "gens": gens_made}
	_gen_cache_keys.erase(key)
	_gen_cache_keys.append(key)
	while _gen_cache_keys.size() > GEN_CACHE_MAX:
		_gen_cache.erase(_gen_cache_keys.pop_front())
	_gen_mutex.unlock()


## 弾幕を作る。v2 = MOD「弾幕 v2」(PatternGenV2)。
static func make_gen(bm, v2: bool) -> Dictionary:
	return PatternGenV2.generate(bm, {}) if v2 else PatternGen.generate(bm, {})


## 開発用: 弾幕の作り方をその場で切り替える(順序は変えない。スクリーンショットの MOD 指定用)。
func debug_regen() -> void:
	var v2 := bool(Mods.params(settings.mods).gen_v2)
	if loader != null and v2 != gens_v2:
		gens = loader.difficulties.map(func(bm): return make_gen(bm, v2))
		gens_v2 = v2


## (別スレッドで動く)曲を開いて、難易度ごとの弾幕・難易度(MOD 適用後)・背景画像・試聴用の音声まで作る。画面には触らない。
## 保存(ChartCache)の統計があれば、譜面の解析も弾幕の生成もしない: 弾幕は「統計」だけ(stub。発射の一覧はない)で、難易度の表示には足りる。
## 発射の一覧は、選んだ譜面の分だけ、あとから ensure_full が作る(保存してあれば読む)。
## want_full = true、または、弾幕を変える MOD(加速・弾数・弾速・弾の大きさ・自機の大きさ)を付けているときは、全譜面の発射の一覧を用意する
## (保存した発射の一覧があればそれを読み、なければ作る。このときの分は保存しない。Lv を測り直すのに、全譜面の発射の一覧が要るため)。
static func load_song(path: String, mod_params: Dictionary, want_full := false) -> Dictionary:
	if not _pruned:   # 保存した譜面(ChartCache)が増えすぎていたら、起動のあと 1 回だけ、別のスレッドで古いものを捨てる
		_pruned = true
		WorkerThreadPool.add_task(ChartCache.prune)
	var v2 := bool(mod_params.get("gen_v2", false))   # MOD「弾幕 v2」: 弾幕の作り方が違うので、覚えておくのも別(v1 / v2 の両方を覚える)
	var need_all := want_full or not Mods.pattern_neutral(mod_params)
	var l = OszLoader.new()
	var first = null
	var gens_out: Array = []
	var from_stats := false
	var saved := ChartCache.load_stats(path, v2)
	if not saved.is_empty() and l.open_cached(path, saved.bms):
		for bm in l.difficulties:
			if str(bm.md5) == str(saved.get("first_md5", "")):
				first = bm
		if first == null:
			first = l.difficulties[0]
		from_stats = true
		gens_out = saved.stubs
	else:
		l = OszLoader.new()
		if not l.open(path):
			return {"ok": false, "error": l.error}
		first = l.difficulties[0]
	var image: Image = l.load_image_data(first.background) if first.background != "" else null
	if image != null and image.get_width() > 1280:   # 背景は 1280×720 の画面に出すだけ。大きい画像は、ここ(別スレッド)で縮めて、テクスチャにする負担を減らす
		image.resize(1280, maxi(int(round(1280.0 * image.get_height() / image.get_width())), 1), Image.INTERPOLATE_BILINEAR)
	var key := "%s|%d|%d|%s" % [path, SongLibrary.file_size(path), FileAccess.get_modified_time(path), "v2" if v2 else "v1"]   # ファイルが差し替わったら別物
	if not from_stats:
		# 保存していない曲: 全難易度の弾幕を作る(直近 GEN_CACHE_MAX 曲はメモリにも覚える)。作ったら、統計を保存する(次からは、解析も生成もしない)
		var diffs: Array = l.difficulties
		var cached := _gen_cache_get(key, diffs.size())
		if not cached.is_empty():
			var order: Array = cached.order
			l.difficulties = order.map(func(i): return diffs[i])
			gens_out = cached.gens
		else:
			var made := _generate_all(l, v2, true)
			gens_out = made.gens
			_gen_cache_put(key, made.order, gens_out)
		ChartCache.save_stats(path, v2, {"bms": l.difficulties.map(func(b): return b.to_meta()), "stubs": gens_out.map(func(g): return ChartCache.stub_of(g)), "first_md5": str(first.md5)})
	elif need_all:
		# 統計から開いたが、発射の一覧が全譜面ぶん要る: メモリに覚えていればそれ、なければ、保存した発射の一覧か、その場で作る
		var key_all := key + "|all"
		var n: int = l.difficulties.size()
		var cached_all := _gen_cache_get(key_all, n)
		if not cached_all.is_empty():
			gens_out = cached_all.gens
		else:
			gens_out = _full_all(path, l.difficulties, v2)
			_gen_cache_put(key_all, range(n), gens_out)
	# Danmaku 難易度(Lv。MOD なしの状態)の低い順に並んでいる(保存したものは、並べ終わっている)
	var ratings_out: Array = gens_out.map(func(g): return PatternGen.summary(Mods.apply(g, mod_params)))
	var levels := {}   # 譜面の識別子 → MOD なしの Lv(SongArt に残して、難易度順・難易度の表示に使う)
	for k in range(gens_out.size()):
		levels[str(l.difficulties[k].md5)] = float(gens_out[k].level)
	var audio: AudioStream = l.load_audio(first.audio_filename)
	var from := maxf(first.preview_time / 1000.0, 0.0)
	var full: AudioStream = audio
	var cropped := crop_mp3(audio, from)
	if cropped != null:   # MP3 の途中から流すと、探す処理で数十 ms 止まる。あらかじめ、その位置から始まる音声にしておく
		audio = cropped
		from = 0.0
	return {"ok": true, "loader": l, "gens": gens_out, "v2": v2, "ratings": ratings_out, "levels": levels, "image": image, "audio": audio, "audio_from": from, "audio_full": full, "audio_file": first.audio_filename}


## 全難易度の弾幕を作って、Lv(同じなら本家★)の低い順に並べる。l.difficulties も同じ並びにする。戻り値: {gens, order(元の並びでの番号)}。
## parallel = true なら、難易度どうしが独立なので、並列に作る(generate は共有の状態を持たない)。MOD の適用は別なので、MOD を変えても使える。
static func _generate_all(l, v2: bool, parallel: bool) -> Dictionary:
	var diffs: Array = l.difficulties
	var made: Array = []
	made.resize(diffs.size())
	if parallel and diffs.size() > 1:
		var gid := WorkerThreadPool.add_group_task(func(i: int): made[i] = make_gen(diffs[i], v2), diffs.size())
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for i in range(diffs.size()):
			made[i] = make_gen(diffs[i], v2)
	var pairs: Array = []
	for i in range(diffs.size()):
		pairs.append({"i": i, "bm": diffs[i], "g": made[i]})
	# 並びは表示する Lv の低い順(同じなら本家★)。生の密度(rating.score)では、弾速が AR で変わる弾幕 v2 で Lv と順が食い違う
	pairs.sort_custom(func(a, b): return a.g.level < b.g.level if not is_equal_approx(a.g.level, b.g.level) else a.g.stars < b.g.stars)
	l.difficulties = pairs.map(func(q): return q.bm)
	return {"gens": pairs.map(func(q): return q.g), "order": pairs.map(func(q): return q.i)}


## 譜面 bm の弾幕(発射の一覧を含む全部)。保存した発射の一覧があればそれを読み、なければ作る(save = true なら、作ったものを保存する)。別スレッドで動く。
static func full_gen_for(path: String, bm, v2: bool, save := true) -> Dictionary:
	var id := str(bm.md5)
	var g := ChartCache.load_events(path, id, v2)
	if g.is_empty():
		g = make_gen(bm, v2)
		if save:
			ChartCache.save_events(path, id, v2, g)
	return g


## 全譜面の弾幕(発射の一覧を含む全部)を並列に用意する(保存はしない)。diffs = 並びが決まった譜面。
static func _full_all(path: String, diffs: Array, v2: bool) -> Array:
	var out: Array = []
	out.resize(diffs.size())
	if diffs.size() > 1:
		var gid := WorkerThreadPool.add_group_task(func(i: int): out[i] = full_gen_for(path, diffs[i], v2, false), diffs.size())
		WorkerThreadPool.wait_for_group_task_completion(gid)
	elif diffs.size() == 1:
		out[0] = full_gen_for(path, diffs[0], v2, false)
	return out


## MP3 の、from 秒あたりから始まる音声(データの途中から切り出す。MP3 は、途中からでも読み始められる)。MP3 でない・先頭のとき・長さが分からないときは null。
static func crop_mp3(audio: AudioStream, from: float) -> AudioStream:
	if not audio is AudioStreamMP3 or from < 1.0:
		return null
	var total: float = audio.get_length()
	var bytes: PackedByteArray = audio.data
	if total <= from + 1.0 or bytes.is_empty():
		return null
	var out := AudioStreamMP3.new()
	out.data = bytes.slice(int(float(bytes.size()) * from / total))
	return out
