extends RefCounted
## .osz の取り込み(アプリで .osz を開いたとき・ドロップしたとき)。ユーザーデータ内の songs にコピーして、曲の一覧に出るようにする。
## すでに曲の置き場(SongLibrary.search_dirs)にあるファイルは、コピーせずにそのまま使う。同じ名前・同じ大きさのファイルが
## 取り込み先にあれば、それを使う(重複して取り込まない)。中身が違う同名のファイルは、「名前 (2).osz」として並べる。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const SongLibrary = preload("res://scripts/song_library.gd")

## 結果: {ok, path(一覧に出る場所のパス。/ 区切り), title, artist, existed(すでにあった)} または {ok=false, error}。
## dest_dir を渡すと、取り込み先をそこにする(テスト用)。
static func import_file(src: String, dest_dir := "") -> Dictionary:
	src = src.replace("\\", "/")
	if not src.to_lower().ends_with(".osz"):
		return {"ok": false, "error": ".osz ファイルではありません"}
	if not FileAccess.file_exists(src):
		return {"ok": false, "error": "ファイルが見つかりません: " + src.get_file()}
	var l = OszLoader.new()
	if not l.open(src):
		return {"ok": false, "error": "読み込めませんでした: " + src.get_file()}
	var first = l.difficulties[0]
	var info := {"title": first.title, "artist": first.artist}
	l.close()
	# すでに曲の置き場にあれば、そのまま使う
	if dest_dir == "":
		var here := _norm(src.get_base_dir())
		for d in SongLibrary.search_dirs():
			if _norm(str(d)) == here:
				info.merge({"ok": true, "path": src, "existed": true})
				return info
		dest_dir = SongLibrary.ensure_user_dir()
	else:
		DirAccess.make_dir_recursive_absolute(dest_dir)
	var name := src.get_file()
	var dest := dest_dir.path_join(name).replace("\\", "/")
	var size := _size(src)
	var n := 2
	while FileAccess.file_exists(dest):
		if _size(dest) == size:
			info.merge({"ok": true, "path": dest, "existed": true})
			return info
		dest = dest_dir.path_join("%s (%d).osz" % [name.get_basename(), n]).replace("\\", "/")
		n += 1
	if DirAccess.copy_absolute(src, dest) != OK:
		return {"ok": false, "error": "コピーできませんでした"}
	info.merge({"ok": true, "path": dest, "existed": false})
	return info


static func _norm(p: String) -> String:
	return p.replace("\\", "/").trim_suffix("/").to_lower()


static func _size(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n
