extends RefCounted
## 曲を手に入れる入口の、小さな処理(UI を持たない。classic・lazer 風の選曲画面と main が使う)。
## - osu! の Songs フォルダが見つかったら、ボタン 1 つで使えるようにする(設定の「曲」の「osu! の Songs フォルダの曲を使う」と同じ)
## - osu! の譜面ページの URL から、曲全体の ID(BeatmapSetID)を読む(main がミラーからダウンロードする。song_download.gd)

const SongLibrary = preload("res://scripts/song_library.gd")
const Settings = preload("res://scripts/settings.gd")

static var _set_re: RegEx
static var _map_re: RegEx


## osu! の Songs フォルダを、まだ使っていなくて、見つかったとき、その場所。使っている・見つからないときは空。
## 前に場所を選んであれば(osu_songs_dir)、そこを優先する。
static func osu_offer(st: Dictionary) -> String:
	if bool(st.get("osu_songs", false)):
		return ""
	var d := str(st.get("osu_songs_dir", "")).replace("\\", "/")
	if d != "" and DirAccess.dir_exists_absolute(d):
		return d
	return SongLibrary.detect_osu_songs()


## osu! の Songs フォルダの曲を使うようにして、保存する(曲の索引は裏で作り始める。画面は refresh_songs で一覧を足し直す)。
static func enable_osu(st: Dictionary) -> void:
	st.osu_songs = true
	var d := str(st.get("osu_songs_dir", ""))
	if d != "" and not DirAccess.dir_exists_absolute(d):
		st.osu_songs_dir = ""   # 前に選んだ場所がもうない: 標準の場所から探す
	SongLibrary.apply_osu_settings(st)
	SongLibrary.start_osu_warmup()
	Settings.save_all(st)


## osu! の譜面ページの URL から、曲全体の ID を読む(例: https://osu.ppy.sh/beatmapsets/320118#osu/738063 → 320118。古い形の /s/320118 も)。
## 読めなければ 0。難易度だけのページ(/beatmaps/… や /b/…)は、曲全体の ID が分からないので -1。
static func set_id_of(text: String) -> int:
	if _set_re == null:
		_set_re = RegEx.create_from_string("(?i)\\bosu\\.ppy\\.sh/(?:beatmapsets|s)/(\\d{1,9})(?!\\d)")
		_map_re = RegEx.create_from_string("(?i)\\bosu\\.ppy\\.sh/(?:beatmaps|b)/\\d+")
	var t := text.substr(0, 2000)
	var m := _set_re.search(t)
	if m != null:
		return int(m.get_string(1))
	if _map_re.search(t) != null:
		return -1
	return 0
