extends SceneTree
## osu! の Songs フォルダ(.osz を展開した曲のフォルダ)を、そのまま曲として読む機能の単体テスト。
## godot --headless --path . --script tests/test_osu_folder.gd

const SL = preload("res://scripts/song_library.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _rm(d: String) -> void:
	if not DirAccess.dir_exists_absolute(d):
		return
	for sub in DirAccess.get_directories_at(d):
		_rm(d.path_join(sub))
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	DirAccess.remove_absolute(d)


func _sorted(a: Array) -> Array:
	a = a.duplicate()
	a.sort()
	return a


## .osz を展開して、osu! の Songs の中の 1 曲のフォルダと同じものを作る。
func _extract(osz: String, dest: String) -> void:
	DirAccess.make_dir_recursive_absolute(dest)
	var z := ZIPReader.new()
	z.open(osz)
	for f in z.get_files():
		var out := dest.path_join(f)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var w := FileAccess.open(out, FileAccess.WRITE)
		w.store_buffer(z.read_file(f))
		w.close()
	z.close()


func _init() -> void:
	# osu!.<ユーザー名>.cfg の BeatmapDirectory
	_check(SL.beatmap_directory("A = 1\nBeatmapDirectory = D:\\games\\osu\\Songs\r\nB = 2", "C:/x/osu!") == "D:/games/osu/Songs", "cfg: 絶対パスの BeatmapDirectory")
	_check(SL.beatmap_directory("BeatmapDirectory = Songs", "C:/x/osu!") == "C:/x/osu!/Songs", "cfg: 相対パスは osu! のフォルダからの位置")
	_check(SL.beatmap_directory("A = 1", "C:/x/osu!") == "" and SL.beatmap_directory("BeatmapDirectory =", "C:/x/osu!") == "", "cfg: なければ・空なら空")
	# 設定が切れていれば使わない
	SL.apply_osu_settings({"osu_songs": false, "osu_songs_dir": "C:/nowhere"})
	_check(SL.osu_dir == "" and SL.osu_song_dirs().is_empty(), "切ってあれば、Songs フォルダは使わない")

	var osz := ""
	for p in SL.find_all():
		if str(p).to_lower().ends_with(".osz"):
			osz = p
			break
	if osz == "":
		print("(試せる .osz がないので、フォルダの読み込みの確認は省略)")
	else:
		var tmp := OS.get_temp_dir().path_join("dda_osu_folder_test").replace("\\", "/")
		_rm(tmp)   # 前の実行の残りを消す
		var songs := tmp.path_join("Songs")
		DirAccess.make_dir_recursive_absolute(songs)
		var one := songs.path_join(osz.get_file().get_basename())
		_extract(osz, one)
		DirAccess.make_dir_recursive_absolute(songs.path_join("not a map"))   # .osu のないフォルダは、曲として数えない
		var w := FileAccess.open(songs.path_join("not a map/readme.txt"), FileAccess.WRITE)
		w.store_string("x")
		w.close()

		# フォルダと .osz で、同じ曲として読める
		var lz := OszLoader.new()
		var lf := OszLoader.new()
		_check(lz.open(osz) and lf.open(one), "フォルダを開ける(%s)" % one.get_file())
		_check(lf.difficulties.size() == lz.difficulties.size() and lf.difficulties.size() > 0, "譜面の数が .osz と同じ(%d)" % lf.difficulties.size())
		_check(lf.difficulties[0].md5 == lz.difficulties[0].md5 and lf.difficulties[0].title == lz.difficulties[0].title, "譜面の識別子・題名が .osz と同じ")
		_check(lf.difficulties[0].beatmapset_id == lz.difficulties[0].beatmapset_id, "曲 ID も同じ(フォルダ名の先頭の数字でも読める)")
		var bm = lf.difficulties[0]
		var a1 := lf.read_file(bm.audio_filename)
		_check(not a1.is_empty() and a1 == lz.read_file(bm.audio_filename), "音声の中身が同じ(%s)" % bm.audio_filename)
		_check(lf.has_file(bm.audio_filename.to_upper()), "ファイル名の大文字小文字は区別しない")
		_check(not lf.has_file("no_such_file.mp3") and not lf.has_file("../x.mp3") and lf.read_file("zzz/none.png").is_empty(), "ないファイル・親の階層は読まない")
		if bm.background != "":
			_check(lf.load_image_data(bm.background) != null, "背景画像を読める(%s)" % bm.background)
		_check(lf.load_audio(bm.audio_filename) != null, "音声を AudioStream にできる")
		lz.close()
		lf.close()

		# 曲の索引
		var inf_z: Dictionary = SL.info(osz)
		var inf_f: Dictionary = SL.info(one)
		_check(inf_f.ok and inf_f.md5 == inf_z.md5 and inf_f.title == inf_z.title and _sorted(inf_f.ids.keys()) == _sorted(inf_z.ids.keys()), "索引(info): フォルダも .osz と同じ要約になる(%s)" % inf_f.title)
		_check(not SL.info(songs.path_join("not a map")).ok, ".osu のないフォルダは曲ではない")

		# 一覧に出る(裏のスレッドで調べる。待たずに返ることも確かめる)
		SL.apply_osu_settings({"osu_songs": true, "osu_songs_dir": songs})
		_check(SL.osu_dir == songs and SL.osu_song_dirs().is_empty(), "設定を入れた直後は、まだ何もない(待たずに返る)")
		SL.start_osu_warmup()
		_wait_warm()
		var dirs := SL.osu_song_dirs()
		_check(dirs.size() == 1 and str(dirs[0]) == one, "Songs の中の曲だけが数えられる(%d 曲。.osu のないフォルダは数えない)" % dirs.size())
		_check(SL.find_all().has(one), "find_all に、フォルダの曲が加わる")
		_check(SL.find_by_md5(inf_f.md5).size() > 0, "識別子から曲を探せる(マルチプレイの「持っている」判定)")
		var ready := SL.take_ready(0, 10)
		_check(ready.size() == 1 and ready[0].path == one and ready[0].info.ok and SL.take_ready(1, 10).is_empty(), "take_ready: できた曲を順に取り出せる")
		var n := SL.find_all().size()
		DirAccess.make_dir_recursive_absolute(songs.path_join("second"))
		var bw := FileAccess.open(songs.path_join("second/b.osu"), FileAccess.WRITE)
		bw.store_string("osu file format v14\n")
		bw.close()
		SL.start_osu_warmup()   # 増えた曲だけ調べ直す
		_wait_warm()
		_check(SL.warm_progress().done == 3 and SL.find_all().size() == n, "調べ直しても、見終えた曲は数え直さない(読めない曲は一覧に出ない)")
		SL.apply_osu_settings({"osu_songs": false})
		_check(not SL.find_all().has(one) and SL.osu_song_dirs().is_empty(), "切ると、一覧から消える")
		# 設定を変えている途中で始めて止めても、壊れない
		SL.apply_osu_settings({"osu_songs": true, "osu_songs_dir": songs})
		SL.start_osu_warmup()
		SL.stop_warmup()
		_check(SL.info(one).ok, "裏の作業を始めてすぐ止めても、索引は壊れない")
		_rm(tmp)

	# 実際の osu! の Songs フォルダ(この PC にあれば。読むだけで、何も書き換えない)
	var real := SL.detect_osu_songs()
	if real != "":
		SL.apply_osu_settings({"osu_songs": true, "osu_songs_dir": ""})
		_check(SL.osu_dir == real, "標準の場所から Songs フォルダを見つけた: " + real)
		SL.start_osu_warmup()
		# 調べている間も、主スレッドの呼び出しが止まらない(画面を止めない)
		var t2 := Time.get_ticks_msec()
		var worst := 0
		var polls := 0
		var cursor := 0
		while SL.warm_progress().running:
			var c0 := Time.get_ticks_usec()
			SL.take_ready(cursor, 10)
			SL.osu_song_dirs()
			SL.find_by_md5("0".repeat(32))
			SL.warm_progress()
			worst = maxi(worst, Time.get_ticks_usec() - c0)
			polls += 1
			OS.delay_msec(10)
		print("  裏の準備(", SL.warm_progress().total, " フォルダ): ", Time.get_ticks_msec() - t2, " ms / 主スレッドの呼び出し ", polls, " 回で、最長 ", worst / 1000.0, " ms")
		var prog := SL.warm_progress()
		_check(prog.done == prog.total and prog.total > 0, "調べ終わる(%d / %d)" % [prog.done, prog.total])
		_check(worst < 20000, "調べている間の主スレッドの呼び出しは、最長でも 20 ms 未満")
		var list := SL.osu_song_dirs()
		print("  osu!standard の曲: ", list.size())
		var lr := OszLoader.new()
		var opened := false
		for p in list.slice(0, 100):
			if lr.open(p):
				opened = true
				break
		_check(opened and lr.load_audio(lr.difficulties[0].audio_filename) != null, "実際の曲を開いて、音声まで読める(%s)" % str(lr.path).get_file())
		lr.close()
		var t3 := Time.get_ticks_usec()
		SL.find_by_md5("0".repeat(32))
		SL.find_all()
		print("  索引ができたあと find_by_md5 + find_all: ", (Time.get_ticks_usec() - t3) / 1000.0, " ms")
		SL.stop_warmup()
	print("test_osu_folder: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


func _wait_warm() -> void:
	while SL.warm_progress().running:
		OS.delay_msec(20)
	SL.stop_warmup()
