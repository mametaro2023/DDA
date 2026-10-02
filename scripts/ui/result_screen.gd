extends Control
## リザルト画面。左上にランクと、その周りの円状のメーター(点数の達成率まで伸びる)、右上にスコアと内訳・成績、下に体力の推移のグラフ。
## ゲームオーバーなら、ランクの代わりに到達度(メーターも到達度まで伸びる)。マルチプレイは、右に参加者の成績の一覧、グラフに参加者の体力を重ねる。

signal menu_requested
signal retry_requested

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const UiFx = preload("res://scripts/ui/ui_fx.gd")
const RankMeter = preload("res://scripts/ui/rank_meter.gd")
const HpGraph = preload("res://scripts/ui/hp_graph.gd")

## メーターが伸び始めるまでの間(右の列が現れるのを待つ)と、伸びきるまでの時間(秒)。スコアの数字も、これに合わせて数え上がる
const FILL_DELAY := 0.55
const FILL_TIME := 1.7
## 体力グラフが描かれ始めるまでの間と、描ききるまでの時間(秒)
const GRAPH_DELAY := 0.7
const GRAPH_TIME := 1.9

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


func setup(p_stats: Dictionary, p_net = null) -> void:
	stats = p_stats
	net = p_net if p_stats.has("mp") else null


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

	var failed: bool = stats.failed
	# クリアしたときだけスコアが残る。ランクは、ノーミスなら SS、それ以外は達成率(スコア ÷ ベーススコア)で S〜F
	var score: int = int(round(stats.score))   # プレイ中の表示(四捨五入)と同じにする。切り捨てだと 1 ずれる
	var score_base: float = float(stats.get("score_base", 1000000.0))
	_rank = GameSim.rank_of(failed, int(stats.hits), float(stats.score), score_base)
	var accent := UiStyle.DANGER if failed else UiStyle.rank_color(_rank)
	_accent = accent
	_ratio = clampf(float(stats.progress), 0.0, 1.0) if failed else clampf(float(stats.score) / maxf(score_base, 1.0), 0.0, 1.0)

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
		_sub = UiStyle.label("到達", 18, UiStyle.TEXT_DIM)
	else:
		_big = UiStyle.label(_rank, 124, accent, true)
		_sub = UiStyle.label("0.0%", 20, UiStyle.TEXT_DIM)
	center.add_child(_centered(_big))
	center.add_child(_centered(_sub))
	if not failed:
		var note := UiStyle.label("ノーミスなら SS", 12, UiStyle.TEXT_FAINT)
		note.position = Vector2(16, 18)
		note.size = Vector2(150, 20)
		left.add_child(note)
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
			right.add_child(_row("被ダメージ係数", "× %.3f" % stats.damage_factor, ""))
			right.add_child(UiStyle.hline())
		# 成績(3 つ並べる)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 40)
		grid.add_child(_stat("GRAZE", int(stats.graze), "", 0.7))
		grid.add_child(_stat("被弾", int(stats.hits), " 回", 0.8))
		grid.add_child(_stat("被弾時間", int(stats.hit_ms), " ms", 0.9))
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

	# 下部のボタン(Enter / R のキーでも同じ操作ができる)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 12)
	hint.position = Vector2(60, 634)
	for spec in ([["ロビーへ", menu_requested]] if stats.has("mp") else [["メニューへ", menu_requested], ["リトライ", retry_requested]]):
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 40)
		var sig: Signal = spec[1]
		b.pressed.connect(func(): sig.emit())
		hint.add_child(b)
	add_child(hint)

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
		_stamp(_big, 0.0)
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


## ランクの文字を叩きつける: 大きく透明な状態から、加速しながら縮んで着地 → 衝撃波・粒・低い音・パネルがずんと沈む。
func _stamp(big: Label, delay: float) -> void:
	big.pivot_offset = big.get_minimum_size() * 0.5
	if not UiStyle.animate or not is_inside_tree():
		big.modulate.a = 1.0
		return
	big.modulate.a = 0.0
	big.scale = Vector2(2.8, 2.8)
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): big.modulate.a = 0.9)
	t.tween_property(big, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(big, "modulate:a", 1.0, 0.2)
	t.tween_callback(func():
		var at := big.get_global_rect().get_center()
		UiFx.ring(self, at, _accent, 40.0, 330.0, 0.7, 4.0)
		UiFx.ring(self, at, Color(1, 1, 1, 0.5), 20.0, 200.0, 0.5, 2.0)
		UiFx.burst(self, at, _accent, 26, 560.0, 0.9, 4.6, 160.0, 1.9)
		UiSfx.play("stamp")
		_left.pivot_offset = _left.size * 0.5   # パネルが、ずんと沈んで戻る
		var th := _left.create_tween()
		th.tween_property(_left, "scale", Vector2(0.985, 0.985), 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		th.tween_property(_left, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## MOD によるベーススコアの倍率の注記(なければ空)。
func _mod_note() -> String:
	var base: float = stats.get("score_base", 1000000.0)
	if absf(base - 1000000.0) < 1.0:
		return ""
	return "MOD  ×%.4f" % (base / 1000000.0)


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


func _exit_tree() -> void:
	if net != null and net.results_changed.is_connected(_on_results_changed):
		net.results_changed.disconnect(_on_results_changed)


func _on_results_changed() -> void:
	_rebuild_board()
	_update_graph()


## 体力のグラフを作り直す。ひとりと協力は自分の(チームの)体力の 1 本、対戦は参加者の体力を色分けして重ねる(他の人の分は届いたものから)。
func _update_graph() -> void:
	if _graph == null:
		return
	var series: Array = []
	var own := HpGraph.points_from_log(stats.get("hp_log", PackedFloat32Array()), float(stats.get("hp_step", 0.25)),
		float(stats.get("hp_t_end", 0.0)), float(stats.get("hp_end", 0.0)))
	var failed: bool = stats.failed
	var versus: bool = stats.has("mp") and stats.mp.mode == "versus"
	for c in _legend.get_children():
		c.queue_free()
		_legend.remove_child(c)
	if versus:
		var res: Dictionary = net.results if net != null else {}
		for p in stats.mp.players:
			var col: Color = MpGame.SLOT_COLORS[int(p.slot) % MpGame.SLOT_COLORS.size()]
			var me: bool = int(p.id) == int(stats.mp.my_id)
			var pts := PackedVector2Array()
			var dead := false
			if me:
				pts = own
				dead = failed
			elif res.has(p.id) and res[p.id].get("hp", []) is Array and (res[p.id].hp as Array).size() >= 2:
				pts = HpGraph.points_from_samples(res[p.id].hp, float(res[p.id].get("dur", 0.0)))
				dead = bool(res[p.id].get("failed", false))
			if pts.size() >= 2:
				series.append({"pts": pts, "color": col, "thick": 3.0 if me else 2.0, "fill": me, "end_mark": dead})
			var item := HBoxContainer.new()
			item.add_theme_constant_override("separation", 5)
			var dot := Control.new()
			dot.custom_minimum_size = Vector2(10, 10)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.draw.connect(func(): dot.draw_circle(Vector2(5, 5), 5.0, col))
			item.add_child(dot)
			item.add_child(UiStyle.label(str(p.name), 12, UiStyle.TEXT if me else UiStyle.TEXT_DIM))
			_legend.add_child(item)
	else:
		series.append({"pts": own, "color": UiStyle.ACCENT, "thick": 3.0, "by_hp": true, "end_mark": failed})
		if stats.has("mp"):
			_legend.add_child(UiStyle.label("チーム共通の体力", 12, UiStyle.TEXT_DIM))
	var t1 := 1.0
	for s in series:
		t1 = maxf(t1, (s.pts as PackedVector2Array)[(s.pts as PackedVector2Array).size() - 1].x)
	var ff: float = float(stats.get("first_fire", -1.0))
	var t0 := maxf(ff - 1.0, 0.0) if ff >= 0.0 and ff < t1 - 5.0 else 0.0
	_graph.set_data(series, t0, t1, stats.get("breaks", []), stats.get("hit_log", PackedFloat32Array()), GameSim.GAUGE_LOW_THRESHOLD)


## マルチプレイ: 参加者の成績の一覧。対戦はスコアの高い順(1 位に色。全員が終えたら WIN)、協力は 1 人ずつの GRAZE・被弾。
## 自分の分は、通信を待たずにこの画面の値を使う。まだ終えていない人は「プレイ中」。
func _rebuild_board() -> void:
	if _board == null:
		return
	for c in _board.get_children():
		c.queue_free()
		_board.remove_child(c)
	var mp: Dictionary = stats.mp
	var versus: bool = mp.mode == "versus"
	var res: Dictionary = net.results.duplicate() if net != null else {}
	res[int(mp.my_id)] = {"score": float(stats.score), "hits": int(stats.hits) if versus else int(res.get(int(mp.my_id), {}).get("hits", stats.hits)),
		"graze": int(res.get(int(mp.my_id), {}).get("graze", stats.graze)), "hit_ms": int(res.get(int(mp.my_id), {}).get("hit_ms", stats.hit_ms))}
	var rows: Array = []
	for p in mp.players:
		if net != null and p.id != int(mp.my_id) and not net.players.has(p.id) and not res.has(p.id):
			continue   # 終える前に去った人
		rows.append({"id": p.id, "name": p.name, "slot": p.slot, "res": res.get(p.id)})
	if versus:
		rows.sort_custom(func(a, b):
			if (a.res != null) != (b.res != null):
				return a.res != null
			if a.res == null:
				return a.slot < b.slot
			return float(a.res.score) > float(b.res.score))
	var all_done := true
	for r in rows:
		if r.res == null:
			all_done = false
	var base: float = float(stats.get("score_base", 1000000.0))
	var place := 0
	for r in rows:
		place += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(0, 36)
		var lead: bool = versus and place == 1 and r.res != null
		var accent: Color = UiStyle.GOLD if lead else UiStyle.TEXT
		if versus:
			var pl := UiStyle.label(str(place), 20, accent if r.res != null else UiStyle.TEXT_FAINT, true)
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
			var rk := GameSim.rank_of(false, int(r.res.hits), float(r.res.score), base)
			row.add_child(UiStyle.chip(rk, UiStyle.rank_color(rk)))
			row.add_child(UiStyle.label("被弾 %d 回 / %d ms" % [int(r.res.hits), int(r.res.get("hit_ms", 0))], 13, UiStyle.TEXT_DIM))
			if lead and all_done and rows.size() > 1:
				row.add_child(UiStyle.chip("WIN", UiStyle.GOLD))
		else:
			row.add_child(UiStyle.label("GRAZE %d" % int(r.res.graze), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("被弾 %d 回" % int(r.res.hits), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("%d ms" % int(r.res.hit_ms), 15, UiStyle.TEXT_DIM))
		_board.add_child(row)
