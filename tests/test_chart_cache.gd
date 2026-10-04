extends SceneTree
## 譜面の読み込み結果の保存(scripts/chart_cache.gd)の確認。
##   ・1 回目は解析・生成して保存し、2 回目は保存から読む(弾幕・Lv・譜面の情報が同じ。ノーツは使うときに読み込んで、同じ)
##   ・曲のファイルが変わったら読まない / v1 と v2 は別 / 壊れたファイルは捨てて作り直す / 無効にすると保存しない
## godot --headless --path . --script tests/test_chart_cache.gd

const SongBrowser = preload("res://scripts/song_browser.gd")
const ChartCache = preload("res://scripts/chart_cache.gd")
const Mods = preload("res://scripts/mods.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _osu(version: String, n: int, extra := "") -> String:
	var s := "osu file format v14\n\n[General]\nAudioFilename: audio.mp3\nMode: 0\nPreviewTime: 1000\n\n[Metadata]\nTitle:Cache test\nArtist:Someone\nVersion:%s\nCreator:me\n\n[Difficulty]\nHPDrainRate:5\nCircleSize:4\nOverallDifficulty:5\nApproachRate:7\nSliderMultiplier:1.4\nSliderTickRate:1\n\n[Events]\n0,0,\"bg.jpg\",0,0\n2,20000,21000\n\n[TimingPoints]\n0,500,4,2,0,100,1,0\n8000,-100,4,2,0,100,0,1\n\n[HitObjects]\n" % version
	for i in range(n):
		var t := 1000 + i * 250
		if i % 7 == 3:   # スライダー(曲線つき)
			s += "%d,%d,%d,2,0,B|%d:%d|%d:%d,1,150,0|0,0:0|0:0,0:0:0:0:\n" % [100 + (i * 37) % 300, 80 + (i * 53) % 200, t, 200 + (i * 37) % 200, 150 + (i * 11) % 100, 300, 250, ]
		else:
			s += "%d,%d,%d,1,0,0:0:0:0:\n" % [64 + (i * 41) % 380, 48 + (i * 29) % 280, t]
	return s + extra


func _make_osz(path: String, n: int, extra := "") -> void:
	var z := ZIPPacker.new()
	z.open(path)
	for d in [["Easy", n >> 1], ["Hard", n]]:
		z.start_file("%s.osu" % d[0])
		z.write_file(_osu(str(d[0]), int(d[1]), extra).to_utf8_buffer())
		z.close_file()
	z.close()


func _init() -> void:
	var dir := ProjectSettings.globalize_path("user://_test_chart_cache")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("1 cache test.osz")
	_make_osz(path, 120)
	var p := Mods.params(["v1"])   # 弾幕 v1(MOD「弾幕 v1」。v2 が初期状態)
	for v2 in [false, true]:
		DirAccess.remove_absolute(ChartCache.file_of(path, v2))
	var tag := "v1"
	# 1 回目: 解析・生成して、保存する
	var r1 := SongBrowser.load_song(path, p)
	_check(r1.ok and r1.gens.size() == 2, "1 回目: 読み込める(難易度 %d)" % r1.gens.size())
	_check(FileAccess.file_exists(ChartCache.file_of(path, false)), "1 回目のあと、保存のファイルができる")
	_check(not FileAccess.file_exists(ChartCache.file_of(path, true)), "v2 の分は、まだない(v1 と v2 は別)")
	_check(not r1.loader.difficulties[0].get("_lite"), "1 回目の譜面は、ふつうの版(ノーツを読んである)")
	# 2 回目: 保存から読む
	var r2 := SongBrowser.load_song(path, p)
	_check(r2.ok and bool(r2.loader.difficulties[0].get("_lite")), "2 回目: 保存から読む(譜面は軽い版)")
	_check(r1.gens == r2.gens, "弾幕が、1 回目と同じ")
	_check(r1.ratings == r2.ratings, "難易度(Lv など)が、1 回目と同じ")
	var meta_same: bool = r1.loader.difficulties.size() == r2.loader.difficulties.size()
	for k in range(mini(r1.loader.difficulties.size(), r2.loader.difficulties.size())):
		var a = r1.loader.difficulties[k]
		var b = r2.loader.difficulties[k]
		if a.md5 != b.md5 or a.version != b.version or a.stars != b.stars or a.first_time() != b.first_time() or a.last_time() != b.last_time() \
				or absf(a.density() - b.density()) > 1e-9 or a.timing_points != b.timing_points or a.breaks != b.breaks or a.audio_filename != b.audio_filename \
				or a.background != b.background or a.preview_time != b.preview_time or a.ar != b.ar or a.cs != b.cs or a.beat_length_at(a.first_time()) != b.beat_length_at(b.first_time()):
			meta_same = false
	_check(meta_same, "譜面の情報(識別子・難易度名・★・最初と最後の時刻・密度・タイミング・休憩・音と画像の名前)が、1 回目と同じ")
	_check(bool(r2.loader.difficulties[1].get("_lite")), "軽い版は、ノーツを使うまで読まない(first_time などでは読まない)")
	# ノーツは、使うときに、その譜面のファイルだけを開き直して読む(読み込んだ OszLoader を閉じたあとでも)
	r2.loader.close()
	var objs_ok := true
	for k in range(r1.loader.difficulties.size()):
		var oa: Array = r1.loader.difficulties[k].hit_objects
		var ob: Array = r2.loader.difficulties[k].hit_objects
		if oa.size() != ob.size() or oa[0].time != ob[0].time or oa[oa.size() - 1].end_time != ob[ob.size() - 1].end_time:
			objs_ok = false
		for i in range(oa.size()):
			if oa[i].kind != ob[i].kind or oa[i].pos != ob[i].pos or oa[i].end_time != ob[i].end_time:
				objs_ok = false
				break
	_check(objs_ok and not bool(r2.loader.difficulties[0].get("_lite")), "使うときに読み込んだノーツが、解析したものと同じ(スライダーの終わりの時刻まで)")
	# 軽い版から弾幕を作り直しても、同じ(MOD で作り直す経路)
	_check(SongBrowser.make_gen(r2.loader.difficulties[0], false) == SongBrowser.make_gen(r1.loader.difficulties[0], false), "軽い版から弾幕を作り直しても、同じ")
	r1.loader.close()
	# v2 は別に保存される
	var r3 := SongBrowser.load_song(path, Mods.params([]))   # 初期状態 = v2
	_check(r3.ok and bool(r3.v2) and FileAccess.file_exists(ChartCache.file_of(path, true)) and not bool(r3.loader.difficulties[0].get("_lite")), "v2: 別に作って、別のファイルに保存する")
	r3.loader.close()
	# 壊れた保存は捨てて、作り直す
	var f := FileAccess.open(ChartCache.file_of(path, false), FileAccess.WRITE)
	f.store_string("broken")
	f.close()
	var r4 := SongBrowser.load_song(path, p)
	_check(r4.ok and r4.gens == r1.gens and not bool(r4.loader.difficulties[0].get("_lite")), "壊れた保存: 読まずに作り直す")
	var r5 := SongBrowser.load_song(path, p)
	_check(bool(r5.loader.difficulties[0].get("_lite")), "作り直したあとは、また保存から読む")
	r4.loader.close()
	r5.loader.close()
	# 曲のファイルが変わったら(大きさ・更新時刻が変わる)、古い保存は読まない
	var old_file := ChartCache.file_of(path, false)
	_make_osz(path, 90)
	_check(ChartCache.file_of(path, false) != old_file, "曲のファイルが変わると、保存のファイル名も変わる")
	var r6 := SongBrowser.load_song(path, p)
	_check(r6.ok and not bool(r6.loader.difficulties[0].get("_lite")) and r6.gens != r1.gens, "曲のファイルが変わったら、古い保存は読まず、作り直す")
	r6.loader.close()
	# 無効にすると、保存も読み込みもしない
	var path2 := dir.path_join("2 cache test.osz")
	_make_osz(path2, 60)
	ChartCache.enabled = false
	var r7 := SongBrowser.load_song(path2, p)
	var r8 := SongBrowser.load_song(path2, p)
	_check(not FileAccess.file_exists(ChartCache.file_of(path2, false)) and not bool(r8.loader.difficulties[0].get("_lite")), "無効のとき: 保存しない・読まない")
	ChartCache.enabled = true
	r7.loader.close()
	r8.loader.close()
	# 保存の整理: 上限を超えたら、古いものから捨てる(ここでは確かめず、呼べること・残るべきものが残ることだけ)
	SongBrowser.load_song(path, p).loader.close()
	ChartCache.prune()
	_check(FileAccess.file_exists(ChartCache.file_of(path, false)), "整理(prune)しても、上限以内なら残る")
	# 後始末
	for v2 in [false, true]:
		DirAccess.remove_absolute(ChartCache.file_of(path, v2))
		DirAccess.remove_absolute(ChartCache.file_of(path2, v2))
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir)
	print("test_chart_cache: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
