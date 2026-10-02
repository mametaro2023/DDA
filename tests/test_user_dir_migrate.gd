extends SceneTree
## ユーザーデータの引っ越し(scripts/user_dir_migrate.gd): アプリの名前を変えたあと、前の名前の場所の中身を、今の場所へ移す。
## godot --headless --path . --script tests/test_user_dir_migrate.gd

const UserDirMigrate = preload("res://scripts/user_dir_migrate.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _rm_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm_tree(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _init() -> void:
	var root := ProjectSettings.globalize_path("user://_test_migrate")
	_rm_tree(root)
	var old := root.path_join("old")
	var cur := root.path_join("cur")

	# 1) 前の場所の設定・曲・記録が、今の場所へ移る。今の場所にすでにあるもの(Godot のログ)は、上書きしない
	_write(old.path_join("settings.cfg"), "old settings")
	_write(old.path_join("songs/a.osz"), "song a")
	_write(old.path_join("speed_study.csv"), "rows")
	_write(old.path_join("logs/godot.log"), "old log")
	_write(cur.path_join("logs/godot.log"), "new log")
	var n := UserDirMigrate.migrate(old, cur)
	_check(n == 3, "設定・曲のフォルダ・記録の 3 つを移した (%d)" % n)
	_check(_read(cur.path_join("settings.cfg")) == "old settings" and _read(cur.path_join("songs/a.osz")) == "song a" and _read(cur.path_join("speed_study.csv")) == "rows",
		"移した中身が、今の場所で読める")
	_check(_read(cur.path_join("logs/godot.log")) == "new log", "今の場所にすでにあるもの(ログ)は上書きしない")
	_check(DirAccess.dir_exists_absolute(old) and not FileAccess.file_exists(old.path_join("settings.cfg")), "移せなかったもの(ログ)が残るので、前の場所は消さない")

	# 2) もう一度呼んでも、すでに今の場所にあるもの(設定)は上書きしない
	_write(old.path_join("settings.cfg"), "stale")
	_check(UserDirMigrate.migrate(old, cur) == 0 and _read(cur.path_join("settings.cfg")) == "old settings", "もう一度呼んでも、すでにあるもの(設定)は上書きしない")

	# 3) 前の場所がなければ何もしない / 全部移せたら、前の場所を消す
	_rm_tree(root)
	_check(UserDirMigrate.migrate(old, cur) == 0, "前の場所がなければ、何もしない")
	_write(old.path_join("settings.cfg"), "s")
	_write(old.path_join("songs/b.osz"), "b")
	_check(UserDirMigrate.migrate(old, cur) == 2 and not DirAccess.dir_exists_absolute(old), "全部移せたら、空になった前の場所を消す")
	_check(UserDirMigrate.migrate(cur, cur) == 0, "前の場所と今の場所が同じなら、何もしない")
	_rm_tree(root)

	_check(UserDirMigrate.OLD_NAME == "DDA - osu! Danmaku Dodger" and ProjectSettings.get_setting("application/config/name") == "DDA - Danmaku Dodger",
		"前の名前と今の名前: %s → %s" % [UserDirMigrate.OLD_NAME, ProjectSettings.get_setting("application/config/name")])
	print("RESULT: ", "OK" if _fail == 0 else "%d FAILURES" % _fail)
	quit(1 if _fail > 0 else 0)
