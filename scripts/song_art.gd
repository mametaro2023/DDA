extends Node
## 曲の一覧の見た目に使う、曲ごとの小さな情報(UI を持たない): 背景画像の縮小版(サムネイル)と、難易度の一覧(名前と、色に使う推定の★)。
## 曲を全部は開かずに一覧を出すため、初めての曲だけ別スレッドで .osz を開いて作り、user:// に保存する(次からは、保存したものを読むだけ)。
##   サムネイル … user://thumbs/<曲の識別子>.jpg(幅 THUMB_W まで縮めたもの)
##   難易度 … user://song_art.json({識別子: {"diffs": [[譜面の識別子, 難易度名, 推定★], ...], "img": 画像があるか, "len": 曲の長さ(秒。-1 = 読めなかった。ない = 前の版で保存した)}})
## 使い方: SongArt.request(曲の識別子, .osz のパス, 受け取り(cb(info)))。info = {diffs, tex(なければ null)}。
## 作業は 1 曲ずつ(曲の読み込みと CPU を取り合わない)。テクスチャへの変換は、1 フレームに 1 枚まで(止まりを作らない)。
## 読み込んだテクスチャは、最近使った MEM_MAX 曲ぶんだけ覚えておく。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const ChartCache = preload("res://scripts/chart_cache.gd")

const META_PATH := "user://song_art.json"
const THUMB_DIR := "user://thumbs"
const THUMB_W := 480
const MEM_MAX := 160
const VERSION := 1

static var inst: Node
## true の間は、新しい作業を始めず、結果の受け取り・保存もしない(プレイ中。別スレッドの解析や、メインでの画像の変換・保存が、プレイ中の画面を止めることがあるため)。
## 終わっていない作業は、プレイを離れてから続く。main が、画面の種類が変わるたびに設定する。
static var paused := false

static var _meta := {}          # 識別子 → {diffs, img}
static var _levels := {}        # 識別子 → {tag(弾幕の作り方の版の印。ChartCache.stamp_tag), v1: {譜面の識別子: Lv}, v2: {...}}(MOD なしの Lv。難易度順・難易度の表示に使う)
static var _meta_loaded := false
static var _meta_dirty := false
static var _levels_dirty := false
static var _tex := {}           # 識別子 → Texture2D(null = 画像なし)
static var _order: Array = []   # 覚えている順(古い順)
static var _queue: Array = []   # [{key, path}](先頭から処理)
static var _waiting := {}       # 識別子 → [cb, ...]
static var _meta_waiting := {}  # 識別子 → [cb, ...](難易度だけを待っているもの。request_meta)
static var _busy := false
static var _ready_q: Array = [] # 別スレッドから戻った結果(メインスレッドで、1 フレームに 1 つずつテクスチャにする)
static var _save_t := 0.0


## いつでも呼べるように、必要なら木に自分を置く(最初に request したとき)。
static func _ensure(tree: SceneTree) -> void:
	if inst != null and is_instance_valid(inst):
		return
	inst = load("res://scripts/song_art.gd").new()
	inst.name = "SongArt"
	tree.root.add_child.call_deferred(inst)


static func _load_meta() -> void:
	if _meta_loaded:
		return
	_meta_loaded = true
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary and int(d.get("v", 0)) == VERSION and d.get("songs") is Dictionary:
		_meta = d.songs
		if d.get("levels") is Dictionary:
			_levels = d.levels


## すでに分かっている難易度の一覧(なければ空)。[[譜面の識別子, 難易度名, 推定★], ...](易しい順)
static func diffs_of(key: String) -> Array:
	_load_meta()
	var m = _meta.get(key)
	return m.diffs if m is Dictionary else []


## 曲 key の、MOD なしの Lv を残す(弾幕の作り方 v2 / v1 ごと)。測ったときの弾幕の作り方の版(ChartCache.stamp_tag)も添える(版が変わったら、古い値は使わない)。
static func set_levels(key: String, v2: bool, levels: Dictionary) -> void:
	_load_meta()
	var tag := ChartCache.stamp_tag()
	var e: Dictionary = _levels.get(key, {})
	if str(e.get("tag", tag)) != tag:   # 前の版の値は、捨てる
		e = {}
	e["tag"] = tag
	e["v2" if v2 else "v1"] = levels
	_levels[key] = e
	_levels_dirty = true


## 曲 key の、譜面 chart_id の、MOD なしの Lv(まだ・版が違うときは -1)。
static func level_of(key: String, chart_id: String, v2: bool) -> float:
	_load_meta()
	var e = _levels.get(key)
	if not (e is Dictionary) or str(e.get("tag", "")) != ChartCache.stamp_tag():
		return -1.0
	var t = e.get("v2" if v2 else "v1")
	return float((t as Dictionary).get(chart_id, -1.0)) if t is Dictionary else -1.0


## 曲の長さ(秒。いちばん長い譜面の、最初のノーツから最後までの長さ)。まだ分からない・読めなかった曲は -1。
static func length_of(key: String) -> float:
	_load_meta()
	var m = _meta.get(key)
	return float((m as Dictionary).get("len", -1.0)) if m is Dictionary else -1.0


## 曲の長さが保存してあるか(読めなかった曲の -1 も、保存してあれば true)。
static func has_length(key: String) -> bool:
	_load_meta()
	var m = _meta.get(key)
	return m is Dictionary and (m as Dictionary).has("len")


## 覚えているテクスチャ(なければ null。まだ読んでいないのか、画像がないのかは区別しない)。
static func texture_of(key: String) -> Texture2D:
	return _tex.get(key)


## 曲の情報を求める。そろっていれば、次のフレームで cb(info) を呼ぶ。なければ作って(読み込んで)から呼ぶ。
## front = true は、待ち行列の先頭に入れる(選んだ曲・見えている曲)。cb の持ち主が消えていたら、呼ばない。
static func request(tree: SceneTree, key: String, path: String, cb: Callable, front := false) -> void:
	_ensure(tree)
	_load_meta()
	if _tex.has(key) and _meta.has(key):
		_touch(key)
		_call_back.bind(cb, {"diffs": _meta[key].diffs, "tex": _tex[key]}).call_deferred()
		return
	if _waiting.has(key):
		(_waiting[key] as Array).append(cb)
		if front:   # すでに並んでいる: 先頭へ
			for i in range(_queue.size()):
				if _queue[i].key == key and not _queue[i].get("meta_only", false):
					var job: Dictionary = _queue[i]
					_queue.remove_at(i)
					_queue.push_front(job)
					break
		return
	_waiting[key] = [cb]
	var job := {"key": key, "path": path, "have_meta": _meta.has(key) and not bool((_meta[key] as Dictionary).get("partial", false))}
	if front:
		_queue.push_front(job)
	else:
		_queue.append(job)


## 難易度の一覧だけを求める(画像は作らない)。難易度順の並び替えで、まだ分かっていない曲の分を、裏で 1 曲ずつ集めるのに使う。
## 分かっていれば、次のフレームで cb(info) を呼ぶ(info.tex は null)。画像は、あとで request が作る(ここで残すのは「一部だけ」の印 partial)。
## need_len = true なら、曲の長さ(len)が分かっていない曲(前の版で保存した分)も、集め直す。
static func request_meta(tree: SceneTree, key: String, path: String, cb: Callable, need_len := false) -> void:
	_ensure(tree)
	_load_meta()
	if _meta.has(key) and not (need_len and not (_meta[key] as Dictionary).has("len")):
		_call_back.bind(cb, {"diffs": _meta[key].diffs, "tex": null}).call_deferred()
		return
	if _meta_waiting.has(key):
		(_meta_waiting[key] as Array).append(cb)
		return
	_meta_waiting[key] = [cb]
	_queue.append({"key": key, "path": path, "have_meta": false, "meta_only": true})


## いま難易度を集めている(待っている)曲の数。
static func meta_pending() -> int:
	return _meta_waiting.size()


## まだ作業が残っているか(撮影で、画像がそろうのを待つのに使う)。
static func busy() -> bool:
	return _busy or not _queue.is_empty() or not _ready_q.is_empty()


## 待ち行列を空にする(画面を離れたとき。作業中の 1 曲は、そのまま終わらせる)。
static func cancel_all() -> void:
	_queue.clear()
	_waiting.clear()
	_meta_waiting.clear()


static func _call_back(cb: Callable, info: Dictionary) -> void:
	if cb.is_valid():
		cb.call(info)


static func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)
	while _order.size() > MEM_MAX:
		_tex.erase(_order.pop_front())


func _process(delta: float) -> void:
	if paused:
		return
	if not _busy and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		_busy = true
		var thumb := "%s/%s.jpg" % [THUMB_DIR, job.key]
		var meta_has_img := bool((_meta.get(job.key, {}) as Dictionary).get("img", false)) if job.have_meta else false
		WorkerThreadPool.add_task(func():
			var r := _work(job, thumb, meta_has_img)
			_finish.call_deferred(r))
	if not _ready_q.is_empty():   # テクスチャへの変換(転送)は 1 フレームに 1 枚
		var r: Dictionary = _ready_q.pop_front()
		var key: String = r.key
		if r.get("meta_only", false):
			# 難易度だけ。すでに全部そろっている曲の記録は、一部だけのもので上書きしない。画像のテクスチャは作らない(あとで request が作る)
			var have: Dictionary = _meta.get(key, {})
			if have.is_empty() or bool(have.get("partial", false)):
				_meta[key] = {"diffs": r.diffs, "img": false, "partial": true, "len": r.len}
				_meta_dirty = true
			elif not have.has("len"):   # 前の版で保存した分: 長さだけ足す
				have["len"] = r.len
				_meta_dirty = true
			var minfo := {"diffs": (_meta.get(key, {}) as Dictionary).get("diffs", []), "tex": null}
			for cb in _meta_waiting.get(key, []):
				_call_back(cb, minfo)
			_meta_waiting.erase(key)
		else:
			if r.has("diffs"):
				_meta[key] = {"diffs": r.diffs, "img": r.img != null, "len": r.get("len", -1.0)}
				_meta_dirty = true
			var tex: Texture2D = ImageTexture.create_from_image(r.img) if r.img != null else null
			_tex[key] = tex
			_touch(key)
			var info := {"diffs": (_meta.get(key, {}) as Dictionary).get("diffs", []), "tex": tex}
			for cb in _waiting.get(key, []):
				_call_back(cb, info)
			_waiting.erase(key)
	if _meta_dirty or _levels_dirty:
		_save_t += delta
		if _save_t > (1.0 if _meta_dirty else 10.0):   # まとめて保存する(Lv だけが増えたときは、間を長く: 曲が多いと、保存は主スレッドで数十 ms かかる)
			_save_t = 0.0
			_meta_dirty = false
			_levels_dirty = false
			var f := FileAccess.open(META_PATH, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify({"v": VERSION, "songs": _meta, "levels": _levels}))
				f.close()


func _finish(r: Dictionary) -> void:
	_busy = false
	if not r.is_empty():
		_ready_q.append(r)


## 別スレッド: 保存したサムネイルがあれば読むだけ。なければ .osz を開いて、難易度の一覧とサムネイルを作る。
static func _work(job: Dictionary, thumb: String, meta_has_img: bool) -> Dictionary:
	if job.get("meta_only", false):   # 難易度の一覧だけ(画像は作らない)
		var lm = OszLoader.new()
		if not lm.open(str(job.path)):
			return {"key": job.key, "meta_only": true, "diffs": [], "len": -1.0}
		var ds: Array = []
		var longest := 0.0
		for bm in lm.difficulties:
			ds.append([str(bm.md5), str(bm.version), snappedf(float(bm.stars), 0.01)])
			longest = maxf(longest, (bm.last_time() - bm.first_time()) / 1000.0)
		lm.close()
		return {"key": job.key, "meta_only": true, "diffs": ds, "len": roundf(longest)}
	if job.have_meta:
		var img: Image = null
		if meta_has_img and FileAccess.file_exists(thumb):
			img = Image.load_from_file(thumb)
		if img != null or not meta_has_img:
			return {"key": job.key, "img": img}
	var l = OszLoader.new()
	if not l.open(str(job.path)):
		return {"key": job.key, "img": null, "diffs": [], "len": -1.0}
	var diffs: Array = []
	var bg := ""
	var longest := 0.0
	for bm in l.difficulties:   # OszLoader の並び(物量の少ない順)= 選曲で選んだときの並び
		diffs.append([str(bm.md5), str(bm.version), snappedf(float(bm.stars), 0.01)])
		longest = maxf(longest, (bm.last_time() - bm.first_time()) / 1000.0)
		if bg == "" and bm.background != "":
			bg = bm.background
	var img: Image = l.load_image_data(bg) if bg != "" else null
	l.close()
	if img != null:
		if img.get_width() > THUMB_W:
			img.resize(THUMB_W, maxi(1, int(round(img.get_height() * float(THUMB_W) / img.get_width()))), Image.INTERPOLATE_BILINEAR)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(THUMB_DIR))
		img.save_jpg(thumb, 0.85)
	return {"key": job.key, "img": img, "diffs": diffs, "len": roundf(longest)}
