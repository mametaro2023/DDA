extends RefCounted
## 曲(.osz)の置き場所の探索。選曲画面とタイトル画面が共通で使う。
## 探す場所: プロジェクト直下(開発時) / songs / 実行ファイルの隣 / 実行ファイルの隣の songs / ユーザーデータ内の songs
## (配布版は、実行ファイルの隣の songs フォルダに .osz を入れる)。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")


static func search_dirs() -> Array:
	var dirs: Array = []
	var proj := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path().get_base_dir()
	for d in [proj, proj.path_join("songs"), exe, exe.path_join("songs"),
			ProjectSettings.globalize_path("user://songs")]:
		d = str(d).replace("\\", "/")
		if not dirs.has(d):
			dirs.append(d)
	return dirs


## 見つかった .osz のパス(重複なし)。
static func find_all() -> Array:
	var out: Array = []
	for d in search_dirs():
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".osz"):
				var p: String = str(d).path_join(f).replace("\\", "/")
				if not out.has(p):
					out.append(p)
	return out


## ユーザーデータ内の songs フォルダ(なければ作る)。ここにも .osz を置ける。
static func ensure_user_dir() -> String:
	var d := ProjectSettings.globalize_path("user://songs")
	DirAccess.make_dir_recursive_absolute(d)
	return d


## 譜面の MD5(Beatmap.md5)から、その譜面を含む .osz を探す(マルチプレイで、部屋の曲を持っているかの確認)。
## 見つかったら {path, version}、なければ空の辞書。.osz の中の .osu を読んで MD5 を数えるだけ(譜面の解析はしない)ので軽い。
static func find_by_md5(md5: String) -> Dictionary:
	for path in find_all():
		var z := ZIPReader.new()
		if z.open(path) != OK:
			continue
		for f in z.get_files():
			if f.to_lower().ends_with(".osu") and z.read_file(f).get_string_from_utf8().md5_text() == md5:
				z.close()
				return {"path": path, "file": f}
		z.close()
	return {}
