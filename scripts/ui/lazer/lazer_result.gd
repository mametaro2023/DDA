extends "res://scripts/ui/lazer/lazer_screen.gd"
## lazer 風のリザルト画面。左に、ランクと周りのメーター・スコア・成績。右に、曲名・Lv・MOD、スコアの内訳(マルチプレイは参加者の成績の一覧)、体力の推移のグラフ。
## ゲームオーバーなら、ランクの代わりに到達度(メーターも到達度まで伸びる。撃破 MOD では、ボスを削った割合)。
## 中身(ランク・達成率・グラフの系列・一覧)は ResultModel(classic のリザルトと共通)。契約は classic のリザルト(result_screen.gd)と同じ:
## signal menu_requested / retry_requested、setup(stats, net)、skip_animation()。Enter / Esc でメニューへ、R でリトライ。

signal menu_requested
signal retry_requested

const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const RankMeter = preload("res://scripts/ui/rank_meter.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const RankStamp = preload("res://scripts/ui/rank_stamp.gd")
const ResultModel = preload("res://scripts/result_model.gd")

## メーターが伸び始めるまでの間(右の列が現れるのを待つ)と、伸びきるまでの時間(秒)。スコアの数字も、これに合わせて数え上がる
const FILL_DELAY := 0.55
const FILL_TIME := 1.7
## 体力グラフが描かれ始めるまでの間と、描ききるまでの時間(秒)
const GRAPH_DELAY := 0.7
const GRAPH_TIME := 1.9

var kind := "result"
var model := ResultModel.new()
var stats: Dictionary
var net                          # マルチプレイのとき: 通信層(他の人の最終成績が届くたびに、一覧を更新する)

var _left: Control               # 左のカード(ランクの衝撃で、ずんと沈む)
var _meter: Control
var _big: Label                  # メーターの中央の大きな文字(ランク / 到達度)
var _sub: Label                  # その下の小さな文字(達成率)
var _score_l: Label
var _score_target := 0.0
var _counters: Array = []        # 数字のカウントアップ: [Label, 目標値, 接尾辞, 開始までの間, 時間]
var _accent := Color.WHITE
var _fill := 0.0
var _fill_done := false
var _last_tick := -1
var _graph: Control
var _legend: HBoxContainer
var _board: VBoxContainer
var _buttons: Array = []


func setup(p_stats: Dictionary, p_net = null) -> void:
	stats = p_stats
	net = p_net if p_stats.has("mp") else null
	model.setup(p_stats, net)


func _ready() -> void:
	settings = Settings.load_all()
	_build_base()
	var bg_tex = stats.get("bg")   # 曲の背景画像(プレイ画面と同じ暗さ。クリアのフェードアウトのあと、同じ背景のまま結果が現れる)
	if bg_tex is Texture2D:
		set_background(bg_tex, true)
	_build_toolbar(["マルチ", "リザルト"] if model.is_mp else ["ソロ", "リザルト"])
	var failed := model.failed
	_accent = UiStyle.DANGER if failed else UiStyle.rank_color(model.rank)
	_build_left()
	_build_right()
	_build_footer()
	_build_footer_buttons()
	_intro()


# --- 左: ランク / 到達度と、周りのメーター・スコア・成績 ---

func _build_left() -> void:
	var failed := model.failed
	var left := Control.new()
	_place(left, 40, 64, 400, 552)
	_left = left
	left.draw.connect(func():
		left.draw_style_box(LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.88), Color(_accent.r, _accent.g, _accent.b, 0.55), 2, 18), Rect2(Vector2.ZERO, left.size)))
	var head := LazerStyle.label("GAME OVER" if failed else "CLEAR", 22, _accent, true)
	head.position = Vector2(0, 16)
	head.size = Vector2(400, 30)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(head)
	var meter := RankMeter.new()
	meter.position = Vector2(40, 46)
	meter.size = Vector2(320, 320)
	meter.ratio = model.ratio
	meter.scale_score = model.score_base
	meter.zones = not failed
	meter.accent = _accent
	left.add_child(meter)
	_meter = meter
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", -6)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(center)
	if failed:
		_big = LazerStyle.label("0%", 92, _accent, true)
		_sub = LazerStyle.label("削った" if stats.has("boss") else "到達", 17, LazerStyle.TEXT_DIM)
	else:
		_big = LazerStyle.label(model.rank, 112, _accent, true)
		_sub = LazerStyle.label("0.0%", 19, LazerStyle.TEXT_DIM)
	center.add_child(_centered(_big))
	center.add_child(_centered(_sub))
	if not failed:
		_big.modulate.a = 0.0   # ランクの文字は、メーターが伸びきってから叩きつける
	# スコア
	var cap := LazerStyle.label("SCORE", 13, LazerStyle.TEXT_MUTE)
	cap.position = Vector2(0, 378)
	cap.size = Vector2(400, 18)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(cap)
	if failed:
		var dash := LazerStyle.label("---", 48, LazerStyle.TEXT_MUTE, true)
		dash.position = Vector2(0, 394)
		dash.size = Vector2(400, 62)
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(dash)
	else:
		_score_target = float(model.score)
		_score_l = LazerStyle.label("0", 50, LazerStyle.TEXT, true)
		_score_l.position = Vector2(0, 392)
		_score_l.size = Vector2(400, 64)
		_score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_score_l.pivot_offset = Vector2(200, 32)
		left.add_child(_score_l)
	# 成績(3 つ並べる。撃破で倒したときは撃破タイムも)
	var tiles: Array = [
		_tile("GRAZE", str(int(stats.graze)), int(stats.graze), "", 0.7),
		_tile("被弾", "%d 回" % int(stats.hits), int(stats.hits), " 回", 0.8),
		_tile("ダメージ", "%d%%" % int(round(float(stats.damage) * 100.0)), int(round(float(stats.damage) * 100.0)), "%", 0.9),
	]
	var n := tiles.size()
	var tw := (368.0 - 10.0 * (n - 1)) / float(n)
	for i in range(n):
		var t: Control = tiles[i]
		t.position = Vector2(16.0 + i * (tw + 10.0), 474)
		t.size = Vector2(tw, 62)
		left.add_child(t)


## 成績の札(見出し + 数字。数字は数え上がる)。
func _tile(cap: String, text: String, value: int, suffix: String, delay: float) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0, 10, 12, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	v.add_child(LazerStyle.label(cap, 12, LazerStyle.TEXT_MUTE))
	var l := LazerStyle.label(text, 22, LazerStyle.TEXT, true)
	v.add_child(l)
	_counters.append([l, value, suffix, delay, 0.9])
	return p


func _centered(c: Control) -> Control:
	var w := CenterContainer.new()
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(c)
	return w


# --- 右: 曲名 / 内訳(または参加者の一覧)/ 体力のグラフ ---

func _build_right() -> void:
	var right := Control.new()
	_place(right, 470, 64, 770, 552)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := LazerStyle.label(str(stats.title), 22, LazerStyle.TEXT, true)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.position = Vector2(0, 0)
	t.size = Vector2(770, 32)
	right.add_child(t)
	# Lv・MOD の札
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.position = Vector2(0, 38)
	chips.size = Vector2(770, 28)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(LazerStyle.pill("★ %.2f" % float(stats.level), LazerStyle.level_color(float(stats.level)), 14))
	if bool(stats.get("new_best", false)) and not model.failed:   # この難易度の、これまでの最高を超えた(records.gd)
		chips.add_child(LazerStyle.pill("NEW BEST", LazerStyle.YELLOW, 14))
	if stats.has("mp"):
		chips.add_child(LazerStyle.pill("対戦" if stats.mp.mode == "versus" else "協力", LazerStyle.YELLOW, 14))
	for id in stats.get("mod_ids", []):
		var m := Mods.find(id)
		if not m.is_empty():
			var c: Color = m.color
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", LazerStyle.box(Color(c.r, c.g, c.b, 0.22), Color(c.r, c.g, c.b, 0.8), 1, 999, 10, 2))
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(LazerStyle.label(str(m.name), 14, c))
			chips.add_child(chip)
	right.add_child(chips)
	# 中段: 内訳(ひとり)/ 参加者の成績の一覧(マルチ)
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.82), Color(0, 0, 0, 0), 0, 14, 20, 14))
	mid.position = Vector2(0, 80)
	mid.size = Vector2(770, 188)
	right.add_child(mid)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mid.add_child(mv)
	if model.is_mp:
		_board = VBoxContainer.new()
		_board.add_theme_constant_override("separation", 6)
		mv.add_child(_board)
		_rebuild_board()
		if net != null:
			net.results_changed.connect(_on_results_changed)
	elif model.failed:
		mv.add_child(LazerStyle.label("ゲームオーバーのため、スコアは記録されません", 16, LazerStyle.TEXT_DIM))
	else:
		mv.add_child(_row("ベーススコア", UiStyle.fmt(int(round(model.score_base))), model.mod_note()))
		mv.add_child(_row("グレイズボーナス", "+ " + UiStyle.fmt(int(stats.score_graze)), ""))
		if stats.has("boss"):   # 撃破: 倒すまでの時間のボーナス
			mv.add_child(_row("撃破タイムボーナス", "+ " + UiStyle.fmt(int(stats.get("score_boss_time", 0.0))), ""))
		mv.add_child(_row("被ダメージ係数", "× %.3f" % float(stats.damage_factor), ""))
	if stats.has("boss") and bool(stats.boss.defeated):   # 撃破: 最初の発射から倒すまでの時間(m:ss)
		var sec := int(float(stats.boss.defeat_t))
		mv.add_child(_row("撃破タイム", "%d:%02d" % [sec / 60, sec % 60], ""))
	# 下段: 体力の推移
	var gp := PanelContainer.new()
	gp.add_theme_stylebox_override("panel", LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.82), Color(0, 0, 0, 0), 0, 14, 20, 12))
	gp.position = Vector2(0, 284)
	gp.size = Vector2(770, 268)
	right.add_child(gp)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 4)
	gp.add_child(gv)
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 16)
	gh.add_child(LazerStyle.label("体力の推移", 14, LazerStyle.TEXT_MUTE))
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 14)
	gh.add_child(_legend)
	gv.add_child(gh)
	_graph = HpGraph.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, 200)
	gv.add_child(_graph)
	_update_graph()
	# 右の列は右から滑り込み、体力のグラフは下から現れる
	UiStyle.pop_in(right, 0.1, Vector2(40, 0), 0.5)
	UiStyle.pop_in(gp, 0.3, Vector2(0, 24), 0.5)


## 内訳の 1 行: 見出し(と注記)を左、値を右に。
func _row(name: String, value: String, note: String) -> Control:
	var h := HBoxContainer.new()
	var l := LazerStyle.label(name, 17, LazerStyle.TEXT_DIM)
	l.custom_minimum_size = Vector2(230, 0)
	h.add_child(l)
	var n := LazerStyle.label(note, 13, LazerStyle.TEXT_MUTE)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var v := LazerStyle.label(value, 20, LazerStyle.TEXT, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(220, 0)
	h.add_child(v)
	return h


## 体力のグラフを作り直す(線・横軸・凡例は model が作る)。
func _update_graph() -> void:
	if _graph == null:
		return
	var g: Dictionary = model.graph(LazerStyle.BLUE)
	for c in _legend.get_children():
		_legend.remove_child(c)
		c.queue_free()
	for e in g.legend:
		if e.has("label"):
			_legend.add_child(LazerStyle.label(str(e.label), 13, LazerStyle.TEXT_DIM))
			continue
		var col: Color = e.color
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.draw.connect(func(): dot.draw_circle(Vector2(5, 5), 5.0, col))
		item.add_child(dot)
		item.add_child(LazerStyle.label(str(e.name), 13, LazerStyle.TEXT if bool(e.me) else LazerStyle.TEXT_DIM))
		_legend.add_child(item)
	_graph.set_data(g.series, g.t0, g.t1, stats.get("breaks", []), stats.get("hit_log", PackedFloat32Array()), GameSim.GAUGE_LOW_THRESHOLD)


## マルチプレイ: 参加者の成績の一覧(順位・WIN の判定は model)。まだ終えていない人は「プレイ中」。
func _rebuild_board() -> void:
	if _board == null:
		return
	for c in _board.get_children():
		_board.remove_child(c)
		c.queue_free()
	var mp: Dictionary = stats.mp
	var b: Dictionary = model.board()
	var versus: bool = b.versus
	var rows: Array = b.rows
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 40)
		var lead: bool = r.lead
		var accent: Color = LazerStyle.YELLOW if lead else LazerStyle.TEXT
		if versus:
			var pl := LazerStyle.label(str(r.place), 22, accent if r.res != null else LazerStyle.TEXT_MUTE, true)
			pl.custom_minimum_size = Vector2(26, 0)
			row.add_child(pl)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c: Color = MpGame.SLOT_COLORS[int(r.slot) % MpGame.SLOT_COLORS.size()]
		dot.draw.connect(func(): dot.draw_circle(Vector2(7, 7), 7.0, c))
		row.add_child(dot)
		var nm := LazerStyle.label(str(r.name), 19, accent if r.id == int(mp.my_id) or lead else LazerStyle.TEXT_DIM, r.id == int(mp.my_id))
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		if r.res == null:
			row.add_child(LazerStyle.label("プレイ中…", 16, LazerStyle.TEXT_MUTE))
		elif versus:
			var sc := LazerStyle.label(UiStyle.fmt(int(round(float(r.res.score)))), 26, accent, true)
			sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sc.custom_minimum_size = Vector2(150, 0)
			row.add_child(sc)
			row.add_child(LazerStyle.pill(str(r.rank), UiStyle.rank_color(str(r.rank)), 14))
			row.add_child(LazerStyle.label("被弾 %d 回 / ダメージ %d%%" % [int(r.res.hits), int(round(float(r.res.get("dmg", 0.0)) * 100.0))], 14, LazerStyle.TEXT_DIM))
			if lead and b.all_done and rows.size() > 1:
				row.add_child(LazerStyle.pill("WIN", LazerStyle.YELLOW, 14))
		else:
			row.add_child(LazerStyle.label("GRAZE %d" % int(r.res.graze), 16, LazerStyle.TEXT))
			row.add_child(LazerStyle.label("被弾 %d 回" % int(r.res.hits), 16, LazerStyle.TEXT))
			row.add_child(LazerStyle.label("ダメージ %d%%" % int(round(float(r.res.get("dmg", 0.0)) * 100.0)), 16, LazerStyle.TEXT_DIM))
		_board.add_child(row)


func _on_results_changed() -> void:
	_rebuild_board()
	_update_graph()


func _exit_tree() -> void:
	if net != null and net.results_changed.is_connected(_on_results_changed):
		net.results_changed.disconnect(_on_results_changed)


# --- 下のフッターと、入場の演出 ---

func _build_footer_buttons() -> void:
	if stats.has("mp"):   # マルチプレイ: ロビーへ戻る(リトライはない)
		var lobby := _footer_button("ロビーへ", LazerStyle.PINK, "back", 0, 200, func(): menu_requested.emit())
		lobby.set_meta("juice_sound", "back")
		_buttons.append(lobby)
	else:
		var back := _footer_button("メニューへ", LazerStyle.PINK, "back", 0, 210, func(): menu_requested.emit())
		back.set_meta("juice_sound", "back")
		_buttons.append(back)
		_buttons.append(_footer_button("リトライ", LazerStyle.PURPLE, "retry", 204, 190, func(): retry_requested.emit(), Color(0.1, 0.04, 0.2)))
	if UiStyle.animate:
		for b in _buttons:
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 現れるまでは押せない(見えないのにクリックが通らないように)
		get_tree().create_timer(1.6).timeout.connect(func():
			for b in _buttons:
				if is_instance_valid(b):
					b.mouse_filter = Control.MOUSE_FILTER_STOP)


## 左のカードは左から滑り込み、数字が数え上がり、メーターが伸びて、グラフが左から右へ描かれる。
func _intro() -> void:
	UiStyle.pop_in(_left, 0.05, Vector2(-40, 0), 0.5)
	if model.failed:
		UiSfx.play("deny", 0.9)
	for c in _counters:
		var lab: Label = c[0]
		var suffix: String = c[2]
		var last_shown := {"v": -1}
		var total := float(c[1])
		var set_text := func(v: float):
			lab.text = str(int(round(v))) + suffix
			if UiStyle.animate and int(round(v)) != last_shown.v and v > 0.0:   # 数字が変わるたびに、音程が上がっていく小さな音
				last_shown.v = int(round(v))
				UiSfx.play("count", 0.9 + 0.7 * clampf(v / maxf(total, 1.0), 0.0, 1.0), 0.8)
		UiStyle.tween_value(lab, 0.0, float(c[1]), float(c[4]), set_text, float(c[3]))
	UiStyle.tween_value(self, 0.0, 1.0, FILL_TIME, _set_fill, FILL_DELAY, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	UiStyle.tween_value(_graph, 0.0, 1.0, GRAPH_TIME, func(v: float): _graph.reveal = v, GRAPH_DELAY, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## メーターの伸び v(0..1)を、輪・スコア・達成率の数字に反映する。伸びきったら、ランクを叩きつける。
func _set_fill(v: float) -> void:
	_fill = v
	_meter.fill = v
	if _score_l != null:
		_score_l.text = UiStyle.fmt(int(round(_score_target * v)))
	if model.failed:
		_big.text = "%d%%" % int(round(model.ratio * 100.0 * v))
	else:
		_sub.text = "%.1f%%" % (model.ratio * 100.0 * v)
	var tick := int(v * 60.0)   # 数え上がる間、音程が上がる小さな音(1/60 刻み)
	if UiStyle.animate and tick != _last_tick and v > 0.0 and v < 1.0:
		_last_tick = tick
		UiSfx.play("count", 0.8 + 0.9 * v, 0.8)
	if v >= 1.0 and not _fill_done:
		_fill_done = true
		_on_fill_done()


func _on_fill_done() -> void:
	if not model.failed:
		RankStamp.stamp(self, _big, _accent, RankStamp.tier_of(model.rank), _left, 0.0)
	if _score_l != null and UiStyle.animate:   # スコアの数字がぽんと弾む
		UiSfx.play("tick", 2.0, 1.0)
		UiStyle.spring(_score_l, "scale", Vector2(1.07, 1.07), Vector2.ONE, 0.4)


## 開発用(スクリーンショット): 演出を待たず、最後の状態にする。
func skip_animation() -> void:
	_set_fill(1.0)
	_big.modulate.a = 1.0
	_big.scale = Vector2.ONE
	_graph.reveal = 1.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				menu_requested.emit()
			KEY_R:
				if not stats.has("mp"):
					retry_requested.emit()
