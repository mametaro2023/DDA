extends SceneTree
## 選曲の検索・並び替え(song_browser.gd の view / matches / step_in_view)の確認。
## godot --headless --path . --script tests/test_song_view.gd

const SongBrowser = preload("res://scripts/song_browser.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var b := SongBrowser.new()
	b.songs = [
		{"title": "Zeta", "artist": "Mika", "mtime": 100},
		{"title": "alpha Beat", "artist": "Zed", "mtime": 300},
		{"title": "Beta", "artist": "Aya", "mtime": 200},
		{"title": "Alpha", "artist": "Zed", "mtime": 300},
	]
	_check(b.view() == [3, 1, 2, 0], "曲名順(大文字小文字は区別しない。同じなら、アーティスト → 元の番号)")
	b.sort_mode = "artist"
	_check(b.view() == [2, 0, 3, 1], "アーティスト順(同じなら曲名)")
	b.sort_mode = "added"
	_check(b.view() == [1, 3, 2, 0], "追加順(新しい順。同じ時刻なら元の番号)")
	b.sort_mode = "rank"
	var fake := {"z": {"rank": "A", "score": 900000}, "ab": {"rank": "SS", "score": 1000000}, "be": {"rank": "A", "score": 950000}}
	for k in range(b.songs.size()):
		b.songs[k]["ids"] = [["z", "ab", "be", "al"][k]]
	b.best_of = func(ids: Array) -> Dictionary: return fake.get(str(ids[0]), {})
	_check(b.view() == [1, 2, 0, 3], "ランク順(高いランク → 同じなら高いスコア → 記録のない曲は後ろ)")
	b.sort_mode = "title"
	b.query = "ALPHA"
	_check(b.view() == [3, 1], "検索: 曲名に含まれる(大文字小文字を区別しない)")
	b.query = "z e d"
	_check(b.view() == [3, 1], "検索: アーティストに含まれる(空白は区別しない)")
	b.query = "nothing"
	_check(b.view().is_empty() and b.step_in_view(0, 1) == -1, "検索: 合う曲がなければ空")
	b.query = ""
	_check(b.step_in_view(3, 1) == 1 and b.step_in_view(3, -1) == 3 and b.step_in_view(0, 1) == 0, "表示順で、次・前へ進む(端で止まる)")
	b.query = "beta"
	_check(b.step_in_view(0, 1) == 2 and b.step_in_view(0, -1) == 2, "表示にない番号からは、先頭(次)・末尾(前)の表示中の曲")
	print("test_song_view: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
