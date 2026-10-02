extends SceneTree
## .osz を読めないときに、理由が分かる文言を出す(osu!standard の譜面がない(mania だけ など)・zip として壊れている)。
## godot --headless --path . --script tests/test_osz_errors.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const OszImport = preload("res://scripts/osz_import.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## Mode が mode の、ノーツ 2 つだけの .osu の中身。
func _osu(mode: int, version: String) -> String:
	return "osu file format v14\n\n[General]\nAudioFilename: audio.mp3\nMode: %d\n\n[Metadata]\nTitle:Test\nArtist:Someone\nVersion:%s\n\n[Difficulty]\nCircleSize:4\nOverallDifficulty:5\nApproachRate:5\nSliderMultiplier:1.4\nSliderTickRate:1\n\n[TimingPoints]\n0,500,4,2,0,100,1,0\n\n[HitObjects]\n64,192,1000,1,0,0:0:0:0:\n192,192,1500,1,0,0:0:0:0:\n" % [mode, version]


func _make_osz(path: String, modes: Array) -> void:
	var z := ZIPPacker.new()
	z.open(path)
	for i in range(modes.size()):
		z.start_file("diff%d.osu" % i)
		z.write_file(_osu(int(modes[i]), "D%d" % i).to_utf8_buffer())
		z.close_file()
	z.close()


func _init() -> void:
	var dir := ProjectSettings.globalize_path("user://_test_osz_errors")
	DirAccess.make_dir_recursive_absolute(dir)
	var mania := dir.path_join("1 mania only.osz")
	var mixed := dir.path_join("2 taiko and catch.osz")
	var broken := dir.path_join("3 broken.osz")
	var std := dir.path_join("4 standard.osz")
	_make_osz(mania, [3, 3])
	_make_osz(mixed, [1, 2])
	_make_osz(std, [0, 3])
	var f := FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("this is not a zip")
	f.close()

	var l := OszLoader.new()
	_check(not l.open(mania) and l.error.contains("mania") and l.error.contains("osu!standard"), "mania だけの曲: 理由が分かる: " + l.error)
	l = OszLoader.new()
	_check(not l.open(mixed) and l.error.contains("taiko") and l.error.contains("catch"), "taiko と catch の曲: 入っていたモードを並べる: " + l.error)
	l = OszLoader.new()
	_check(not l.open(broken) and l.error.contains("zip") and l.error.contains("ダウンロード"), "壊れた zip: 途中で終わったダウンロードを疑うよう伝える: " + l.error)
	l = OszLoader.new()
	_check(l.open(std) and l.difficulties.size() == 1, "osu!standard が 1 つでも入っていれば読める(mania の難易度は除く)")
	l.close()

	# アプリで開いたとき(取り込み)も、同じ理由を出す
	var dest := dir.path_join("dest")
	var r := OszImport.import_file(mania, dest)
	_check(not r.ok and str(r.error).contains("1 mania only.osz") and str(r.error).contains("mania"), "アプリで開いたときのエラーに、ファイル名と理由が入る: " + str(r.error))
	r = OszImport.import_file(std, dest)
	_check(r.ok, "osu!standard の曲は取り込める")
	# 曲の一覧の要約(フォルダの監視・選曲画面)も、同じ理由
	var info := SongLibrary.info(mania)
	_check(not info.ok and str(info.error).contains("mania"), "曲の一覧の要約にも理由が入る: " + str(info.error))

	for p in [mania, mixed, broken, std]:
		DirAccess.remove_absolute(p)
	for g in DirAccess.get_files_at(dest):
		DirAccess.remove_absolute(dest.path_join(g))
	DirAccess.remove_absolute(dest)
	DirAccess.remove_absolute(dir)
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
