extends Node
## osu! の曲を探す(UI を持たない)。非公式ミラー osu.direct の検索 API(ログイン不要)を使う。osu! 公式の API は、アプリごとの秘密の鍵が要るので使わない。
## 結果は osu!standard の譜面を含む曲(BeatmapSet)だけ。1 回に PAGE 件、offset で続きを読む。
## ジャケット画像(assets.ppy.sh の list.jpg。正方形)は、同時に COVER_PARALLEL 件まで取り、user:// に保存して使い回す。
## ダウンロードそのものは main(song_download.gd・同意の確認)が行う。ここは探すだけ。

## 検索の結果。req: search() が返した番号(古い検索の結果は届かない)。items: 下の _item() の形。more: 続きがありそう
signal results(req: int, items: Array, more: bool)
signal failed(req: int, msg: String)
## ジャケット画像ができた
signal cover_ready(set_id: int, tex: Texture2D)

const PAGE := 30
const COVER_PARALLEL := 4
const COVER_DIR := "user://web_covers"
const COVER_MEM := 240   # 覚えておくジャケットの数(超えたら古いものから忘れる。ファイルは残る)
const USER_AGENT := "User-Agent: Danmaku (+https://github.com/mametaro2023/DDA)"

## 並び順: id → osu.direct の sort の値
const SORTS := {"plays": "play_count:desc", "new": "ranked_date:desc", "favs": "favourite_count:desc"}
## 絞り込み: id → status の値(空 = すべて)
const STATUSES := {"ranked": "1", "loved": "4", "all": ""}

## 検索 API の場所(テストでは手元のサーバーに差し替える)
var base_url := "https://osu.direct/api/v2/search"

var _req := 0
var _http: HTTPRequest
var _cover_wait: Array = []          # [set_id, url] まだ取りに行っていないジャケット
var _cover_busy := {}                # set_id → HTTPRequest
var _cover_mem := {}                 # set_id → Texture2D
var _cover_order: Array = []


## 探す。query が空なら、並び順どおりの一覧(おすすめ)。offset: 続きを読むときの、すでにある件数。返り値の番号が results / failed に付く。
func search(query: String, sort_id := "plays", status_id := "ranked", offset := 0) -> int:
	_req += 1
	var req := _req
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.body_size_limit = 8 * 1024 * 1024
	add_child(_http)
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray): _on_search_done(req, result, code, body))
	var err := _http.request(build_url(query, sort_id, status_id, offset), PackedStringArray([USER_AGENT]))
	if err != OK:
		failed.emit.call_deferred(req, "つながりませんでした")
	return req


## 検索の URL(文字は URL 用に変換する。query 以外は、決まった値だけ)。
func build_url(query: String, sort_id: String, status_id: String, offset: int) -> String:
	var q := PackedStringArray(["mode=0", "amount=%d" % PAGE, "offset=%d" % maxi(offset, 0), "sort=" + str(SORTS.get(sort_id, SORTS.plays))])
	var st := str(STATUSES.get(status_id, ""))
	if st != "":
		q.append("status=" + st)
	if query.strip_edges() != "":
		q.append("query=" + query.strip_edges().uri_encode())
	return base_url + "?" + "&".join(q)


func _on_search_done(req: int, result: int, code: int, body: PackedByteArray) -> void:
	if req != _req:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit(req, "つながりませんでした")
		return
	if code != 200:
		failed.emit(req, "検索できませんでした(%d)" % code)
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Array:
		failed.emit(req, "検索できませんでした")
		return
	var items: Array = []
	for s in data:
		if s is Dictionary:
			var it := parse_item(s)
			if not it.is_empty():
				items.append(it)
	results.emit(req, items, (data as Array).size() >= PAGE)


## API の 1 曲を、画面で使う形にする。osu!standard の譜面がなければ空。
## {id, title, artist, creator, status, plays, favs, bpm, length(秒。いちばん長い譜面), stars(osu!standard の譜面の★。易しい順), cover(画像の URL)}
static func parse_item(s: Dictionary) -> Dictionary:
	var id := int(s.get("id", 0))
	if id <= 0:
		return {}
	var stars: Array = []
	var length := 0
	var maps = s.get("beatmaps", [])
	if maps is Array:
		for b in maps:
			if b is Dictionary and int(b.get("mode_int", -1 if str(b.get("mode", "")) != "osu" else 0)) == 0:
				stars.append(float(b.get("difficulty_rating", 0.0)))
				length = maxi(length, int(b.get("total_length", 0)))
	if stars.is_empty():
		return {}
	stars.sort()
	var covers = s.get("covers", {})
	var cover := ""
	if covers is Dictionary:
		cover = str(covers.get("list@2x", covers.get("list", "")))
	if not cover.begins_with("https://assets.ppy.sh/"):   # 画像は osu! の画像の置き場からだけ取る
		cover = ""
	return {"id": id, "title": str(s.get("title", "")), "artist": str(s.get("artist", "")), "creator": str(s.get("creator", "")),
		"status": str(s.get("status", "")), "plays": int(s.get("play_count", 0)), "favs": int(s.get("favourite_count", 0)),
		"bpm": float(s.get("bpm", 0.0)), "length": length, "stars": stars, "cover": cover}


# --- ジャケット画像 ---

## その曲のジャケット(覚えていれば、すぐ返す。なければ null を返し、できたら cover_ready)。
func cover(set_id: int, url: String) -> Texture2D:
	if _cover_mem.has(set_id):
		return _cover_mem[set_id]
	var path := "%s/%d.jpg" % [COVER_DIR, set_id]
	if FileAccess.file_exists(path):
		var tex := _decode(FileAccess.get_file_as_bytes(path))
		if tex != null:
			_remember(set_id, tex)
			return tex
	if url == "" or _cover_busy.has(set_id):
		return null
	for w in _cover_wait:
		if int(w[0]) == set_id:
			return null
	_cover_wait.append([set_id, url])
	_pump_covers()
	return null


## まだ取りに行っていないジャケットを捨てる(新しく検索したとき。見えなくなった行の画像は要らない)。
func drop_pending_covers() -> void:
	_cover_wait.clear()


func _pump_covers() -> void:
	while _cover_busy.size() < COVER_PARALLEL and not _cover_wait.is_empty():
		var w: Array = _cover_wait.pop_front()
		var set_id := int(w[0])
		var h := HTTPRequest.new()
		h.timeout = 15.0
		h.body_size_limit = 2 * 1024 * 1024
		add_child(h)
		_cover_busy[set_id] = h
		h.request_completed.connect(func(result: int, code: int, _hd: PackedStringArray, body: PackedByteArray):
			_cover_busy.erase(set_id)
			h.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				var tex := _decode(body)
				if tex != null:
					DirAccess.make_dir_recursive_absolute(COVER_DIR)
					var f := FileAccess.open("%s/%d.jpg" % [COVER_DIR, set_id], FileAccess.WRITE)
					if f != null:
						f.store_buffer(body)
						f.close()
					_remember(set_id, tex)
					cover_ready.emit(set_id, tex)
			_pump_covers())
		if h.request(str(w[1]), PackedStringArray([USER_AGENT])) != OK:
			_cover_busy.erase(set_id)
			h.queue_free()


static func _decode(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 4:
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes) if bytes[0] == 0xFF else img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


func _remember(set_id: int, tex: Texture2D) -> void:
	_cover_mem[set_id] = tex
	_cover_order.append(set_id)
	while _cover_order.size() > COVER_MEM:
		_cover_mem.erase(_cover_order.pop_front())
