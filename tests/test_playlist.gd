extends SceneTree
## プレイリスト(scripts/playlist.gd)の確認: 編集・保存・順に進める・シャッフル・リピート・選曲で別の曲を選んだとき。
## godot --headless --path . --script tests/test_playlist.gd

const Playlist = preload("res://scripts/playlist.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _fill(n: int) -> int:
	var i := Playlist.create("テスト")
	for k in range(n):
		Playlist.add(i, "C:/songs/s%d.osz" % k, "曲%d" % k, "A")
	return i


func _init() -> void:
	Playlist.file_path = "user://test_playlists.json"
	DirAccess.remove_absolute(Playlist.file_path)
	Playlist.reset()
	Playlist.ensure_loaded()
	var i := _fill(4)
	_check(Playlist.lists.size() == 1 and Playlist.lists[0].tracks.size() == 4, "作って 4 曲足せる")
	_check(not Playlist.add(i, "c:\\SONGS\\S1.osz", "x", "x"), "同じ曲(書き方が違っても)は足せない")
	_check(Playlist.create("") == 1 and Playlist.lists[1].name == "プレイリスト 2", "名前が空なら「プレイリスト N」")

	# 順に進める
	var t: Dictionary = Playlist.start(i, 1)
	_check(t.title == "曲1" and Playlist.is_active(), "2 曲目から流し始める")
	_check(Playlist.advance(1, true).title == "曲2" and Playlist.advance(1, true).title == "曲3", "次へ進む")
	_check(Playlist.advance(1, true).title == "曲0", "全曲リピート: 最後の次は、頭へ戻る")
	_check(Playlist.advance(-1).title == "曲3", "前へ(頭の前は、最後へ)")
	Playlist.repeat = Playlist.REPEAT_ONE
	_check(Playlist.advance(1, true).title == "曲3" and Playlist.advance(1).title == "曲0", "1 曲リピート: 自然に終わると同じ曲・手で次へは進む")
	Playlist.repeat = Playlist.REPEAT_OFF
	Playlist.start(i, 3)
	_check(Playlist.advance(1, true).is_empty() and not Playlist.is_active(), "リピートなし: 最後の曲が終わったら止まる")
	Playlist.start(i, 3)
	_check(Playlist.advance(1).title == "曲0", "リピートなしでも、手で次へ押せば頭へ戻る")
	Playlist.repeat = Playlist.REPEAT_ALL

	# シャッフル
	Playlist.toggle_shuffle()
	Playlist.start(i, 2)
	var seen := {Playlist.current().title: true}
	for k in range(3):
		seen[Playlist.advance(1, true).title] = true
	_check(seen.size() == 4 and Playlist.current().title != "", "シャッフル: 1 周で全部の曲が 1 回ずつ出る")
	_check(Playlist.start(i, 2).title == "曲2", "シャッフル: 選んだ曲から始まる")
	for k in range(4):
		Playlist.advance(1, true)
	_check(Playlist.is_active(), "シャッフル: 1 周したあとも続く")
	Playlist.toggle_shuffle()
	_check(Playlist.current_index() >= 0, "シャッフルを切っても、いまの曲を保つ")

	# 選曲で選んだ曲
	Playlist.start(i, 0)
	Playlist.note_song("C:/songs/s2.osz")
	_check(Playlist.current().title == "曲2", "選曲で、入っている別の曲を選ぶと、そこが現在位置になる")
	Playlist.note_song("C:/songs/other.osz")
	_check(not Playlist.is_active(), "入っていない曲を選ぶと、流しは止まる")

	# 編集中の位置
	Playlist.start(i, 1)
	Playlist.move_track(i, 1, 1)
	_check(Playlist.current().title == "曲1" and Playlist.lists[i].tracks[2].title == "曲1", "並べ替えても、流している曲は変わらない")
	Playlist.remove_track(i, 0)
	_check(Playlist.current().title == "曲1", "別の曲を消しても、流している曲は変わらない")
	Playlist.remove_track(i, Playlist.current_index())
	_check(Playlist.is_active() and Playlist.current().title != "曲1", "流している曲を消すと、同じ位置の曲へ移る")
	Playlist.delete(0)
	_check(not Playlist.is_active() and Playlist.lists.size() == 1, "流しているプレイリストを消すと、止まる")

	# 保存
	Playlist.shuffle = true
	Playlist.repeat = Playlist.REPEAT_ONE
	Playlist.add(0, "C:/songs/z.osz", "Z", "Q")
	Playlist.save()
	Playlist.reset()
	Playlist.ensure_loaded()
	_check(Playlist.lists.size() == 1 and Playlist.lists[0].tracks.size() == 1 and Playlist.lists[0].tracks[0].title == "Z" and Playlist.shuffle and Playlist.repeat == Playlist.REPEAT_ONE, "保存して、読み直せる")
	DirAccess.remove_absolute(Playlist.file_path)
	print("test_playlist: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
