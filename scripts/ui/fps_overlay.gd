extends CanvasLayer
## 画面右下の FPS 表示(開発・確認用。設定の「画面」で入り切り、F3 キーでも一時的に切り替えられる)。
##   描画 … 実際に画面へ描いたフレームの数(RenderingServer.frame_post_draw を数える)
##   処理 … 1 秒あたりの更新(メインループの _process)の回数
##   判定 … プレイ中だけ。弾の動きと当たり判定の計算(GameSim の 1 ステップ)の回数。1 ms 刻みなので、約 1000/s が正常で、
##          これが大きく落ちるときは処理が間に合っていない

const GameSim = preload("res://scripts/game/game_sim.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

const INTERVAL := 0.5   # 数え直す間隔(秒)

## 表示するか(設定の show_fps が起動時に入る。F3 で一時的に切り替えられる)
static var enabled := false

var _label: Label
var _loops := 0
var _draws := 0
var _t := 0.0
var _steps_before := 0


func _ready() -> void:
	layer = 95   # 音量メーター(90)より上、画面切り替えの幕(100)・カーソル(127)より下
	# 右下の隅に、薄い暗い札(背景の絵の上でも読める。行数が変わると、札の大きさも変わり、左と上へ伸びる)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -12.0
	panel.offset_top = -12.0
	panel.offset_right = -12.0
	panel.offset_bottom = -12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.02, 0.02, 0.05, 0.5), Color(1, 1, 1, 0.08), 1, 8, 10, 6))
	add_child(panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	panel.add_child(_label)
	RenderingServer.frame_post_draw.connect(_on_drawn)
	visible = enabled


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_drawn):
		RenderingServer.frame_post_draw.disconnect(_on_drawn)


func _on_drawn() -> void:
	_draws += 1


func _process(delta: float) -> void:
	visible = enabled
	if not enabled:
		_loops = 0
		_draws = 0
		_t = 0.0
		_steps_before = GameSim.steps_total
		return
	_loops += 1
	_t += delta
	if _t < INTERVAL:
		return
	var text := "描画 %d FPS\n処理 %d FPS" % [int(round(_draws / _t)), int(round(_loops / _t))]
	var steps := GameSim.steps_total - _steps_before
	if steps > 0:
		text += "\n判定 %d /s" % int(round(steps / _t))
	_label.text = text
	_loops = 0
	_draws = 0
	_t = 0.0
	_steps_before = GameSim.steps_total


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		enabled = not enabled
		get_viewport().set_input_as_handled()
