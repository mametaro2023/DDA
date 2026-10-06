extends "res://scripts/ui/classic_ui.gd"
## lazer 風の UI セット。作った画面から順に差し替え、まだ作っていない画面・パネルは classic のものをそのまま返す
## (途中でも、選んで遊べる)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const P_LazerMenu := "res://scripts/ui/lazer/lazer_menu.gd"
const P_LazerTitle := "res://scripts/ui/lazer/lazer_title.gd"
const P_LazerResult := "res://scripts/ui/lazer/lazer_result.gd"
const P_LazerGame := "res://scripts/ui/lazer/lazer_game.gd"
const P_LazerOptions := "res://scripts/ui/lazer/lazer_options.gd"
const P_LazerMulti := "res://scripts/ui/lazer/lazer_multi.gd"
const P_LazerHowto := "res://scripts/ui/lazer/lazer_howto.gd"
const P_LazerMods := "res://scripts/ui/lazer/lazer_mods.gd"
const P_LazerQuit := "res://scripts/ui/lazer/lazer_quit.gd"
const P_LazerUpdate := "res://scripts/ui/lazer/lazer_update.gd"
const P_LazerLoader := "res://scripts/ui/lazer/lazer_loader.gd"


func id() -> String:
	return "lazer"


func display_name() -> String:
	return "lazer 風"


## lazer 風の配色・フォントにする。classic の部品をそのまま使っているところ(パネルの中のふつうのボタンなど)も、この配色で描かれる。
func activate() -> void:
	UiStyle.set_palette({
		"BG": LazerStyle.BG, "PANEL": Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 1.0), "LINE": LazerStyle.LINE,
		"ACCENT": LazerStyle.PINK, "TEXT": LazerStyle.TEXT, "TEXT_DIM": Color(LazerStyle.TEXT_DIM.r, LazerStyle.TEXT_DIM.g, LazerStyle.TEXT_DIM.b, 0.86),
		"TEXT_FAINT": LazerStyle.TEXT_MUTE, "DANGER": LazerStyle.RED, "GOLD": LazerStyle.YELLOW, "GOOD": LazerStyle.GREEN,
	}, LazerStyle.font(), LazerStyle.font_bold())


func make_title() -> Control:
	return load(P_LazerTitle).new()


func make_multi() -> Control:
	return load(P_LazerMulti).new()


func make_options() -> Control:
	return load(P_LazerOptions).new()


func make_game() -> Node:
	return load(P_LazerGame).new()


func make_result() -> Control:
	return load(P_LazerResult).new()


func make_loader() -> Control:
	return load(P_LazerLoader).new()


func make_menu(pick: bool) -> Control:
	var m = load(P_LazerMenu).new()
	m.pick_mode = pick
	return m


func make_update() -> Control:
	return load(P_LazerUpdate).new()


func make_howto() -> Control:
	return load(P_LazerHowto).new()


func make_mods() -> Control:
	return load(P_LazerMods).new()


func make_quit() -> Control:
	return load(P_LazerQuit).new()
