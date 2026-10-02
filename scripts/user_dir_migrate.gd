extends RefCounted
## ユーザーデータの引っ越し(v0.8.0 でアプリの名前を「DDA - osu! Danmaku Dodger」から「DDA - Danmaku Dodger」に変えたため)。
## Godot のユーザーデータ(user://)の場所は、アプリの名前で決まる(%APPDATA%\Godot\app_userdata\<名前>)。名前を変えると、
## 設定・取り込んだ曲・記録が、前の名前の場所に残ったままになるので、起動するたびに、前の場所が残っていれば、その中身を今の場所へ移す(移し終えたら前の場所は消えるので、ふだんは何もしない)。
##   - 前の場所の中身を 1 つずつ移す(同じドライブなので、名前の付け替えだけで速い。曲のフォルダが大きくても待たない)
##   - 今の場所にすでに同じ名前のもの(Godot が作るログ・新しい版で作った設定など)があれば、それは移さない(上書きしない)
##   - 空になった前の場所は消す。何度呼んでも、すでにあるものは触らないので安全(開発用のツールが先に今の場所へ書いていても、残りは移る)

const OLD_NAME := "DDA - osu! Danmaku Dodger"


## 起動時に呼ぶ。移したものの数を返す(移さなかったら 0)。
static func run() -> int:
	var cur := OS.get_user_data_dir()
	return migrate(cur.get_base_dir().path_join(OLD_NAME), cur)


## old の中身を cur へ移す(テストでは、別の場所を渡す)。
static func migrate(old: String, cur: String) -> int:
	if old.simplify_path() == cur.simplify_path() or not DirAccess.dir_exists_absolute(old):
		return 0
	DirAccess.make_dir_recursive_absolute(cur)
	var moved := 0
	var entries: Array = []
	entries.append_array(DirAccess.get_directories_at(old))
	entries.append_array(DirAccess.get_files_at(old))
	for nm in entries:
		var dst := cur.path_join(nm)
		if FileAccess.file_exists(dst) or DirAccess.dir_exists_absolute(dst):
			continue
		if DirAccess.rename_absolute(old.path_join(nm), dst) == OK:
			moved += 1
		else:
			push_warning("ユーザーデータを移せませんでした: " + old.path_join(nm))
	# 空になったら、前の場所を消す(残ったもの(ログなど)があれば、そのまま)
	if DirAccess.get_directories_at(old).is_empty() and DirAccess.get_files_at(old).is_empty():
		DirAccess.remove_absolute(old)
	if moved > 0:
		print("ユーザーデータを移しました(%d 個): %s → %s" % [moved, old, cur])
	return moved
