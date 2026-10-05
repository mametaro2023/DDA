extends SceneTree
## 譜面の読み込み結果の保存(scripts/chart_cache.gd)と、それを使う選曲の読み込み(song_browser.gd)の確認。
##   ・1 回目は解析・生成して「統計」を保存し、2 回目は統計から読む(弾幕は統計だけ。Lv・譜面の情報が同じ。ノーツは使うときに読み込んで、同じ)
##   ・発射の一覧は、選んだ譜面の分だけ、あとから作って保存する(統計と同じ内容 / 保存したものを読む)
##   ・弾幕を変える MOD(加速など)・want_full のときは、全譜面の発射の一覧を用意する
##   ・曲のファイルが変わったら読まない / v1 と v2 は別 / 壊れたファイルは捨てて作り直す / 無効にすると保存しない / 前の形式のファイルを整理する
##   ・全曲の難易度の準備(prep_song)が、読み込みと同じ統計・Lv を作る / SongArt に Lv を残せる
## godot --headless --path . --script tests/test_chart_cache.gd

const SongBrowser = preload("res://scripts/song_browser.gd")
const ChartCache = preload("res://scripts/chart_cache.gd")
const SongArt = preload("res://scripts/song_art.gd")
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


func _stubs_all(r: Dictionary) -> bool:
	for g in r.gens:
		if not ChartCache.is_stub(g) or g.has("events"):
			return false
	return not r.gens.is_empty()


func _full_all(r: Dictionary) -> bool:
	for g in r.gens:
		if ChartCache.is_stub(g) or not g.has("events"):
			return false
	return not r.gens.is_empty()


func _init() -> void:
	var dir := ProjectSettings.globalize_path("user://_test_chart_cache")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("1 cache test.osz")
	_make_osz(path, 120)
	var p := Mods.params(["v1"])   # 弾幕 v1(MOD「弾幕 v1」。v2 が初期状態)
	for v2 in [false, true]:
		DirAccess.remove_absolute(ChartCache.stats_file(path, v2))
	# 1 回目: 解析・生成して、統計を保存する
	var r1 := SongBrowser.load_song(path, p)
	_check(r1.ok and r1.gens.size() == 2 and _full_all(r1), "1 回目: 読み込める(難易度 %d。発射の一覧つき)" % r1.gens.size())
	_check(FileAccess.file_exists(ChartCache.stats_file(path, false)), "1 回目のあと、統計の保存のファイルができる")
	_check(not FileAccess.file_exists(ChartCache.stats_file(path, true)), "v2 の分は、まだない(v1 と v2 は別)")
	_check(not r1.loader.difficulties[0].get("_lite"), "1 回目の譜面は、ふつうの版(ノーツを読んである)")
	var stat_b := int(FileAccess.get_file_as_bytes(ChartCache.stats_file(path, false)).size())
	var ev_b := int(var_to_bytes(r1.gens[1]).size())
	_check(stat_b * 4 < ev_b, "統計は、発射の一覧よりずっと小さい(統計 %d B / 発射の一覧(圧縮前)%d B)" % [stat_b, ev_b])
	# 2 回目: 統計から読む
	var r2 := SongBrowser.load_song(path, p)
	_check(r2.ok and bool(r2.loader.difficulties[0].get("_lite")) and _stubs_all(r2), "2 回目: 統計から読む(譜面は軽い版。弾幕は統計だけ)")
	_check(r1.ratings == r2.ratings and r1.levels == r2.levels, "難易度(Lv など)が、1 回目と同じ")
	var n_ok := true
	for k in range(r1.gens.size()):
		if int(r2.gens[k].n_events) != (r1.gens[k].events as Array).size() or r2.gens[k].level != r1.gens[k].level:
			n_ok = false
	_check(n_ok, "統計の発射の数・Lv が、1 回目と同じ")
	var meta_same: bool = r1.loader.difficulties.size() == r2.loader.difficulties.size()
	for k in range(mini(r1.loader.difficulties.size(), r2.loader.difficulties.size())):
		var a = r1.loader.difficulties[k]
		var b = r2.loader.difficulties[k]
		if a.md5 != b.md5 or a.version != b.version or a.stars != b.stars or a.first_time() != b.first_time() or a.last_time() != b.last_time() \
				or absf(a.density() - b.density()) > 1e-9 or a.timing_points != b.timing_points or a.breaks != b.breaks or a.audio_filename != b.audio_filename \
				or a.background != b.background or a.preview_time != b.preview_time or a.ar != b.ar or a.cs != b.cs or a.beat_length_at(a.first_time()) != b.beat_length_at(b.first_time()):
			meta_same = false
	_check(meta_same, "譜面の情報(識別子・難易度名・★・最初と最後の時刻・密度・タイミング・休憩・音と画像の名前)が、1 回目と同じ")
	# 発射の一覧: 選んだ譜面の分だけ、あとから作って保存する
	var bm1 = r2.loader.difficulties[1]
	_check(not FileAccess.file_exists(ChartCache.events_file(path, str(bm1.md5), false)), "選ぶまでは、発射の一覧の保存はない")
	var full := SongBrowser.full_gen_for(path, bm1, false, true)
	_check(full.has("events") and not ChartCache.is_stub(full) and (full.events as Array).size() == int(r2.gens[1].n_events) and full.events == r1.gens[1].events, "発射の一覧を作れる(1 回目と同じ内容。軽い版からでも作れる)")
	_check(FileAccess.file_exists(ChartCache.events_file(path, str(bm1.md5), false)), "作った発射の一覧は、保存される")
	var again := SongBrowser.full_gen_for(path, bm1, false, true)
	_check(again == full, "2 回目は、保存した発射の一覧を読む(同じ内容)")
	# 統計から開いた曲: 選んだ譜面が統計の間は、始められない
	var sb := SongBrowser.new()
	sb.songs = [{"path": path, "title": "Cache test", "artist": "Someone", "md5": "x", "key": "x", "key2": "x"}]
	sb.settings = {"mods": []}
	sb.loader = r2.loader
	sb.gens = r2.gens
	sb.ratings = r2.ratings
	sb.song_sel = 0
	sb.diff_sel = 1
	_check(not sb.can_start() and sb.waiting_full(), "選んだ譜面が統計だけの間は、始められない")
	sb.gens[1] = full
	_check(sb.can_start() and not sb.waiting_full(), "発射の一覧がそろったら、始められる")
	# 弾幕を変える MOD: 統計だけでは Lv を測れないので、全譜面の発射の一覧が要る
	sb.gens_v2 = false
	sb.settings = {"mods": ["v1", "rush"]}
	_check(sb.needs_style_reload(), "加速を付けると、統計だけの弾幕は、読み直しが要る")
	sb.settings = {"mods": ["v1", "practice"]}
	_check(not sb.needs_style_reload(), "練習(弾幕を変えない MOD)なら、読み直しは要らない")
	r2.loader.close()
	var rush := SongBrowser.load_song(path, Mods.params(["v1", "rush"]))
	_check(rush.ok and _full_all(rush) and rush.ratings[1].level != r1.ratings[1].level, "加速: 全譜面の発射の一覧を用意して、Lv を測り直す(Lv %.2f → %.2f)" % [r1.ratings[1].level, rush.ratings[1].level])
	_check(rush.levels == r1.levels, "MOD なしの Lv(levels)は、MOD の影響を受けない")
	rush.loader.close()
	var wf := SongBrowser.load_song(path, p, true)
	_check(wf.ok and _full_all(wf), "want_full: 全譜面の発射の一覧を用意する")
	wf.loader.close()
	r1.loader.close()
	# ノーツは、使うときに、その譜面のファイルだけを開き直して読む(読み込んだ OszLoader を閉じたあとでも)
	var r2b := SongBrowser.load_song(path, p)
	r2b.loader.close()
	var objs_ok := true
	for k in range(r2b.loader.difficulties.size()):
		var ob: Array = r2b.loader.difficulties[k].hit_objects
		if ob.is_empty():
			objs_ok = false
	_check(objs_ok and not bool(r2b.loader.difficulties[0].get("_lite")), "使うときに読み込んだノーツが、読める(閉じたあとでも)")
	# v2 は別に保存される
	var r3 := SongBrowser.load_song(path, Mods.params([]))
	_check(r3.ok and bool(r3.v2) and FileAccess.file_exists(ChartCache.stats_file(path, true)) and _full_all(r3), "v2: 別に作って、別のファイルに保存する")
	r3.loader.close()
	# 壊れた保存は捨てて、作り直す
	var f := FileAccess.open(ChartCache.stats_file(path, false), FileAccess.WRITE)
	f.store_string("broken")
	f.close()
	var r4 := SongBrowser.load_song(path, p)
	_check(r4.ok and _full_all(r4) and not bool(r4.loader.difficulties[0].get("_lite")), "壊れた保存: 読まずに作り直す")
	var r5 := SongBrowser.load_song(path, p)
	_check(bool(r5.loader.difficulties[0].get("_lite")) and _stubs_all(r5), "作り直したあとは、また統計から読む")
	r4.loader.close()
	r5.loader.close()
	# 曲のファイルが変わったら(大きさ・更新時刻が変わる)、古い保存は読まない
	var old_file := ChartCache.stats_file(path, false)
	_make_osz(path, 90)
	_check(ChartCache.stats_file(path, false) != old_file, "曲のファイルが変わると、保存のファイル名も変わる")
	var r6 := SongBrowser.load_song(path, p)
	_check(r6.ok and not bool(r6.loader.difficulties[0].get("_lite")) and _full_all(r6), "曲のファイルが変わったら、古い保存は読まず、作り直す")
	r6.loader.close()
	# 全曲の難易度の準備(別の曲): 読み込みと同じ統計・Lv を作る
	var path2 := dir.path_join("2 cache test.osz")
	_make_osz(path2, 60)
	DirAccess.remove_absolute(ChartCache.stats_file(path2, false))
	_check(not ChartCache.has_stats(path2, false), "準備の前は、統計がない")
	var levels := SongBrowser.prep_song(path2, false)
	_check(ChartCache.has_stats(path2, false) and levels.size() == 2, "準備(prep_song): 統計を保存して、全譜面の Lv を返す")
	var viaload := SongBrowser.load_song(path2, p)
	_check(bool(viaload.loader.difficulties[0].get("_lite")) and _stubs_all(viaload) and viaload.levels == levels, "準備した統計から読める(Lv が、準備で測ったものと同じ)")
	viaload.loader.close()
	# SongArt に Lv を残す・版が違えば使わない
	SongArt.set_levels("test_song", false, levels)
	var id0: String = str(levels.keys()[0])
	_check(absf(SongArt.level_of("test_song", id0, false) - float(levels[id0])) < 1e-9 and SongArt.level_of("test_song", id0, true) < 0.0 and SongArt.level_of("nothing", id0, false) < 0.0, "SongArt: Lv を残して読める(v1 / v2 は別。ない曲は -1)")
	# 無効にすると、保存も読み込みもしない
	var path3 := dir.path_join("3 cache test.osz")
	_make_osz(path3, 60)
	ChartCache.enabled = false
	var r7 := SongBrowser.load_song(path3, p)
	var r8 := SongBrowser.load_song(path3, p)
	_check(not FileAccess.file_exists(ChartCache.stats_file(path3, false)) and not bool(r8.loader.difficulties[0].get("_lite")), "無効のとき: 保存しない・読まない")
	ChartCache.enabled = true
	r7.loader.close()
	r8.loader.close()
	# 保存の整理: 前の形式(.dcc)を捨て、いまの形式は残す
	var legacy := "%s/old.dcc" % ChartCache.DIR
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ChartCache.DIR))
	var lf := FileAccess.open(legacy, FileAccess.WRITE)
	lf.store_string("old")
	lf.close()
	ChartCache.prune()
	_check(not FileAccess.file_exists(legacy) and FileAccess.file_exists(ChartCache.stats_file(path2, false)), "整理(prune): 前の形式は捨て、いまの統計は残る")
	# 後始末
	for pth in [path, path2, path3]:
		for v2 in [false, true]:
			DirAccess.remove_absolute(ChartCache.stats_file(pth, v2))
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir)
	print("test_chart_cache: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
