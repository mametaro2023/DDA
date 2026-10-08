extends SceneTree
## 既定の UI が lazer になったときの、設定の引き継ぎの確認(settings.gd の load_all)。
## 設定は user://dev_settings.cfg(開発用の別ファイル)に書くので、使う人の settings.cfg は触らない。
## godot --headless --path . --script tests/test_ui_default.gd

const Settings = preload("res://scripts/settings.gd")

var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


## 設定ファイルを、指定の中身(game セクション)だけで作り直して、読み込んだ ui_style を返す
func _style_of(values: Dictionary) -> String:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("game", k, values[k])
	cfg.save(Settings.path)
	return str(Settings.load_all().ui_style)


func _init() -> void:
	Settings.use_dev_file()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	_check(str(Settings.load_all().ui_style) == "lazer", "設定が無い(新しい人): lazer")

	_check(_style_of({"ui_style": "classic"}) == "lazer", "旧版の既定のまま(classic・宣伝カードは未操作): lazer に引き継ぐ")
	_check(_style_of({"ui_style": "classic", "ui_promo_hidden": false}) == "lazer", "宣伝カードを出したまま: lazer に引き継ぐ")
	_check(_style_of({"ui_style": "classic", "ui_promo_hidden": true}) == "classic", "カードを閉じた・試して戻した人(自分で選んだ): classic のまま")
	_check(_style_of({"ui_style": "lazer"}) == "lazer", "lazer を選んでいた人: lazer")
	_check(_style_of({"ui_style": "classic", "ui_default_migrated": true}) == "classic", "引き継ぎ後に classic へ戻した人: classic のまま")

	# 引き継ぎのあと保存すると、印が付き、classic へ戻しても次の読み込みで lazer へ戻されない
	_style_of({"ui_style": "classic"})
	var d := Settings.load_all()
	Settings.save_all(d)
	d.ui_style = "classic"
	Settings.save_all(d)
	_check(str(Settings.load_all().ui_style) == "classic", "引き継ぎ後に classic へ戻して保存: 次の読み込みでも classic")

	print("test_ui_default: ", "OK" if _fail == 0 else "%d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)
