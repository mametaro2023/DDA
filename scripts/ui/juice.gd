extends Node
## 「触って気持ちいい」を、すべてのボタン・スライダーへ自動でつける(画面ごとのコードを書き換えずに済むよう、ツリーに入ったものへ後からつける)。
##   ボタン … ホバーで弾むように少し大きくなり(音つき)、押すとぎゅっと縮み、離すと行き過ぎてから戻る。押した瞬間にクリック音。
##   スライダー … 動かすたびに、値に応じた音程の小さな音(音階になる)。つかむと小さく鳴る。
## 文字や位置は変えず、scale だけを動かす(レイアウトに影響しない)。点滅・揺れ続けるものはない。
## 外したいノードには set_meta("no_juice", true)。クリック音の種類は set_meta("juice_sound", "confirm" / "back" ...)で変えられる。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const PRESS_SCALE := 0.94


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		_juice_button(n as BaseButton)
	elif n is HSlider:
		_juice_slider(n as HSlider)


func _eligible(c: Control) -> bool:
	return not c.has_meta("no_juice") and c.get_window() == get_tree().root


## ホバーしたときの大きさ(幅が広いボタンほど控えめ。およそ左右に 4px ずつ広がる)。
static func hover_scale_of(c: Control) -> float:
	return 1.0 + clampf(8.0 / maxf(c.size.x, 1.0), 0.015, 0.06)


## 既定のクリック音: 「戻る」「閉じる」系は back、それ以外は click(set_meta("juice_sound", ...) があればそれ)。
static func click_sound_of(b: BaseButton) -> String:
	if b.has_meta("juice_sound"):
		return str(b.get_meta("juice_sound"))
	var text: String = b.text if b is Button else ""
	if text.begins_with("◀") or text.contains("閉じる") or text.contains("キャンセル") or text.contains("あとで"):
		return "back"
	return "click"


func _go(c: Control, to: float, dur: float, back := false) -> void:
	if not UiStyle.animate or not c.is_inside_tree():
		c.scale = Vector2(to, to)
		return
	c.pivot_offset = c.size * 0.5
	var old = c.get_meta("juice_tween") if c.has_meta("juice_tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2(to, to), dur).set_trans(Tween.TRANS_BACK if back else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("juice_tween", t)


func _juice_button(b: BaseButton) -> void:
	if not _eligible(b):
		return
	b.mouse_entered.connect(func():
		if b.disabled:
			return
		UiSfx.play("hover", randf_range(0.97, 1.05))
		_go(b, hover_scale_of(b), 0.24, true))
	b.mouse_exited.connect(func():
		_go(b, 1.0, 0.2))
	b.button_down.connect(func():
		var snd := click_sound_of(b)
		UiSfx.play(snd, randf_range(0.97, 1.03))
		_go(b, PRESS_SCALE, 0.07))
	b.button_up.connect(func():
		var inside := b.get_global_rect().has_point(b.get_global_mouse_position())
		_go(b, hover_scale_of(b) if inside else 1.0, 0.32, true))


func _juice_slider(s: HSlider) -> void:
	if not _eligible(s):
		return
	var held := {"v": false}
	s.mouse_entered.connect(func(): UiSfx.play("hover", 1.1))
	s.drag_started.connect(func():
		held.v = true
		UiSfx.play("select", 1.2))
	s.drag_ended.connect(func(_changed: bool): held.v = false)
	s.value_changed.connect(func(v: float):
		# 人が動かしているときだけ鳴らす(画面を開いたときに、コードが値を入れても鳴らさない)
		if not s.is_visible_in_tree() or not (held.v or s.get_global_rect().has_point(s.get_global_mouse_position())):
			return
		var span := s.max_value - s.min_value
		var t := (v - s.min_value) / span if span > 0.0 else 0.0
		UiSfx.play("tick", UiSfx.scale_pitch(t, 1.6) * 0.8))
