extends RefCounted
## UI セット(窓口)の基底。main.gd は、画面とパネルを必ずこれ経由で作る(クラスを直接 new しない)。
## 見た目の違う UI("classic" = 従来の UI など)は、これを継承して、同じ契約を満たす画面・パネルを返す。契約の一覧は docs/ui_plan.md の §2.3。
##
## 画面(Control。プレイ画面だけ Node2D)の契約:
##   var kind: String         "title" / "menu" / "multi" / "game" / "result"(main が、いま何の画面かを知るのに使う。クラスでは判定しない)
##   func on_overlay(open: bool, panel: Control = null)   任意。設定パネルが開いた・閉じた(画面は、自分の入力を止める・戻す)
##   var settings: Dictionary                              任意。持っていれば、設定パネルがこの辞書を直接編集する
##   func on_settings_changed(kind: String)                任意。設定パネルで値が変わった
## 画面ごとの signal・メソッドは、docs/ui_plan.md を参照。
##
## パネルの契約: signal closed / func close_panel()。
##   設定 … setup(settings: Dictionary) / signal changed(kind) / show_section(i) / refresh_size()
##   更新 … setup(updater) / signal cancelled / var auto_start
##   遊び方 … (共通の契約だけ)
##   MOD … setup(settings: Dictionary, level_cb: Callable) / signal changed / refresh_info() / var multi
##   確認 … setup(title, ok, cancel, body) / signal confirmed

## この UI セットの名前(設定の ui_style の値)
func id() -> String:
	return ""


## この UI セットを使い始める(UiSets.current が、UI セットが変わったときに呼ぶ)。UiStyle の配色・フォントを、この UI セットのものに切り替える。
func activate() -> void:
	pass


## 設定画面の選択肢に出す名前
func display_name() -> String:
	return id()


func make_title() -> Control:
	return null


## pick = true: マルチプレイの部屋の曲を選ぶモード(決定で、開始せずに選んだ内容を返す)
func make_menu(_pick: bool) -> Control:
	return null


func make_multi() -> Control:
	return null


func make_game() -> Node:
	return null


func make_result() -> Control:
	return null


func make_options() -> Control:
	return null


func make_update() -> Control:
	return null


func make_howto() -> Control:
	return null


func make_mods() -> Control:
	return null


## 確認パネル(既定の文言は「ゲームを終了しますか？」。setup で変える)
func make_quit() -> Control:
	return null
