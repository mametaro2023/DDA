extends "res://scripts/ui/ui_set.gd"
## 従来の UI("classic")。既存の画面・パネルをそのまま返すだけ。

const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const MultiScreen = preload("res://scripts/ui/multi_screen.gd")
const GameScreen = preload("res://scripts/game/game_screen.gd")
const ResultScreen = preload("res://scripts/ui/result_screen.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const UpdatePanel = preload("res://scripts/ui/update_panel.gd")
const HowToPanel = preload("res://scripts/ui/howto_panel.gd")
const ModPanel = preload("res://scripts/ui/mod_panel.gd")
const QuitPanel = preload("res://scripts/ui/quit_panel.gd")
const ReplayList = preload("res://scripts/ui/replay_list.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")


func id() -> String:
	return "classic"


func display_name() -> String:
	return "クラシック"


func activate() -> void:
	UiStyle.set_palette({})   # 従来の色・フォント


func make_title() -> Control:
	return TitleScreen.new()


func make_menu(pick: bool) -> Control:
	var m := MenuScreen.new()
	m.pick_mode = pick
	return m


func make_multi() -> Control:
	return MultiScreen.new()


func make_game() -> Node:
	return GameScreen.new()


func make_result() -> Control:
	return ResultScreen.new()


func make_options() -> Control:
	var p := OptionsPanel.new()
	p.theme = UiStyle.make_theme()
	return p


func make_update() -> Control:
	return UpdatePanel.new()


func make_howto() -> Control:
	return HowToPanel.new()


func make_mods() -> Control:
	var p := ModPanel.new()
	p.theme = UiStyle.make_theme()
	return p


func make_quit() -> Control:
	return QuitPanel.new()


## リプレイの一覧パネル(classic と lazer 風で共通。UiStyle の配色が、その UI セットの色になる)
func make_replays() -> Control:
	return ReplayList.new()
