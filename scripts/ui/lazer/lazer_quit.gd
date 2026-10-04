extends "res://scripts/ui/quit_panel.gd"
## lazer 風の確認パネル(終了の確認・部屋を閉じる確認・ダウンロードの同意)。文言・キー操作(Enter で実行、Esc で閉じる)・signal は
## classic の確認パネル(quit_panel.gd)のものをそのまま使い、見た目だけを lazer の確認ダイアログ(lazer_dialog.gd)にする。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerDialog = preload("res://scripts/ui/lazer/lazer_dialog.gd")

## 上の丸いアイコン(空なら、文言から決める: 終了 → 電源、ダウンロード → 下向きの矢印、ほか → 注意)
var icon_kind := ""

var _f: Dictionary


func _ready() -> void:
	var icon := icon_kind
	if icon == "":
		icon = "power" if ok_text.contains("終了") else ("download" if ok_text.contains("ダウンロード") else "alert")
	var danger := icon != "download"   # 取り消せない操作(終了・閉じる)は赤、同意は主役のピンク
	var accent := LazerStyle.RED if danger else LazerStyle.PINK
	_f = LazerDialog.build(self, icon, accent, title_text, body_text, 640.0 if body_text != "" else 480.0)
	_dim = _f.dim
	_panel = _f.panel
	LazerDialog.button(_f.buttons, ok_text, accent, "power" if icon == "power" else ("download" if icon == "download" else ""), Color(0.16, 0.03, 0.07), _confirm)
	LazerDialog.button(_f.buttons, cancel_text, Color(0.3, 0.28, 0.38), "back", LazerStyle.TEXT, _cancel, "back")
	UiStyle.close_on_outside_click(self, _panel, _cancel)
	LazerDialog.open_anim(self, _f)


func _cancel() -> void:
	if _done:
		return
	_done = true
	LazerDialog.close_anim(self, _f, func(): closed.emit())
