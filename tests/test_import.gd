extends SceneTree
## .osz の取り込み・音量・ダウンロードリンクの単体テスト。
## godot --headless --path . --script tests/test_import.gd

const OszImport = preload("res://scripts/osz_import.gd")
const Volume = preload("res://scripts/volume.gd")
const MultiScreen = preload("res://scripts/ui/multi_screen.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	# ダウンロードリンク(osu! の譜面ページ)
	_check(MultiScreen.osu_url(320118, 738063) == "https://osu.ppy.sh/beatmapsets/320118#osu/738063", "リンク: 曲 ID + 難易度 ID")
	_check(MultiScreen.osu_url(320118, 0) == "https://osu.ppy.sh/beatmapsets/320118", "難易度 ID がなければ曲のページ")
	_check(MultiScreen.osu_url(0, 5) == "" and MultiScreen.osu_url(-3, 0) == "", "曲 ID がなければリンクなし")
	# 譜面から ID を読む
	var src := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
	var l := OszLoader.new()
	if FileAccess.file_exists(src) and l.open(src):
		var ok := true
		for bm in l.difficulties:
			if bm.beatmapset_id != 320118 or bm.beatmap_id <= 0:
				ok = false
		_check(ok, "譜面から BeatmapSetID(320118)・BeatmapID を読める(例: %s → %d)" % [l.difficulties[0].version, l.difficulties[0].beatmap_id])
		l.close()
	# 取り込み(テスト用の取り込み先)
	var tmp := OS.get_temp_dir().path_join("dda_import_test").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(tmp)
	if FileAccess.file_exists(src):
		var r := OszImport.import_file(src, tmp)
		_check(r.ok and not r.existed and FileAccess.file_exists(r.path) and r.title == "No title", "取り込むとコピーされる: %s" % str(r.get("path", "")).get_file())
		var r2 := OszImport.import_file(src, tmp)
		_check(r2.ok and r2.existed and r2.path == r.path, "同じ物を 2 回取り込んでも増えない")
		# 同名で中身が違うもの
		var f := FileAccess.open(r.path, FileAccess.READ)
		var bytes := f.get_buffer(f.get_length())
		f.close()
		var other := tmp.path_join("src2/320118 Reol - No title.osz")
		DirAccess.make_dir_recursive_absolute(other.get_base_dir())
		var w := FileAccess.open(other, FileAccess.WRITE)
		w.store_buffer(bytes)
		w.store_buffer(PackedByteArray([0, 0, 0, 0]))   # 末尾に足して大きさを変える(zip としては読める)
		w.close()
		var r3 := OszImport.import_file(other, tmp)
		_check(r3.ok and not r3.existed and r3.path != r.path and r3.path.contains("(2)"), "同名で中身が違えば別名で取り込む: %s" % str(r3.get("path", "")).get_file())
		DirAccess.remove_absolute(r.path)
		DirAccess.remove_absolute(r3.path)
		DirAccess.remove_absolute(other)
		DirAccess.remove_absolute(other.get_base_dir())
	var bad := tmp.path_join("x.txt")
	var bf := FileAccess.open(bad, FileAccess.WRITE)
	bf.store_string("hello")
	bf.close()
	_check(not OszImport.import_file(bad, tmp).ok, ".osz でないものは断る")
	var fake := tmp.path_join("fake.osz")
	var ff := FileAccess.open(fake, FileAccess.WRITE)
	ff.store_string("not a zip")
	ff.close()
	_check(not OszImport.import_file(fake, tmp).ok, "壊れた .osz は断る")
	_check(not OszImport.import_file(tmp.path_join("none.osz"), tmp).ok, "存在しないファイルは断る")
	DirAccess.remove_absolute(bad)
	DirAccess.remove_absolute(fake)
	DirAccess.remove_absolute(tmp)

	# 曲の一覧の重複(同じファイルが、書き方の違うパスや別の置き場から見つかっても 1 つにする)
	var SL = load("res://scripts/song_library.gd")
	_check(SL.norm("C:/Users/A/DDA_beta/songs/") == SL.norm("c:\\users\\a\\DDA_beta\\songs") and SL.norm("C:/x/./y/../songs") == SL.norm("c:/X/songs"), "パスの書き方(大小・区切り・末尾・. ..)が違っても同じ場所と分かる")
	if FileAccess.file_exists(src):
		var d1 := tmp + "_a"
		var d2 := tmp + "_b"
		DirAccess.make_dir_recursive_absolute(d1)
		DirAccess.make_dir_recursive_absolute(d2)
		DirAccess.copy_absolute(src, d1.path_join("320118 Reol - No title.osz"))
		DirAccess.copy_absolute(src, d2.path_join("320118 REOL - no title.OSZ"))
		var seen := {}
		var p1: String = d1.path_join("320118 Reol - No title.osz")
		var p2: String = d2.path_join("320118 REOL - no title.OSZ")
		_check(SL._is_new(seen, p1) and not SL._is_new(seen, p1), "同じパスは 2 回目は追加しない")
		_check(not SL._is_new(seen, p2), "別の置き場に、同じ名前(大小違い)・同じ大きさのコピーがあっても追加しない")
		for p in [p1, p2]:
			DirAccess.remove_absolute(p)
		DirAccess.remove_absolute(d1)
		DirAccess.remove_absolute(d2)

	# 音量
	Volume.set_master(50)
	_check(Volume.master == 50 and absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) < 0.01, "全体音量 50%% → マスターバス %.1f dB" % AudioServer.get_bus_volume_db(0))
	Volume.set_music(0)
	var mi := AudioServer.get_bus_index(Volume.MUSIC_BUS)
	_check(mi > 0 and AudioServer.is_bus_mute(mi) and AudioServer.get_bus_send(mi) == &"Master", "音楽 0%% → Music バスがミュート(マスターの子)")
	Volume.set_music(40)
	_check(not AudioServer.is_bus_mute(mi) and absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.4)) < 0.01, "音楽 40%%")
	Volume.set_value(2, 130)
	_check(Volume.sfx == 100, "範囲を超えたら 100 で止まる")
	Volume.set_value(0, -20)
	_check(Volume.master == 0 and AudioServer.is_bus_mute(0), "0 未満は 0(ミュート)")
	var d := {"volume": 1, "sfx_volume": 2, "music_volume": 3}
	Volume.write_into(d)
	_check(d.volume == 0 and d.sfx_volume == 100 and d.music_volume == 40, "保存する辞書へ、今の音量を書き込む(古い値で上書きしない)")

	# アプリのバージョン比較(アプリ内アップデート)
	var Up = load("res://scripts/updater.gd")
	_check(Up.is_newer("0.3.0-beta", "0.2.0-beta") and Up.is_newer("v0.2.1", "0.2.0-beta") and Up.is_newer("1.0.0", "0.9.9"), "新しい版を新しいと判定する")
	_check(not Up.is_newer("0.2.0-beta", "0.2.0-beta") and not Up.is_newer("0.1.0-beta", "0.2.0-beta") and not Up.is_newer("0.2.0-alpha", "0.2.0-beta"), "同じ・古い版は新しくない")
	_check(Up.is_newer("0.2.0", "0.2.0-beta") and not Up.is_newer("0.2.0-beta", "0.2.0"), "正式版は、同じ番号のベータより新しい")
	_check(Up.is_newer("0.10.0", "0.9.0") and Up.compare("0.2", "0.2.0") == 0, "数字として比べる(0.10 > 0.9、0.2 = 0.2.0)")
	_check(not Up.is_newer("abc", "0.2.0") and not Up.is_newer("", "0.2.0") and not Up.is_newer("v1.x", "0.2.0"), "読めない版は新しいと見なさない")
	print("test_import: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)
