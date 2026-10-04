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
	# 難易度順: 曲ではなく、譜面を 1 つずつ Lv の低い順に並べる
	b.query = ""
	b.sort_mode = "diff"
	var charts := {
		0: [["z1", "Easy", 2.0], ["z2", "Hard", 5.0]],
		1: [["a1", "Normal", 3.5], ["a2", "Insane", 5.0]],
		2: [],   # まだ難易度が分かっていない曲
		3: [["l1", "Lv", 3.504]],
	}
	b.charts_of = func(i: int) -> Array: return charts[i]
	_check(b.chart_mode() and not b.chart_view().is_empty(), "難易度順のとき、chart_mode() が true")
	var ids := b.chart_view().map(func(c): return c.id)
	_check(ids == ["z1", "l1", "a1", "a2", "z2"], "譜面ごとに、Lv の低い順(分からない曲は出ない): %s" % [ids])
	var first: Dictionary = b.chart_view()[0]
	_check(first.s == 0 and first.name == "Easy" and absf(first.lv - 2.0) < 1e-9, "要素は {曲の番号, 識別子, 難易度名, Lv}")
	_check(b.chart_view()[1].id == "l1" and b.chart_view()[2].id == "a1", "同じ Lv(画面に出る小数 2 桁で同じ)は、曲名順(Alpha → alpha Beat)")
	_check(b.chart_view()[3].id == "a2" and b.chart_view()[4].id == "z2", "同じ Lv の 2 譜面も、曲名順(alpha Beat → Zeta)")
	b.query = "zeta"
	_check(b.chart_view().map(func(c): return c.id) == ["z1", "z2"], "検索は、難易度順にも効く(合う曲の譜面だけ)")
	# 長さ順: 短い順。長さが分からない曲(0 以下)は後ろ。同じ長さは曲名順
	b.query = ""
	b.sort_mode = "length"
	var lens := {0: 140.0, 1: 95.0, 2: -1.0, 3: 95.9}
	b.length_of = func(i: int) -> float: return lens[i]
	_check(b.view() == [3, 1, 0, 2], "長さ順(短い順。長さが分からない曲は後ろ。秒未満は切り捨てて比べ、同じ長さなら曲名順): %s" % [b.view()])
	lens[2] = 60.0
	_check(b.view() == [2, 3, 1, 0], "長さが分かったら、その位置に入る")
	b.query = "alpha"
	_check(b.view() == [3, 1], "検索は、長さ順にも効く。同じ長さ(95 秒)は、曲名順(Alpha → alpha Beat)")
	b.query = ""
	b.sort_mode = "title"
	_check(not b.chart_mode() and b.view() == [3, 1, 2, 0], "ほかの並び替えでは、曲ごとの一覧のまま")
	print("test_song_view: ","OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
