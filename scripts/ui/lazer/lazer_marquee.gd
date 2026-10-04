extends Control
## 1 行の文字。枠に入りきらないときは、少し止まってから左へ流れ、つなぎ目の後ろに同じ文字が続いて、ひと回りしたらまた止まる(長い曲名を全部読めるように)。
## 入りきるときは動かない。動き(UiStyle.animate)を切っていると流れない(枠で切れる)。

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")

const GAP := 64.0      # つなぎ目の空き
const SPEED := 42.0    # 流れる速さ(px/秒)
const PAUSE := 1.8     # 先頭で止まる時間(秒)

var text := "":
	set(v):
		text = v
		_l.text = v
		_l2.text = v
		_w = _l.get_minimum_size().x
		_x = 0.0
		_wait = PAUSE
		_layout()

var _l: Label
var _l2: Label
var _w := 0.0
var _x := 0.0
var _wait := PAUSE


func _init(font_size := 16, color := LazerStyle.TEXT, bold := false) -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_l = LazerStyle.label("", font_size, color, bold)
	_l2 = LazerStyle.label("", font_size, color, bold)
	add_child(_l)
	add_child(_l2)
	resized.connect(_layout)


func _overflow() -> bool:
	return _w > size.x + 0.5


func _layout() -> void:
	_l.size.y = size.y
	_l2.size.y = size.y
	_l.position = Vector2(-_x, 0)
	_l2.position = Vector2(-_x + _w + GAP, 0)
	_l2.visible = _overflow()
	queue_redraw()


func _process(delta: float) -> void:
	if not _overflow() or not UiStyle.animate:
		if _x != 0.0:
			_x = 0.0
			_layout()
		return
	if _wait > 0.0:
		_wait -= delta
		return
	_x += SPEED * delta
	if _x >= _w + GAP:   # ひと回りした: 先頭に戻って、また止まる
		_x = 0.0
		_wait = PAUSE
	_layout()
