extends RefCounted
## UI セットの一覧と、いま使うものの選択。選ぶ値は、設定(user://settings.cfg)の ui_style。
## 起動オプション --ui <名前> で、設定を上書きできる(撮影・確認用。保存はしない)。
## 知らない名前(消えた UI セットなど)のときは、既定("lazer")に戻す。

const Settings = preload("res://scripts/settings.gd")
const ClassicUi = preload("res://scripts/ui/classic_ui.gd")
const LazerUi = preload("res://scripts/ui/lazer/lazer_ui.gd")

const DEFAULT_ID := "lazer"

## --ui で指定された名前(空なら、設定に従う)
static var override_id := ""
static var _sets := {}   # 名前 → UI セット
static var _active   # いま配色を適用している UI セット


## 使える UI セットの名前(設定画面の選択肢の順)
static func ids() -> Array:
	_ensure()
	return _sets.keys()


static func get_set(set_id: String):
	_ensure()
	return _sets.get(set_id, _sets[DEFAULT_ID])


## いま使う UI セット。
static func current():
	var want := override_id if override_id != "" else str(Settings.load_all().get("ui_style", DEFAULT_ID))
	var ui = get_set(want)
	if _active != ui:   # UI セットが変わったとき、配色・フォントを切り替える
		_active = ui
		ui.activate()
	return ui


static func _ensure() -> void:
	if not _sets.is_empty():
		return
	for s in [LazerUi.new(), ClassicUi.new()]:   # 設定画面の選択肢の順
		_sets[s.id()] = s
