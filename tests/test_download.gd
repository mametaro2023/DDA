extends SceneTree
## 曲のダウンロード(song_download.gd)の確認。手元のミラーのふりをするサーバーを、先に動かしておく:
##   node tests/fake_mirror_server.js 8766 "22699 Len - U.N. Owen was her.osz"
##   godot --headless --path . --script tests/test_download.gd

const SongDownload = preload("res://scripts/song_download.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _run(dl, set_id: int, key: String, label: String) -> Dictionary:
	var box := {}
	dl.finished.connect(func(r): box["r"] = r)
	dl.start(set_id, key, label)
	var t0 := Time.get_ticks_msec()
	while not box.has("r") and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	return box.get("r", {"ok": false, "error": "timeout"})


func _init() -> void:
	await process_frame   # 木が動き出してから(HTTPRequest は、木の中でしか使えない)
	var src := "C:/Desktop/my_apps/DDA/22699 Len - U.N. Owen was her.osz"
	var l := OszLoader.new()
	l.open(src)
	var key: String = l.difficulties[1].md5
	l.close()
	var tmp := OS.get_temp_dir().path_join("dda_download_test").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(tmp)
	var base := "http://127.0.0.1:8766"

	# 404 → HTML(曲ではない)→ 本物、の順に試して、最後のもので取り込める
	var dl := SongDownload.new()
	root.add_child(dl)
	dl.dest_dir = tmp
	dl.mirrors = [{"name": "bad", "url": base + "/bad/%d"}, {"name": "html", "url": base + "/html/%d"}, {"name": "good", "url": base + "/d/%d"}]
	var r: Dictionary = await _run(dl, 22699, key, "22699 Len - U.N. Owen was her?")
	_check(r.ok and FileAccess.file_exists(str(r.path)), "失敗するミラーを飛ばして、3 番目から取り込める: %s" % str(r.get("path", r.get("error", ""))).get_file())
	_check(not dl.busy, "終わったら busy でない")
	_check(str(r.get("path", "")).get_file() == "22699 Len - U.N. Owen was her.osz", "ファイル名に使えない文字(?)は除く")
	var leftover := FileAccess.file_exists(ProjectSettings.globalize_path(SongDownload.WORK_DIR).path_join("22699 Len - U.N. Owen was her.osz"))
	_check(not leftover, "ダウンロード中の一時ファイルは残らない")

	# 部屋の譜面と違う中身は、断る
	var dl2 := SongDownload.new()
	root.add_child(dl2)
	dl2.dest_dir = tmp
	dl2.mirrors = [{"name": "good", "url": base + "/d/%d"}]
	var r2: Dictionary = await _run(dl2, 22699, "0".repeat(32), "wrongkey")
	_check(not r2.ok and str(r2.error).contains("内容が違います"), "部屋の譜面と違う曲は断る: %s" % str(r2.get("error", "")))

	# すべて失敗
	var dl3 := SongDownload.new()
	root.add_child(dl3)
	dl3.dest_dir = tmp
	dl3.mirrors = [{"name": "bad", "url": base + "/bad/%d"}, {"name": "html", "url": base + "/html/%d"}]
	var r3: Dictionary = await _run(dl3, 5, "", "none")
	_check(not r3.ok and str(r3.error).contains("bad") and str(r3.error).contains("html"), "すべて失敗したら、理由を並べて知らせる: %s" % str(r3.get("error", "")))

	if r.ok:
		DirAccess.remove_absolute(str(r.path))
	DirAccess.remove_absolute(tmp)
	print("test_download: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
