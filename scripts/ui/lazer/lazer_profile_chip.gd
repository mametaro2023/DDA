extends Button
## 上のツールバーの右端の、プレイヤーの名前とアイコン。押すと、名前とアイコンを変えるパネルが開く(Profile.open_cb)。
## 名前・アイコンは settings(画面が持っている辞書)から毎回読むので、どこで変えても、すぐ変わる。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const Profile = preload("res://scripts/profile.gd")

const W := 172.0
const H := 32.0
const NAME_W := 134.0
const R := 12.0

var _settings: Dictionary
var _shown := ""


func _init(settings: Dictionary) -> void:
	_settings = settings
	size = Vector2(W, H)
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "名前とアイコンを変える"
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	pressed.connect(func():
		if Profile.open_cb.is_valid():
			Profile.open_cb.call())


func _ready() -> void:
	for sig in [mouse_entered, mouse_exited, button_down, button_up]:
		sig.connect(queue_redraw)


func _process(_delta: float) -> void:
	var key := "%s|%s|%d" % [Profile.name_of(_settings), str(_settings.get("player_icon", "")), Profile._tex_time]
	if key != _shown:
		_shown = key
		queue_redraw()


func _draw() -> void:
	if is_hovered() or button_pressed:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.16 if button_pressed else 0.09))
	var name_s := Profile.name_of(_settings)
	var font := LazerStyle.font()
	while name_s.length() > 1 and font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > NAME_W:   # 入りきらないときは、後ろを「…」にする
		name_s = name_s.left(name_s.length() - 2) + "…"
	var tw := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(W - 2.0 * R - 10.0 - tw, H * 0.5 + 5.0), name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LazerStyle.TEXT if is_hovered() else LazerStyle.TEXT_DIM)
	Profile.draw_avatar(self, Vector2(W - R - 4.0, H * 0.5), R, str(_settings.get("player_icon", "")), Profile.name_of(_settings))
