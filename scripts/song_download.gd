extends Node
## 曲(.osz)のダウンロードと取り込み(マルチプレイで、部屋の曲を持っていないとき)。
## osu! の公式サイトはログインが要るので、ログイン不要のミラーサイト(曲の ID だけで取れる)を順に試す。osu.direct を最優先にする(たいていの曲が取れるため)。
## ダウンロードしたファイルは、zip として読めること・osu!standard の譜面を含むこと・(指定があれば)部屋の譜面と同じ中身の難易度を含むことを確かめてから、
## ユーザーデータの songs に取り込む(OszImport)。確かめられなければ捨てて、次のミラーを試す。ボタンを押したときだけ通信する。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const OszImport = preload("res://scripts/osz_import.gd")

signal progress(fraction: float, text: String)
## 結果: {ok, path, title} または {ok=false, error}
signal finished(result: Dictionary)

## ミラーの一覧。url の %d に曲の ID が入る(テストでは差し替える)
var mirrors: Array = [
	{"name": "osu.direct", "url": "https://osu.direct/api/d/%d"},
	{"name": "Nerinyan", "url": "https://api.nerinyan.moe/d/%d?noVideo=true"},
	{"name": "catboy.best", "url": "https://catboy.best/d/%dn"},
]
const MAX_BYTES := 150 * 1024 * 1024
const MIN_BYTES := 2000
const WORK_DIR := "user://download"
const USER_AGENT := "User-Agent: DDA-danmaku-dodger (+https://github.com/mametaro2023/DDA)"

var busy := false
## 取り込み先(空なら、ユーザーデータの songs。テスト用に差し替えられる)
var dest_dir := ""

var _http: HTTPRequest
var _set_id := 0
var _want := ""
var _label := ""
var _i := 0
var _path := ""
var _errors: Array = []


## set_id: 曲の ID。want_key: 部屋の譜面の識別子(Beatmap.md5。空なら照合しない)。label: 保存する名前("ID 作者 - 曲名")。
func start(set_id: int, want_key: String, label: String) -> void:
	if busy:
		return
	busy = true
	_set_id = set_id
	_want = want_key
	_label = _safe_name(label if label != "" else str(set_id))
	_i = 0
	_errors.clear()
	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	_next()


func cancel() -> void:
	if not busy:
		return
	_stop_http()
	_remove_partial()
	busy = false


func _exit_tree() -> void:
	cancel()


func _next() -> void:
	if _i >= mirrors.size():
		_finish({"ok": false, "error": "ダウンロードできませんでした(%s)" % ", ".join(_errors) if not _errors.is_empty() else "ダウンロードできませんでした"})
		return
	var m: Dictionary = mirrors[_i]
	progress.emit(0.0, "%s に接続しています…" % m.name)
	_path = ProjectSettings.globalize_path(WORK_DIR).path_join(_label + ".osz")
	_stop_http()
	_http = HTTPRequest.new()
	_http.download_file = _path
	_http.body_size_limit = MAX_BYTES
	_http.max_redirects = 8
	_http.timeout = 180.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var err := _http.request(str(m.url) % _set_id, PackedStringArray([USER_AGENT]))
	if err != OK:
		_fail("接続できません")


func _process(_delta: float) -> void:
	if not busy or _http == null:
		return
	var got := _http.get_downloaded_bytes()
	var total := _http.get_body_size()
	var name: String = mirrors[mini(_i, mirrors.size() - 1)].name
	if total > 0:
		progress.emit(clampf(float(got) / float(total), 0.0, 1.0), "%s からダウンロード中  %.1f / %.1f MB" % [name, got / 1048576.0, total / 1048576.0])
	elif got > 0:
		progress.emit(0.0, "%s からダウンロード中  %.1f MB" % [name, got / 1048576.0])


func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if not busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("通信に失敗しました" if result != HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED else "ファイルが大きすぎます")
		return
	if code != 200:
		_fail("見つかりませんでした" if code == 404 else "エラー(%d)" % code)
		return
	var why := _check(_path)
	if why != "":
		_fail(why)
		return
	var r := OszImport.import_file(_path, dest_dir)
	_remove_partial()
	if not r.ok:
		_errors.append(str(r.error))
		_i += 1
		_next()
		return
	_finish(r)


## ダウンロードしたファイルの確認。問題がなければ空文字。
func _check(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "保存できませんでした"
	var size := f.get_length()
	var head := f.get_buffer(2)
	f.close()
	if size < MIN_BYTES or head.size() < 2 or head[0] != 0x50 or head[1] != 0x4B:   # 「PK」(zip)で始まる
		return "曲のファイルではありません"
	var l := OszLoader.new()
	if not l.open(path):
		return "曲として読めません"
	var ok := _want == ""
	for bm in l.difficulties:
		if bm.md5 == _want:
			ok = true
	l.close()
	return "" if ok else "部屋の譜面と内容が違います"


func _fail(msg: String) -> void:
	_errors.append("%s: %s" % [mirrors[_i].name, msg])
	_remove_partial()
	_i += 1
	_next()


func _finish(result: Dictionary) -> void:
	_stop_http()
	busy = false
	finished.emit(result)


func _stop_http() -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
		_http = null


func _remove_partial() -> void:
	if _path != "" and FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


## ファイル名に使えない文字を除く。
static func _safe_name(s: String) -> String:
	var out := s
	for c in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(c, "")
	out = out.strip_edges().left(120)
	return out if out != "" else "song"
