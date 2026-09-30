extends RefCounted
## 曲(.osz)の置き場所の探索。選曲画面とタイトル画面が共通で使う。
## 探す場所: プロジェクト直下(開発時) / songs / 実行ファイルの隣 / 実行ファイルの隣の songs / ユーザーデータ内の songs
## (配布版は、実行ファイルの隣の songs フォルダに .osz を入れる)。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")


## パスを比べるための形(区切りを / にそろえ、余分な / ・ . を除き、大文字小文字を区別しない)。
## 同じ場所が、実行ファイルの位置と res:// から別の書き方で得られても(ドライブ文字の大小など)、同じと分かるようにする。
static func norm(p: String) -> String:
	return p.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


static func search_dirs() -> Array:
	var dirs: Array = []
	var seen := {}
	var proj := ProjectSettings.globalize_path("res://")
	var exe := OS.get_executable_path().get_base_dir()
	for d in [proj, proj.path_join("songs"), exe, exe.path_join("songs"),
			ProjectSettings.globalize_path("user://songs")]:
		d = str(d).replace("\\", "/")
		var key := norm(d)
		if not seen.has(key):
			seen[key] = true
			dirs.append(d)
	return dirs


## 見つかった .osz のパス。同じファイルは 1 つにする(場所の書き方が違うものも、同じ名前・同じ大きさのものも)。
static func find_all() -> Array:
	var out: Array = []
	var seen := {}
	for d in search_dirs():
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".osz"):
				var p: String = str(d).path_join(f).replace("\\", "/")
				if _is_new(seen, p):
					out.append(p)
	return out


## 追加してよいファイルか(すでに数えたものと同じなら false)。同じと見なすのは、パスが同じ、または名前と大きさが同じ。
static func _is_new(seen: Dictionary, p: String) -> bool:
	var k1 := norm(p)
	var f := FileAccess.open(p, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	if f != null:
		f.close()
	var k2 := "%s|%d" % [p.get_file().to_lower(), size]
	if seen.has(k1) or (size >= 0 and seen.has(k2)):
		return false
	seen[k1] = true
	seen[k2] = true
	return true


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
