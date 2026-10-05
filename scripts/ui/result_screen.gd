extends Control
## リザルト画面。左上にランクと、その周りの円状のメーター(点数の達成率まで伸びる)、右上にスコアと内訳・成績、下に体力の推移のグラフ。
## ゲームオーバーなら、ランクの代わりに到達度(メーターも到達度まで伸びる。撃破 MOD では、ボスを削った割合)。マルチプレイは、右に参加者の成績の一覧、グラフに参加者の体力を重ねる。

signal menu_requested
signal retry_requested
signal replay_requested

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const RankMeter = preload("res://scripts/ui/rank_meter.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")
const ResultModel = preload("res://scripts/result_model.gd")
const RankStamp = preload("res://scripts/ui/rank_stamp.gd")

## メーターが伸び始めるまでの間(右の列が現れるのを待つ)と、伸びきるまでの時間(秒)。スコアの数字も、これに合わせて数え上がる
const FILL_DELAY := 0.55
const FILL_TIME := 1.7
## 体力グラフが描かれ始めるまでの間と、描ききるまでの時間(秒)
const GRAPH_DELAY := 0.7
const GRAPH_TIME := 1.9

## ランク・達成率・体力グラフの系列・マルチプレイの一覧を作る中身(UI なし。lazer のリザルトと共通。scripts/result_model.gd)
var model := ResultModel.new()
var stats: Dictionary
var net                          # マルチプレイのとき: 通信層(他の人の最終成績が届くたびに、一覧を更新する)
var _board: VBoxContainer         # マルチプレイの成績の一覧

var _score_l: Label
var _counters: Array = []         # 数字のカウントアップ: [Label, 目標値, 接尾辞, 開始までの間, 時間]
var _score_target := 0.0
var _fill := 0.0                  # メーターの伸び 0..1(スコア・達成率の数字も、これに合わせる)
var _ratio := 0.0                 # 最終的な達成率(ゲームオーバーなら到達度)
var _fill_done := false
var _last_tick := -1
var _left: Control            # 左のランクのパネル(スタンプの衝撃で、ずんと揺れる)
var _accent := Color.WHITE
var _big: Label               # メーターの中央の大きな文字(ランク / 到達度)
var _sub: Label               # その下の小さな文字(達成率)
var _meter: Control
var _graph: Control
var _legend: HBoxContainer
var _rank := "-"


## 画面の種類(main が、いま何の画面かを知るのに使う。ui_set.gd の契約)
var kind := "result"


func setup(p_stats: Dictionary, p_net = null) -> void:
	stats = p_stats
	net = p_net if p_stats.has("mp") else null
	model.setup(p_stats, net)


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	# 曲の背景画像(プレイ画面と同じ暗さ。クリアのフェードアウトのあと、同じ背景のまま結果が現れる)
	var bg_tex = stats.get("bg")
	if bg_tex is Texture2D:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.modulate = Color(0.28, 0.28, 0.32)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	var amb := Ambient.new()
	amb.strength = 0.8
	add_child(amb)

	var failed: bool = model.failed
	var score: int = model.score
	var score_base: float = model.score_base
	_rank = model.rank
	var accent := UiStyle.DANGER if failed else UiStyle.rank_color(_rank)
	_accent = accent
	_ratio = model.ratio

	# --- 左: ランク / 到達度と、周りのメーター ---
	var left := Control.new()
	left.position = Vector2(60, 56)
	left.size = Vector2(460, 394)
	add_child(left)
	_left = left
	var lp := PanelContainer.new()
	lp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lp.add_theme_stylebox_override("panel", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.05), Color(accent.r, accent.g, accent.b, 0.35), 1, 8))
	left.add_child(lp)
	var head := UiStyle.label("GAME OVER" if failed else "CLEAR", 24, accent, true)
	head.position = Vector2(0, 12)
	head.size = Vector2(460, 34)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(head)
	var meter := RankMeter.new()
	meter.position = Vector2(60, 44)
	meter.size = Vector2(340, 340)
	meter.ratio = _ratio
	meter.scale_score = score_base
	meter.zones = not failed
	meter.accent = accent
	left.add_child(meter)
	_meter = meter
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", -6)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(center)
	if failed:
		_big = UiStyle.label("0%", 100, accent, true)
		_sub = UiStyle.label("削った" if stats.has("boss") else "到達", 18, UiStyle.TEXT_DIM)
	else:
		_big = UiStyle.label(_rank, 124, accent, true)
		_sub = UiStyle.label("0.0%", 20, UiStyle.TEXT_DIM)
	center.add_child(_centered(_big))
	center.add_child(_centered(_sub))
	if not failed:
		_big.modulate.a = 0.0   # ランクの文字は、メーターが伸びきってから叩きつける

	# 左パネルは左から滑り込む
	UiStyle.pop_in(left, 0.05, Vector2(-40, 0), 0.5)
	if failed:
		UiSfx.play("deny", 0.9)

	# --- 右: 曲名 / スコア / 内訳 / 成績 ---
	var right := VBoxContainer.new()
	right.position = Vector2(560, 50)
	right.size = Vector2(660, 400)
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	var t := UiStyle.label(stats.title, 18, UiStyle.TEXT_DIM)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(t)
	# Lv・MOD のチップ
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(UiStyle.chip("Lv %.2f" % stats.level, UiStyle.level_color(stats.level)))
	if stats.has("mp"):
		chips.add_child(UiStyle.chip("対戦" if stats.mp.mode == "versus" else "協力", UiStyle.GOLD))
	if bool(stats.get("keyboard", false)):   # キーボードで遊んだ(マウスのときは出さない)
		chips.add_child(UiStyle.chip("キーボード", UiStyle.TEXT_DIM))
	for id in stats.get("mod_ids", []):
		var m := Mods.find(id)
		if not m.is_empty():
			chips.add_child(UiStyle.chip(m.name, m.color))
	right.add_child(chips)

	right.add_child(UiStyle.caption("SCORE"))
	if failed:
		right.add_child(UiStyle.label("---", 64, UiStyle.TEXT_FAINT, true))
	else:
		_score_target = float(score)
		_score_l = UiStyle.label("0", 64, UiStyle.TEXT, true)
		right.add_child(_score_l)
	right.add_child(UiStyle.hline())
	if stats.has("mp"):   # マルチプレイ: 参加者の成績の一覧(他の人が終えるたびに更新)
		_board = VBoxContainer.new()
		_board.add_theme_constant_override("separation", 6)
		right.add_child(_board)
		_rebuild_board()
		if net != null:
			net.results_changed.connect(_on_results_changed)
	else:
		if not failed:
			right.add_child(_row("ベーススコア", UiStyle.fmt(int(round(score_base))), _mod_note()))
			right.add_child(_row("グレイズボーナス", "+ " + UiStyle.fmt(int(stats.score_graze)), ""))
			if stats.has("boss"):   # 撃破: 倒すまでの時間のボーナス
				right.add_child(_row("撃破タイムボーナス", "+ " + UiStyle.fmt(int(stats.get("score_boss_time", 0.0))), ""))
			right.add_child(_row("被ダメージ係数", "× %.3f" % stats.damage_factor, ""))
			right.add_child(UiStyle.hline())
		# 成績(3 つ並べる)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 40)
		grid.add_child(_stat("GRAZE", int(stats.graze), "", 0.7))
		grid.add_child(_stat("被弾", int(stats.hits), " 回", 0.8))
		grid.add_child(_stat("ダメージ", int(round(float(stats.damage) * 100.0)), "%", 0.9))   # ゲージ満タン = 100%(回復は引かない)
		if stats.has("boss") and bool(stats.boss.defeated):   # 撃破: 最初の発射から倒すまでの時間(m:ss)
			var sec := int(float(stats.boss.defeat_t))
			var bt := VBoxContainer.new()
			bt.add_theme_constant_override("separation", 2)
			bt.add_child(UiStyle.caption("撃破タイム"))
			bt.add_child(UiStyle.label("%d:%02d" % [sec / 60, sec % 60], 26, UiStyle.TEXT, true))
			grid.add_child(bt)
		right.add_child(grid)

	# --- 下: 体力の推移 ---
	var gp := PanelContainer.new()
	gp.position = Vector2(60, 466)
	gp.size = Vector2(1160, 152)
	gp.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.3), UiStyle.LINE, 1, 8, 16, 10))
	add_child(gp)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 2)
	gp.add_child(gv)
	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 16)
	gh.add_child(UiStyle.caption("HP"))
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 14)
	gh.add_child(_legend)
	gv.add_child(gh)
	_graph = HpGraph.new()
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, 100)
	gv.add_child(_graph)
	_update_graph()

	# 下部のボタン(Enter / R のキーでも同じ操作ができる)。主ボタン(次へ進む「メニューへ」「ロビーへ」)が右下、リトライはその左
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 12)
	hint.position = Vector2(1220, 626)   # 右端をグラフの右端にそろえる(幅が増えたら左へ伸びる)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var specs: Array = [["ロビーへ", menu_requested, true]] if stats.has("mp") else [["リトライ", retry_requested, false], ["メニューへ", menu_requested, true]]
	if not stats.has("mp") and str(stats.get("replay", "")) != "":
		specs.insert(1, ["リプレイ", replay_requested, false])   # このプレイの記録を見返す(P キーでも)
	if bool(stats.get("video", false)):   # リプレイの動画の最後に撮るときは、ボタンを出さない
		specs = []
	for spec in specs:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 48)
		if spec[2]:
			UiStyle.style_primary(b)
		var sig: Signal = spec[1]
		b.pressed.connect(func(): sig.emit())
		if UiStyle.animate:
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 現れるまでは押せない(見えないのにクリックが通らないように)
		hint.add_child(b)
	add_child(hint)
	if UiStyle.animate:
		var enable := create_tween()   # 画面に結び付いた待ち(画面を離れたら、一緒に消える。タイマーだと、離れたあとに呼ばれて、解放済みの物を触る)
		enable.tween_interval(1.2 + 0.08 * hint.get_child_count() + 0.4)
		enable.tween_callback(func():
			for b in hint.get_children():
				b.mouse_filter = Control.MOUSE_FILTER_STOP)

	# 右の列は右から滑り込み、中身が上から順に現れ、数字が数え上がる。グラフは下から現れて、左から右へ描かれる
	UiStyle.pop_in(right, 0.1, Vector2(40, 0), 0.5)
	var j := 0
	for c in right.get_children():
		UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.35, 0.2 + 0.07 * j)
		j += 1
	UiStyle.pop_in(gp, 0.3, Vector2(0, 24), 0.5)
	var bk := 0
	for b in hint.get_children():   # 下のボタンは、最後に弾んで現れる
		UiStyle.pop_scale(b, 0.8, 0.4, 1.2 + 0.08 * bk)
		bk += 1
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

	# メーターの伸び(ランクの周りの輪・スコア・達成率が一緒に進む)と、グラフの描き進み
	UiStyle.tween_value(self, 0.0, 1.0, FILL_TIME, _set_fill, FILL_DELAY, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	UiStyle.tween_value(_graph, 0.0, 1.0, GRAPH_TIME, func(v: float): _graph.reveal = v, GRAPH_DELAY, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


## メーターの伸び v(0..1)を、輪・スコア・達成率の数字に反映する。伸びきったら、ランクを叩きつける。
func _set_fill(v: float) -> void:
	_fill = v
	_meter.fill = v
	if _score_l != null:
		var shown := int(round(_score_target * v))
		_score_l.text = UiStyle.fmt(shown)
	if bool(stats.failed):
		_big.text = "%d%%" % int(round(_ratio * 100.0 * v))
	else:
		_sub.text = "%.1f%%" % (_ratio * 100.0 * v)
	var tick := int(v * 60.0)   # 数え上がる間、音程が上がる小さな音(1/60 刻み)
	if UiStyle.animate and tick != _last_tick and v > 0.0 and v < 1.0:
		_last_tick = tick
		UiSfx.play("count", 0.8 + 0.9 * v, 0.8)
	if v >= 1.0 and not _fill_done:
		_fill_done = true
		_on_fill_done()


func _on_fill_done() -> void:
	if not bool(stats.failed):
		RankStamp.stamp(self, _big, _accent, RankStamp.tier_of(_rank), _left, 0.0)   # ランクの叩きつけ(scripts/ui/rank_stamp.gd。lazer のリザルトと共通)
	if _score_l != null and UiStyle.animate:   # スコアの数字がぽんと弾む
		UiSfx.play("tick", 2.0, 1.0)
		_score_l.pivot_offset = Vector2(0.0, _score_l.size.y * 0.5)
		UiStyle.spring(_score_l, "scale", Vector2(1.07, 1.07), Vector2.ONE, 0.4)


## 開発用(スクリーンショット): 演出を待たず、最後の状態にする。
func skip_animation() -> void:
	_set_fill(1.0)
	_big.modulate.a = 1.0
	_big.scale = Vector2.ONE
	_graph.reveal = 1.0


## MOD によるベーススコアの倍率の注記(なければ空)。
func _mod_note() -> String:
	return model.mod_note()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _centered(c: Control) -> Control:
	var w := CenterContainer.new()
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(c)
	return w


## 内訳の 1 行: 見出し(と注記)を左、値を右に。
func _row(name: String, value: String, note: String) -> Control:
	var h := HBoxContainer.new()
	var l := UiStyle.label(name, 16, UiStyle.TEXT_DIM)
	l.custom_minimum_size = Vector2(190, 0)
	h.add_child(l)
	var n := UiStyle.label(note, 12, UiStyle.TEXT_FAINT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var v := UiStyle.label(value, 18, UiStyle.TEXT, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.custom_minimum_size = Vector2(190, 0)
	h.add_child(v)
	return h


func _stat(cap: String, value: int, suffix: String, delay: float) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UiStyle.caption(cap))
	var l := UiStyle.label(str(value) + suffix, 26, UiStyle.TEXT, true)
	v.add_child(l)
	_counters.append([l, value, suffix, delay, 0.9])
	return v


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE:
				menu_requested.emit()
			KEY_R:
				if not stats.has("mp"):
					retry_requested.emit()
			KEY_P:
				if not stats.has("mp") and str(stats.get("replay", "")) != "":
					replay_requested.emit()


func _exit_tree() -> void:
	if net != null and net.results_changed.is_connected(_on_results_changed):
		net.results_changed.disconnect(_on_results_changed)


func _on_results_changed() -> void:
	_rebuild_board()
	_update_graph()


## 体力のグラフを作り直す。ひとりと協力は自分の(チームの)体力の 1 本、対戦は参加者の体力を色分けして重ねる(他の人の分は届いたものから)。
## 線・横軸の範囲・凡例は model が作る。ここは、凡例の部品を並べて、グラフに渡すだけ。
func _update_graph() -> void:
	if _graph == null:
		return
	var g: Dictionary = model.graph(UiStyle.ACCENT)
	for c in _legend.get_children():
		c.queue_free()
		_legend.remove_child(c)
	for e in g.legend:
		if e.has("label"):
			_legend.add_child(UiStyle.label(str(e.label), 12, UiStyle.TEXT_DIM))
			continue
		var col: Color = e.color
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.draw.connect(func(): dot.draw_circle(Vector2(5, 5), 5.0, col))
		item.add_child(dot)
		item.add_child(UiStyle.label(str(e.name), 12, UiStyle.TEXT if bool(e.me) else UiStyle.TEXT_DIM))
		_legend.add_child(item)
	_graph.set_data(g.series, g.t0, g.t1, stats.get("breaks", []), stats.get("hit_log", PackedFloat32Array()), float(stats.get("low_line", GameSim.GAUGE_LOW_THRESHOLD)))


## マルチプレイ: 参加者の成績の一覧。対戦はスコアの高い順(1 位に色。全員が終えたら WIN)、協力は 1 人ずつの GRAZE・被弾。
## 順位・WIN の判定は model が行い(自分の分は、通信を待たずにこの画面の値を使う)、ここは行を並べるだけ。まだ終えていない人は「プレイ中」。
func _rebuild_board() -> void:
	if _board == null:
		return
	for c in _board.get_children():
		c.queue_free()
		_board.remove_child(c)
	var mp: Dictionary = stats.mp
	var b: Dictionary = model.board()
	var versus: bool = b.versus
	var rows: Array = b.rows
	for r in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 36)
		var lead: bool = r.lead
		var accent: Color = UiStyle.GOLD if lead else UiStyle.TEXT
		if versus:
			var pl := UiStyle.label(str(r.place), 20, accent if r.res != null else UiStyle.TEXT_FAINT, true)
			pl.custom_minimum_size = Vector2(22, 0)
			row.add_child(pl)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var c: Color = MpGame.SLOT_COLORS[int(r.slot) % MpGame.SLOT_COLORS.size()]
		dot.draw.connect(func(): dot.draw_circle(Vector2(6, 6), 6.0, c))
		row.add_child(dot)
		var nm := UiStyle.label(str(r.name), 18, accent if r.id == int(mp.my_id) or lead else UiStyle.TEXT_DIM, r.id == int(mp.my_id))
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		if r.res == null:
			row.add_child(UiStyle.label("プレイ中…", 15, UiStyle.TEXT_FAINT))
		elif versus:
			var sc := UiStyle.label(UiStyle.fmt(int(round(float(r.res.score)))), 24, accent, true)
			sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sc.custom_minimum_size = Vector2(150, 0)
			row.add_child(sc)
			row.add_child(UiStyle.chip(r.rank, UiStyle.rank_color(r.rank)))
			row.add_child(UiStyle.label("被弾 %d 回 / ダメージ %d%%" % [int(r.res.hits), int(round(float(r.res.get("dmg", 0.0)) * 100.0))], 13, UiStyle.TEXT_DIM))
			if lead and b.all_done and rows.size() > 1:
				row.add_child(UiStyle.chip("WIN", UiStyle.GOLD))
		else:
			row.add_child(UiStyle.label("GRAZE %d" % int(r.res.graze), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("被弾 %d 回" % int(r.res.hits), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("ダメージ %d%%" % int(round(float(r.res.get("dmg", 0.0)) * 100.0)), 15, UiStyle.TEXT_DIM))
		_board.add_child(row)
