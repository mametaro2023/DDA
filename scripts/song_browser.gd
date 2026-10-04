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

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const Records = preload("res://scripts/records.gd")

## 設定の辞書(画面と同じものを共有する。mods・last_song・last_diff を読み書きする)
var settings: Dictionary = {}

var songs: Array = []           # [{path, title, artist, key, key2, md5, ids(難易度の識別子の一覧), mtime(ファイルの更新時刻)}]
var loader                      # 選択中の OszLoader
var gens: Array = []            # 難易度リストと同じ並びの、MOD 適用前の弾幕(生成結果)
var ratings: Array = []         # 同じ並びの Danmaku 難易度(MOD 適用後)
var song_sel := -1
var diff_sel := -1
var last_error := ""
var job := 0                    # 曲の読み込み(別スレッド)の通し番号。最新のものだけ使う
var job_pending := false        # 読み込み中か
var prev_sel := -1              # 読み込み中の曲を選ぶ前に選んでいた曲(読めなかったときに戻す)
var full_audio: AudioStream     # 選んでいる曲の、全体の音声(試聴用は途中から切り出したもの。プレイ画面へ渡す)
var full_audio_file := ""

var _closed := false


## 画面を離れる(以後に届く読み込みの結果は捨てる)。
func close() -> void:
	_closed = true


# --- 曲の検出 ---

## 一覧を作り直す。読めなかった曲があれば、その知らせの文を返す(なければ空)。
func scan() -> String:
	songs.clear()
	var failed: Array = []
	var paths := SongLibrary.find_all()   # 同じファイルは 1 つにまとめて返る
	for p in paths:
		if add_song(p) < 0:
			failed.append(str(p).get_file())
	SongLibrary.save_index(paths)
	if failed.is_empty():
		return ""
	return "読み込めなかった曲: " + ", ".join(failed.slice(0, 3)) + (" ほか %d 件" % (failed.size() - 3) if failed.size() > 3 else "")   # 読めなかった曲は、黙って飛ばさず、名前を出す


## songs フォルダの中身が変わったとき: 一覧を作り直す。選んでいる曲は、同じ曲を探して選び直す(読み込み直さない)。scan と同じ知らせの文を返す。
func rescan() -> String:
	var cur := ""
	if song_sel >= 0 and song_sel < songs.size():
		cur = str(songs[song_sel].key)
	var msg := scan()
	song_sel = -1
	for i in range(songs.size()):
		if songs[i].key == cur:
			song_sel = i
	return msg


## 追加して一覧の番号を返す(重複は既存の番号、読めなければ -1。理由は last_error)。
func add_song(path: String) -> int:
	path = path.replace("\\", "/")
	var key := SongLibrary.norm(path)
	var size := -1
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh != null:
		size = fh.get_length()
		fh.close()
	var key2 := "%s|%d" % [path.get_file().to_lower(), size]
	for i in range(songs.size()):   # すでに一覧にある(パスが同じ、または名前と大きさが同じ)
		if songs[i].key == key or (size >= 0 and songs[i].key2 == key2):
			return i
	var info := SongLibrary.info(path)   # 曲を全部は開かずに、題名などを得る(結果は保存されて、次からは開き直さない)
	if not info.ok:
		last_error = str(info.error)
		return -1
	for i in range(songs.size()):   # 別の名前で同じ曲が入っている(譜面の中身が同じ)ときも、1 つにする
		if songs[i].md5 == info.md5:
			return i
	songs.append({"path": path, "title": info.title, "artist": info.artist, "key": key, "key2": key2, "md5": info.md5,
		"ids": (info.ids as Dictionary).keys(), "mtime": FileAccess.get_modified_time(path)})
	return songs.size() - 1


# --- 検索と並び替え(表示用) ---

## 並び替えの種類 [id, 名前]。設定の song_sort に、id を保存する
const SORT_MODES := [["title", "曲名"], ["artist", "アーティスト"], ["added", "追加順"], ["rank", "ランク"]]
## ランク順の並び(左ほど上)。記録のない曲は、いちばん後ろ
const RANK_ORDER := ["SS", "S", "A", "B", "C", "D", "F"]

## 曲(ids = 難易度の識別子の一覧)の最高記録を返す関数(確認用に差し替えられる)。既定はプレイ記録(Records)
var best_of: Callable = func(ids: Array) -> Dictionary: return Records.best_of_song(ids)

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
	var pick := 0
	for i in range(songs.size()):
		if songs[i].key == SongLibrary.norm(str(settings.last_song)):
			pick = i
	return pick


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
	song_changing.emit(old, i)
	var my_job := job
	var path: String = songs[i].path
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
	return true


## 前の曲の OszLoader を、別スレッドで手放す(主スレッドで手放すと止まる)。弾幕の一覧は、キャッシュ(_gen_cache)と共有しているので、ここでは壊さない。
func _release_later(old_loader) -> void:
	if old_loader == null:
		return
	WorkerThreadPool.add_task(func():
		old_loader.close()
		old_loader.difficulties.clear())


func _on_load_done(res: Dictionary) -> void:
	if _closed or int(res.job) != job:   # 画面を離れた / 別の曲を選び直した
		if res.get("loader") != null:
			res.loader.close()
		return
	job_pending = false
	if not res.ok:
		var bad := song_sel
		song_sel = prev_sel   # 選べなかったので、元の曲の選択に戻す
		song_load_failed.emit(str(res.error), bad)
		return
	_release_later(loader)   # 前の曲の譜面は、量が多く、ここで手放すと解放だけで十数 ms かかる
	loader = res.loader
	gens = res.gens
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
	song_loaded.emit(res)


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
	return old


## 選択中の難易度の、MOD 適用後の Lv(難易度がなければ -1)。
func selected_level() -> float:
	if diff_sel < 0 or diff_sel >= ratings.size():
		return -1.0
	return float(ratings[diff_sel].level)


# --- プレイへ渡す ---

## 始められるか(曲を読み込み終わっていて、難易度を選んでいる)。
func can_start() -> bool:
	return loader != null and diff_sel >= 0 and not job_pending


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


## (別スレッドで動く)曲を開いて、難易度ごとの弾幕・難易度(MOD 適用後)・背景画像・試聴用の音声まで作る。画面には触らない。
static func load_song(path: String, mod_params: Dictionary) -> Dictionary:
	var l = OszLoader.new()
	if not l.open(path):
		return {"ok": false, "error": l.error}
	var first = l.difficulties[0]
	var image: Image = l.load_image_data(first.background) if first.background != "" else null
	if image != null and image.get_width() > 1280:   # 背景は 1280×720 の画面に出すだけ。大きい画像は、ここ(別スレッド)で縮めて、テクスチャにする負担を減らす
		image.resize(1280, maxi(int(round(1280.0 * image.get_height() / image.get_width())), 1), Image.INTERPOLATE_BILINEAR)
	# Danmaku 難易度(画面内の弾数。MOD なしの状態)の低い順に並べ替える
	# 弾幕の生成が読み込みの大半(1 難易度で 20〜200 ms)。一度作った曲は覚えておき(直近 GEN_CACHE_MAX 曲)、次からは作らない。
	# 作るときは、難易度どうしが独立なので並列に作る(generate は共有の状態を持たない)。MOD の適用は別(下の ratings)なので、MOD を変えても使える
	var diffs: Array = l.difficulties
	var key := "%s|%d|%d" % [path, SongLibrary.file_size(path), FileAccess.get_modified_time(path)]   # ファイルが差し替わったら別物
	var gens_out: Array = []
	var cached := _gen_cache_get(key, diffs.size())
	if not cached.is_empty():
		var order: Array = cached.order
		l.difficulties = order.map(func(i): return diffs[i])
		gens_out = cached.gens
	else:
		var made: Array = []
		made.resize(diffs.size())
		if diffs.size() > 1:
			var gid := WorkerThreadPool.add_group_task(func(i: int): made[i] = PatternGen.generate(diffs[i], {}), diffs.size())
			WorkerThreadPool.wait_for_group_task_completion(gid)
		else:
			made[0] = PatternGen.generate(diffs[0], {})
		var pairs: Array = []
		for i in range(diffs.size()):
			pairs.append({"i": i, "bm": diffs[i], "g": made[i]})
		pairs.sort_custom(func(a, b): return a.g.rating.score < b.g.rating.score)
		l.difficulties = pairs.map(func(q): return q.bm)
		gens_out = pairs.map(func(q): return q.g)
		_gen_cache_put(key, pairs.map(func(q): return q.i), gens_out)
	var ratings_out: Array = gens_out.map(func(g): return PatternGen.summary(Mods.apply(g, mod_params)))
	var audio: AudioStream = l.load_audio(first.audio_filename)
	var from := maxf(first.preview_time / 1000.0, 0.0)
	var full: AudioStream = audio
	var cropped := crop_mp3(audio, from)
	if cropped != null:   # MP3 の途中から流すと、探す処理で数十 ms 止まる。あらかじめ、その位置から始まる音声にしておく
		audio = cropped
		from = 0.0
	return {"ok": true, "loader": l, "gens": gens_out, "ratings": ratings_out, "image": image, "audio": audio, "audio_from": from, "audio_full": full, "audio_file": first.audio_filename}


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
