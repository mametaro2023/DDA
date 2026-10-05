extends RefCounted
## プレイリスト(上のプレイヤーで、曲を決めた順に流す)。UI を持たない: 持っている曲の一覧の保存と、「いま何番目を流しているか」の進め方だけ。
## ・プレイリストは何個でも作れ、それぞれが曲の並び({path, title, artist})を持つ。user://playlists.json に保存する(曲そのものは持たない)。
## ・「流している」状態(playing)は、保存しない。流している間は、上のプレイヤーの前・次・曲が終わったときが、このプレイリストの順に進む
##   (タイトルの背景曲・選曲の試聴のどちらでも。実際に流すのは画面の仕事 = now_playing.gd の play_cb)。
## ・シャッフル(いつでも切り替え。いま流している曲は先頭に残る)とリピート(全曲 / 1 曲 / しない)。
## ・流している間に、プレイリストに入っていない曲を選曲で選ぶと、プレイリストの流しは止まる(note_song)。

const SongLibrary = preload("res://scripts/song_library.gd")

const REPEAT_ALL := 0
const REPEAT_ONE := 1
const REPEAT_OFF := 2
const MAX_NAME := 20
const MAX_LISTS := 50
const MAX_TRACKS := 2000

## 保存先(テストでは差し替える)
static var file_path := "user://playlists.json"

static var lists: Array = []   # [{name, tracks: [{path, title, artist}]}]
static var selected := 0       # パネルで開いているプレイリスト
static var shuffle := false
static var repeat := REPEAT_ALL
## 変わるたびに増える(表示の作り直し用)。rev = 一覧の中身が変わった / state_rev = 流している位置が変わった
static var rev := 0
static var state_rev := 0

static var playing := -1       # 流しているプレイリストの番号(-1: 流していない)
static var _order: Array = []  # 流す順(トラックの番号)
static var _oi := 0            # _order の中の、いまの位置
static var _loaded := false


# --- 保存 ---

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	lists = []
	if not FileAccess.file_exists(file_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not (data is Dictionary):
		return
	for l in data.get("lists", []):
		if not (l is Dictionary):
			continue
		var tracks: Array = []
		for t in l.get("tracks", []):
			if t is Dictionary and str(t.get("path", "")) != "":
				tracks.append({"path": str(t.path), "title": str(t.get("title", "")), "artist": str(t.get("artist", ""))})
		lists.append({"name": str(l.get("name", "")).left(MAX_NAME), "tracks": tracks})
	selected = clampi(int(data.get("selected", 0)), 0, maxi(lists.size() - 1, 0))
	shuffle = bool(data.get("shuffle", false))
	repeat = clampi(int(data.get("repeat", REPEAT_ALL)), REPEAT_ALL, REPEAT_OFF)


static func save() -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"lists": lists, "selected": selected, "shuffle": shuffle, "repeat": repeat}))
	f.close()


## 読み込み直す(テスト用)
static func reset() -> void:
	_loaded = false
	lists = []
	selected = 0
	shuffle = false
	repeat = REPEAT_ALL
	playing = -1
	_order = []
	_oi = 0
	rev += 1
	state_rev += 1


static func _changed() -> void:
	rev += 1
	save()


# --- プレイリストの編集 ---

## 新しいプレイリストを作る。名前が空なら「プレイリスト N」。作ったものを開く。作れなければ -1。
static func create(name := "") -> int:
	ensure_loaded()
	if lists.size() >= MAX_LISTS:
		return -1
	name = name.strip_edges().left(MAX_NAME)
	if name == "":
		var n := lists.size() + 1
		while _name_taken("プレイリスト %d" % n):
			n += 1
		name = "プレイリスト %d" % n
	lists.append({"name": name, "tracks": []})
	selected = lists.size() - 1
	_changed()
	return selected


static func _name_taken(name: String) -> bool:
	for l in lists:
		if l.name == name:
			return true
	return false


static func rename(i: int, name: String) -> void:
	ensure_loaded()
	name = name.strip_edges().left(MAX_NAME)
	if i < 0 or i >= lists.size() or name == "":
		return
	lists[i].name = name
	_changed()


static func delete(i: int) -> void:
	ensure_loaded()
	if i < 0 or i >= lists.size():
		return
	if playing == i:
		stop()
	elif playing > i:
		playing -= 1
	lists.remove_at(i)
	selected = clampi(selected if selected < i else selected - 1, 0, maxi(lists.size() - 1, 0))
	_changed()


## 曲を足す(同じ曲がもう入っていたら足さず false)。
static func add(i: int, path: String, title: String, artist: String) -> bool:
	ensure_loaded()
	if i < 0 or i >= lists.size() or path == "" or index_of(i, path) >= 0 or lists[i].tracks.size() >= MAX_TRACKS:
		return false
	lists[i].tracks.append({"path": path, "title": title, "artist": artist})
	if playing == i:
		_order.append(lists[i].tracks.size() - 1)   # 流す順の最後に足す(いまの曲・順は、そのまま)
		state_rev += 1
	_changed()
	return true


static func remove_track(i: int, t: int) -> void:
	ensure_loaded()
	if i < 0 or i >= lists.size() or t < 0 or t >= lists[i].tracks.size():
		return
	var cur_path := _current_path() if playing == i else ""
	var was_current := cur_path != "" and SongLibrary.norm(cur_path) == SongLibrary.norm(str(lists[i].tracks[t].path))
	lists[i].tracks.remove_at(t)
	if playing == i:
		if lists[i].tracks.is_empty():
			stop()
		else:
			_rebuild_order("" if was_current else cur_path, t)
	_changed()


## 曲を d(-1 = 前へ・1 = あとへ)だけ動かす。
static func move_track(i: int, t: int, d: int) -> void:
	ensure_loaded()
	if i < 0 or i >= lists.size():
		return
	var tracks: Array = lists[i].tracks
	var to := t + d
	if t < 0 or t >= tracks.size() or to < 0 or to >= tracks.size():
		return
	var cur_path := _current_path() if playing == i else ""
	var tmp = tracks[t]
	tracks[t] = tracks[to]
	tracks[to] = tmp
	if playing == i:
		_rebuild_order(cur_path, 0)
	_changed()


## プレイリスト i の中の曲 path の番号(なければ -1)。
static func index_of(i: int, path: String) -> int:
	if i < 0 or i >= lists.size():
		return -1
	var key := SongLibrary.norm(path)
	var tracks: Array = lists[i].tracks
	for t in range(tracks.size()):
		if SongLibrary.norm(str(tracks[t].path)) == key:
			return t
	return -1


# --- 流す ---

static func is_active() -> bool:
	return playing >= 0 and playing < lists.size() and not (lists[playing].tracks as Array).is_empty() and _oi >= 0 and _oi < _order.size()


## いま流している曲({path, title, artist})。流していなければ空。
static func current() -> Dictionary:
	if not is_active():
		return {}
	return lists[playing].tracks[_order[_oi]]


## 流している曲の、プレイリストの中の番号(流していなければ -1)。
static func current_index() -> int:
	return int(_order[_oi]) if is_active() else -1


## プレイリスト i の t 番目から流し始める(順番どおりなら、そこから続き・シャッフルなら、その曲を先頭にした順)。流す曲を返す(空なら流せない)。
static func start(i: int, t := 0) -> Dictionary:
	ensure_loaded()
	if i < 0 or i >= lists.size() or (lists[i].tracks as Array).is_empty():
		return {}
	playing = i
	var tracks: Array = lists[i].tracks
	_build_order(clampi(t, 0, tracks.size() - 1))
	state_rev += 1
	return current()


static func stop() -> void:
	if playing == -1:
		return
	playing = -1
	_order = []
	_oi = 0
	state_rev += 1


## 順を作る: first の曲を、いまの位置にする。シャッフルなら first を先頭に、残りを混ぜる。
static func _build_order(first: int) -> void:
	var n: int = (lists[playing].tracks as Array).size()
	_order = []
	if shuffle:
		var rest: Array = []
		for k in range(n):
			if k != first:
				rest.append(k)
		rest.shuffle()
		_order = [first] + rest
		_oi = 0
	else:
		for k in range(n):
			_order.append(k)
		_oi = first


static func _current_path() -> String:
	return str(current().get("path", ""))


## 曲の入れ替え・削除のあと、順を作り直す。cur_path = 変える前に流していた曲(そこから続ける)。空なら(流していた曲がなくなった)、fallback の位置の曲へ。
static func _rebuild_order(cur_path: String, fallback: int) -> void:
	var tracks: Array = lists[playing].tracks
	var first := clampi(fallback, 0, tracks.size() - 1)
	if cur_path != "":
		first = maxi(index_of(playing, cur_path), 0)
	_build_order(first)
	state_rev += 1


## 次(d = 1)・前(d = -1)の曲へ進めて、その曲を返す。auto = 曲が終わって自然に進むとき(リピート 1 曲 = 同じ曲・リピートなし = 最後で止まる)。
## 止まったとき・流していないときは空。
static func advance(d: int, auto := false) -> Dictionary:
	if not is_active():
		return {}
	if auto and repeat == REPEAT_ONE:
		state_rev += 1
		return current()
	var n := _order.size()
	var ni := _oi + d
	if ni >= n or ni < 0:
		if auto and repeat == REPEAT_OFF:
			stop()
			return {}
		if shuffle and ni >= n:   # 1 周したら、混ぜ直す(つなぎ目で同じ曲が続かないようにする)
			var last := int(_order[n - 1])
			_order.shuffle()
			if n > 1 and int(_order[0]) == last:
				var swap_i := 1 + randi() % (n - 1)
				var tmp = _order[0]
				_order[0] = _order[swap_i]
				_order[swap_i] = tmp
		ni = posmod(ni, n)
	_oi = ni
	state_rev += 1
	return current()


## 選曲などで、ある曲(path)を流し始めた。流している最中で、その曲がこのプレイリストに入っていればその位置へ、入っていなければ流しを止める。
static func note_song(path: String) -> void:
	if not is_active():
		return
	var t := index_of(playing, path)
	if t < 0:
		stop()
		return
	if int(_order[_oi]) == t:
		return
	var at := _order.find(t)
	if at >= 0:
		_oi = at
	state_rev += 1


static func toggle_shuffle() -> void:
	ensure_loaded()
	shuffle = not shuffle
	if is_active():
		_build_order(int(_order[_oi]))
		state_rev += 1
	save()
	rev += 1


static func cycle_repeat() -> void:
	ensure_loaded()
	repeat = (repeat + 1) % 3
	save()
	rev += 1


static func repeat_label() -> String:
	return ["全曲", "1曲", "なし"][repeat]
