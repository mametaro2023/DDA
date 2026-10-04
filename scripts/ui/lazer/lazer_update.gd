extends "res://scripts/ui/update_panel.gd"
## lazer 風のアップデートのパネル。ダウンロード・中止・入れ替えの処理と契約(setup(updater) / signal closed・cancelled / auto_start)は
## classic(update_panel.gd)のものをそのまま使い、見た目だけを lazer の確認ダイアログ(lazer_dialog.gd)にする。
## 版の変化(いま → 新しい版)を札で並べ、その下に更新内容、進み具合のバー、ボタン(主役が上)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerDialog = preload("res://scripts/ui/lazer/lazer_dialog.gd")

var _f: Dictionary


func _ready() -> void:
	var info: Dictionary = updater.info
	_f = LazerDialog.build(self, "download", LazerStyle.PINK, "新しいバージョンがあります", "", 600.0)
	_dim = _f.dim
	_panel = _f.panel
	var body: VBoxContainer = _f.body
	# 版: いまの版(うす札)→ 新しい版(ピンクの札)
	var ver := HBoxContainer.new()
	ver.alignment = BoxContainer.ALIGNMENT_CENTER
	ver.add_theme_constant_override("separation", 12)
	ver.add_child(LazerStyle.pill("v%s" % updater.current, Color(1, 1, 1, 0.12), 15, LazerStyle.TEXT_DIM))
	ver.add_child(LazerStyle.label("→", 18, LazerStyle.TEXT_MUTE, true))
	ver.add_child(LazerStyle.pill("v%s" % str(info.get("version", "?")), LazerStyle.PINK, 17))
	body.add_child(ver)
	var notes_box := PanelContainer.new()
	notes_box.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06), 1, 12, 18, 14))
	body.add_child(notes_box)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	notes_box.add_child(nv)
	nv.add_child(LazerStyle.label("更新内容", 12, LazerStyle.PINK, true))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 170)
	nv.add_child(scroll)
	var notes := LazerStyle.label(_clean_notes(str(info.get("notes", ""))), 14, LazerStyle.TEXT_DIM)
	notes.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(notes)
	# ダウンロードの進み具合
	_progress_box = VBoxContainer.new()
	_progress_box.add_theme_constant_override("separation", 6)
	_progress_box.visible = false
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.add_theme_stylebox_override("background", LazerStyle.box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 4))
	_bar.add_theme_stylebox_override("fill", LazerStyle.box(LazerStyle.PINK, Color(0, 0, 0, 0), 0, 4))
	_progress_box.add_child(_bar)
	_status = LazerStyle.label("", 13, LazerStyle.TEXT_DIM)
	_progress_box.add_child(_status)
	body.add_child(_progress_box)
	# ボタン(主役が上)。文字は text を描く(ダウンロード中に「キャンセル」などへ変わる)
	var self_update: bool = updater.can_self_update()
	_btn_update = LazerDialog.button(_f.buttons, "", LazerStyle.PINK, "download", Color(0.2, 0.04, 0.11), _start if self_update else func(): OS.shell_open(str(info.get("page", Updater.PAGE_URL))))
	_btn_update.text = "今すぐ更新" if self_update else "ダウンロードページを開く"
	_btn_later = LazerDialog.button(_f.buttons, "", Color(0.3, 0.28, 0.38), "clock", LazerStyle.TEXT, _on_later, "back")
	_btn_later.text = "後で"
	updater.progress.connect(_on_progress)
	updater.failed.connect(_on_failed)
	updater.staged.connect(_on_staged)
	UiStyle.close_on_outside_click(self, _panel, close_panel)
	if auto_start and self_update:
		_start.call_deferred()
	LazerDialog.open_anim(self, _f)


func _on_progress(frac: float, text: String) -> void:
	super._on_progress(frac, text)
	_btn_later.queue_redraw()


func _on_failed(msg: String) -> void:
	super._on_failed(msg)
	_status.add_theme_color_override("font_color", LazerStyle.RED)
	_btn_update.queue_redraw()
	_btn_later.queue_redraw()


func close_panel() -> void:
	if _closing or _busy:
		return
	_closing = true
	LazerDialog.close_anim(self, _f, func(): closed.emit())
