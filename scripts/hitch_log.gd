extends Node
## 開発用: 止まり(長いフレーム)の記録。-- --hitch [しきい値 ms] で有効になり、しきい値(既定 25 ms)を超えたフレームを、
## 直前の入力・直前に鳴った UI の音・いまの画面と一緒に出力する(プチフリーズの原因を探す)。

const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

var threshold_ms := 25.0
var screen_of: Callable = func() -> String: return ""

var _last_us := 0
var _last_input := ""
var _frames := 0


func _ready() -> void:
	process_priority = -1000   # どのノードよりも先に測る
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_last_input = "key " + OS.get_keycode_string(event.keycode)
	elif event is InputEventMouseButton and event.pressed:
		_last_input = "mouse %d @%s" % [event.button_index, str(event.position.round())]


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frames += 1
	if _last_us > 0 and _frames > 3:
		var ms := (now - _last_us) / 1000.0
		if ms > threshold_ms:
			var sfx := ""
			if UiSfx.inst != null and not UiSfx.inst.log.is_empty():
				var l: Array = UiSfx.inst.log[UiSfx.inst.log.size() - 1]
				sfx = "%s(%dms ago)" % [str(l[0]), Time.get_ticks_msec() - int(l[1])]
			print("[hitch] %6.1f ms  t=%.2fs  screen=%s  input=%s  sfx=%s" % [ms, now / 1000000.0, screen_of.call(), _last_input, sfx])
	_last_us = now
