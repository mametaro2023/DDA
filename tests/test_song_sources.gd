extends SceneTree
## 曲を手に入れる入口(scripts/song_sources.gd)の単体テスト: osu! の譜面ページの URL から曲の ID を読む / osu! の Songs フォルダを勧めるか。
## godot --headless --path . --script tests/test_song_sources.gd

const SS = preload("res://scripts/song_sources.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var cases := [
		["https://osu.ppy.sh/beatmapsets/320118#osu/738063", 320118],
		["https://osu.ppy.sh/beatmapsets/320118", 320118],
		["osu.ppy.sh/beatmapsets/320118/", 320118],
		["  https://OSU.PPY.SH/beatmapsets/42?x=1\n", 42],
		["https://osu.ppy.sh/s/1234", 1234],
		["見て https://osu.ppy.sh/beatmapsets/777#taiko/1 これ", 777],
		["https://osu.ppy.sh/beatmapsets/1234567#o", 1234567],   # 検索欄の長さで切れた URL
		["https://osu.ppy.sh/beatmaps/738063", -1],
		["https://osu.ppy.sh/b/738063", -1],
		["https://example.com/beatmapsets/320118", 0],
		["https://notosu.ppy.sh.evil.com/beatmapsets/1", 0],
		["https://osu.ppy.sh/beatmapsets/12345678901", 0],   # 長すぎる数字は読まない
		["320118", 0],
		["", 0],
	]
	for c in cases:
		var got := SS.set_id_of(str(c[0]))
		_check(got == int(c[1]), "set_id_of(%s) = %d(期待 %d)" % [JSON.stringify(c[0]), got, int(c[1])])

	var tmp := OS.get_temp_dir().path_join("danmaku_song_sources_test").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(tmp)
	_check(SS.osu_offer({"osu_songs": true, "osu_songs_dir": tmp}) == "", "osu! の曲を使っているときは勧めない")
	_check(SS.osu_offer({"osu_songs": false, "osu_songs_dir": tmp}) == tmp, "前に選んだ場所があれば、そこを勧める")
	var missing := tmp.path_join("nope")
	var std := SS.SongLibrary.detect_osu_songs()
	_check(SS.osu_offer({"osu_songs": false, "osu_songs_dir": missing}) == std, "前に選んだ場所がなければ、標準の場所(%s)" % (std if std != "" else "見つからない"))
	DirAccess.remove_absolute(tmp)

	print("test_song_sources: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(1 if _fail > 0 else 0)
