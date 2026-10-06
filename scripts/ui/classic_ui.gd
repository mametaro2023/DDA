extends "res://scripts/ui/ui_set.gd"
## 従来の UI("classic")。既存の画面・パネルをそのまま返すだけ。

const P_TitleScreen := "res://scripts/ui/title_screen.gd"
const P_MenuScreen := "res://scripts/ui/menu_screen.gd"
const P_MultiScreen := "res://scripts/ui/multi_screen.gd"
const P_GameScreen := "res://scripts/game/game_screen.gd"
const P_ResultScreen := "res://scripts/ui/result_screen.gd"
const P_OptionsPanel := "res://scripts/ui/options_panel.gd"
const P_UpdatePanel := "res://scripts/ui/update_panel.gd"
const P_HowToPanel := "res://scripts/ui/howto_panel.gd"
const P_ModPanel := "res://scripts/ui/mod_panel.gd"
const P_QuitPanel := "res://scripts/ui/quit_panel.gd"
const P_ReplayList := "res://scripts/ui/replay_list.gd"
const UiStyle = preload("res://scripts/ui/ui_style.gd")


func id() -> String:
	return "classic"


func display_name() -> String:
	return "クラシック"


func activate() -> void:
	UiStyle.set_palette({})   # 従来の色・フォント


func make_title() -> Control:
	return load(P_TitleScreen).new()


func make_menu(pick: bool) -> Control:
	var m = load(P_MenuScreen).new()
	m.pick_mode = pick
	return m


func make_multi() -> Control:
	return load(P_MultiScreen).new()


func make_game() -> Node:
	return load(P_GameScreen).new()


func make_result() -> Control:
	return load(P_ResultScreen).new()


func make_options() -> Control:
	var p = load(P_OptionsPanel).new()
	p.theme = UiStyle.make_theme()
	return p


func make_update() -> Control:
	return load(P_UpdatePanel).new()


func make_howto() -> Control:
	return load(P_HowToPanel).new()


func make_mods() -> Control:
	var p = load(P_ModPanel).new()
	p.theme = UiStyle.make_theme()
	return p


func make_quit() -> Control:
	return load(P_QuitPanel).new()


## リプレイの一覧パネル(classic と lazer 風で共通。UiStyle の配色が、その UI セットの色になる)
func make_replays() -> Control:
	return load(P_ReplayList).new()
