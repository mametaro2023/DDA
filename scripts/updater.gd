extends Node
## アプリ内アップデート。GitHub のリリース(mametaro2023/DDA)から、新しいバージョンを探して、ダウンロードして入れ替える。
##
## 流れ:
##   1. check()        … リリース一覧(API)を取り、いちばん新しいバージョンが今より新しいかを調べる(ベータ版のプレリリースも対象)。
##   2. start_download() … リリースの zip をダウンロードし、大きさ(と、API が教えるハッシュ)を確かめ、中の DDA.exe などを取り出す。
##   3. apply_and_quit() … 別のプロセス(PowerShell)を起動して、このアプリが終わるのを待ってから、exe を入れ替えて、新しいアプリを起動する。
##      入れ替えに失敗したら、元の exe を戻して、元のアプリを起動し直す(壊れた状態にならない)。songs フォルダなど、
##      ほかのファイルには触れない(入れ替えるのは DDA.exe と、README.txt・LICENSE-Godot.txt だけ)。
##
## 安全のため: ダウンロード先は、このリポジトリのリリースのアドレス(RELEASE_PREFIX)に限る。httpS で取得し、サイズ・SHA-256 を確かめ、
## zip の中の決まった名前のファイルだけを取り出す(パスの区切り・.. は使わない)。取り出した exe が Windows の実行ファイルの形でなければ断る。

const REPO := "mametaro2023/DDA"
const API_URL := "https://api.github.com/repos/mametaro2023/DDA/releases?per_page=10"
const RELEASE_PREFIX := "https://github.com/mametaro2023/DDA/releases/download/"
const PAGE_URL := "https://github.com/mametaro2023/DDA/releases"
const WORK_DIR := "user://update"
const ALLOWED := ["DDA.exe", "README.txt", "LICENSE-Godot.txt"]
const MIN_EXE_BYTES := 1000000

signal check_finished(info: Dictionary)
signal progress(fraction: float, text: String)
signal failed(message: String)
signal staged

## 確認先(テストでは、手元のサーバーに差し替える。そのときだけ https / 公式のアドレス以外も許す)
var api_url := API_URL
var allow_any_url := false
## 開発用: 書き出したアプリでなくても、入れ替えを行う(テスト用)
var force_apply := false

var current := ""
var info: Dictionary = {}       # 最後の確認の結果
var stage_dir := ""             # 取り出した新しいファイルの置き場(絶対パス)

var _http: HTTPRequest
var _downloading := false
var _dl_path := ""


func _ready() -> void:
	current = str(ProjectSettings.get_setting("application/config/version", "0"))


# --- バージョン比較 ---

## "v0.2.0-beta" → {nums: [0, 2, 0], pre: "beta"}。読めなければ nums が空。
static func parse_version(s: String) -> Dictionary:
	s = s.strip_edges().trim_prefix("v").trim_prefix("V")
	var pre := ""
	var dash := s.find("-")
	if dash >= 0:
		pre = s.substr(dash + 1)
		s = s.substr(0, dash)
	var nums: Array = []
	for p in s.split("."):
		if not p.is_valid_int():
			return {"nums": [], "pre": pre}
		nums.append(int(p))
	return {"nums": nums, "pre": pre}


## a と b の大小(a が新しければ 1、同じなら 0、古ければ -1)。数字を順に比べ、同じなら、-beta などの付かないほうが新しい。
static func compare(a: String, b: String) -> int:
	var pa := parse_version(a)
	var pb := parse_version(b)
	var na: Array = pa.nums
	var nb: Array = pb.nums
	for i in range(maxi(na.size(), nb.size())):
		var x: int = na[i] if i < na.size() else 0
		var y: int = nb[i] if i < nb.size() else 0
		if x != y:
			return 1 if x > y else -1
	if pa.pre == pb.pre:
		return 0
	if pa.pre == "":
		return 1
	if pb.pre == "":
		return -1
	return 1 if pa.pre > pb.pre else -1


static func is_newer(candidate: String, than: String) -> bool:
	return not parse_version(candidate).nums.is_empty() and compare(candidate, than) > 0


## このアプリが、自分を入れ替えられるか(書き出した Windows 版で、置き場所に書き込めるとき)。
func can_self_update() -> bool:
	if OS.get_name() != "Windows":
		return false
	if not (OS.has_feature("template") or force_apply):
		return false
	return _dir_writable(OS.get_executable_path().get_base_dir())


static func _dir_writable(dir: String) -> bool:
	var p := dir.path_join(".dda_write_test")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(p)
	return true


# --- 1. 確認 ---

func check() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_check_done)
	var err := _http.request(api_url, PackedStringArray(["User-Agent: DDA-updater", "Accept: application/vnd.github+json"]))
	if err != OK:
		_finish_check({"ok": false, "error": "接続できません"})


func _on_check_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_check({"ok": false, "error": "更新を確認できませんでした(%d)" % code})
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Array):
		_finish_check({"ok": false, "error": "更新の情報を読めませんでした"})
		return
	var best := {}
	for r in data:
		if not (r is Dictionary) or bool(r.get("draft", false)):
			continue
		var tag := str(r.get("tag_name", ""))
		if parse_version(tag).nums.is_empty():
			continue
		var asset := {}
		for a in r.get("assets", []):
			if a is Dictionary and str(a.get("name", "")).to_lower().ends_with(".zip"):
				asset = a
				break
		if asset.is_empty():
			continue
		if best.is_empty() or compare(tag, str(best.tag)) > 0:
			var digest = asset.get("digest")
			best = {"tag": tag, "version": tag.trim_prefix("v"), "notes": str(r.get("body", "")), "page": str(r.get("html_url", PAGE_URL)),
				"asset_url": str(asset.get("browser_download_url", "")), "asset_size": int(asset.get("size", 0)),
				"digest": str(digest) if digest != null else ""}
	if best.is_empty():
		_finish_check({"ok": true, "newer": false})
		return
	best["ok"] = true
	best["newer"] = is_newer(best.tag, current) and (allow_any_url or str(best.asset_url).begins_with(RELEASE_PREFIX))
	_finish_check(best)


func _finish_check(r: Dictionary) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	info = r
	check_finished.emit(r)


# --- 2. ダウンロード ---

func start_download() -> void:
	if _downloading or not bool(info.get("newer", false)):
		return
	var url := str(info.asset_url)
	if not allow_any_url and not url.begins_with(RELEASE_PREFIX):
		failed.emit("ダウンロード先が正しくありません")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_dl_path = ProjectSettings.globalize_path(WORK_DIR).path_join("download.zip")
	if FileAccess.file_exists(_dl_path):
		DirAccess.remove_absolute(_dl_path)
	_http = HTTPRequest.new()
	_http.download_file = _dl_path
	_http.timeout = 0.0
	_http.max_redirects = 8
	add_child(_http)
	_http.request_completed.connect(_on_download_done)
	if _http.request(url, PackedStringArray(["User-Agent: DDA-updater"])) != OK:
		_http.queue_free()
		_http = null
		failed.emit("ダウンロードを始められません")
		return
	_downloading = true
	progress.emit(0.0, "ダウンロード中…")


func _process(_delta: float) -> void:
	if _downloading and _http != null:
		var total := _http.get_body_size()
		if total <= 0:
			total = int(info.get("asset_size", 0))
		var got := _http.get_downloaded_bytes()
		if total > 0:
			progress.emit(clampf(float(got) / float(total), 0.0, 1.0), "ダウンロード中… %.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0])


func _on_download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("ダウンロードに失敗しました(%d)" % code)
		return
	progress.emit(1.0, "確認中…")
	# 大きさ・ハッシュの確認
	var f := FileAccess.open(_dl_path, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	if f != null:
		f.close()
	if int(info.get("asset_size", 0)) > 0 and size != int(info.asset_size):
		failed.emit("ダウンロードしたファイルの大きさが違います")
		return
	var digest := str(info.get("digest", ""))
	if digest.begins_with("sha256:") and FileAccess.get_sha256(_dl_path) != digest.trim_prefix("sha256:").to_lower():
		failed.emit("ダウンロードしたファイルが壊れています(ハッシュが一致しません)")
		return
	var err := _extract()
	if err != "":
		failed.emit(err)
		return
	progress.emit(1.0, "準備ができました")
	staged.emit()


## zip から、決まった名前のファイルだけを取り出す(ディレクトリは無視。.. などは使わない)。失敗したら理由、成功なら空文字。
func _extract() -> String:
	stage_dir = ProjectSettings.globalize_path(WORK_DIR).path_join("stage")
	_remove_dir(stage_dir)
	DirAccess.make_dir_recursive_absolute(stage_dir)
	var z := ZIPReader.new()
	if z.open(_dl_path) != OK:
		return "ダウンロードしたファイルを開けません"
	var found := {}
	for name in z.get_files():
		var n := str(name)
		if n.ends_with("/") or n.contains(".."):
			continue
		var base := n.get_file()
		if ALLOWED.has(base) and not found.has(base):
			var bytes := z.read_file(n)
			var w := FileAccess.open(stage_dir.path_join(base), FileAccess.WRITE)
			if w == null:
				z.close()
				return "ファイルを書き出せません"
			w.store_buffer(bytes)
			w.close()
			found[base] = bytes.size()
	z.close()
	if not found.has("DDA.exe") or int(found["DDA.exe"]) < MIN_EXE_BYTES:
		return "ダウンロードしたファイルに、アプリ本体(DDA.exe)がありません"
	var head := FileAccess.open(stage_dir.path_join("DDA.exe"), FileAccess.READ)
	var magic := head.get_buffer(2)
	head.close()
	if magic.size() < 2 or magic[0] != 0x4D or magic[1] != 0x5A:   # "MZ"
		return "アプリ本体が Windows の実行ファイルではありません"
	return ""


static func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# --- 3. 入れ替え ---

const APPLY_SCRIPT := """param([int]$ProcId, [string]$Dir, [string]$Stage, [string]$ExeName)
$ErrorActionPreference = 'Stop'
try { Wait-Process -Id $ProcId -Timeout 60 } catch {}
$exe = Join-Path $Dir $ExeName
$old = $exe + '.old'
$ok = $false
for ($i = 0; $i -lt 40; $i++) {
  try {
    if (Test-Path $old) { Remove-Item $old -Force }
    Move-Item $exe $old -Force
    Copy-Item (Join-Path $Stage 'DDA.exe') $exe -Force
    $ok = $true
    break
  } catch {
    if ((Test-Path $old) -and -not (Test-Path $exe)) { try { Move-Item $old $exe -Force } catch {} }
    Start-Sleep -Milliseconds 500
  }
}
if ($ok) {
  foreach ($n in @('README.txt', 'LICENSE-Godot.txt')) {
    $s = Join-Path $Stage $n
    if (Test-Path $s) { try { Copy-Item $s (Join-Path $Dir $n) -Force } catch {} }
  }
} elseif ((Test-Path $old) -and -not (Test-Path $exe)) {
  Move-Item $old $exe -Force
}
Start-Process -FilePath $exe
"""


## 入れ替えを別のプロセスに任せて、このアプリを終了する(新しいアプリが起動する)。
func apply_and_quit() -> void:
	if stage_dir == "" or not FileAccess.file_exists(stage_dir.path_join("DDA.exe")):
		failed.emit("更新のファイルがありません")
		return
	var script := ProjectSettings.globalize_path(WORK_DIR).path_join("apply.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		failed.emit("更新の準備ができません")
		return
	f.store_string(APPLY_SCRIPT)
	f.close()
	var exe := OS.get_executable_path()
	var pid := OS.create_process("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script,
		"-ProcId", str(OS.get_process_id()), "-Dir", exe.get_base_dir(), "-Stage", stage_dir, "-ExeName", exe.get_file()])
	if pid <= 0:
		failed.emit("更新を始められません")
		return
	get_tree().quit()


## 起動時の後片付け: 前回の更新で残った古い exe と、作業フォルダを消す。
static func cleanup_after_update() -> void:
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	var work := ProjectSettings.globalize_path(WORK_DIR)
	_remove_dir(work.path_join("stage"))
	for n in ["download.zip", "apply.ps1"]:
		if FileAccess.file_exists(work.path_join(n)):
			DirAccess.remove_absolute(work.path_join(n))
