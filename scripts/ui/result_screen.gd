extends Control
## リザルト画面。左に大きなランク(ゲームオーバーなら到達度)、右にスコア(カウントアップ)と内訳・成績。

signal menu_requested
signal retry_requested

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Ambient = preload("res://scripts/ui/ambient.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")
const MpGame = preload("res://scripts/net/mp_game.gd")

## スコア表示の ease-out(1/RATE 秒ほどで大半が追いつく。プレイ画面の表示と同じ考え方)
const COUNT_RATE := 3.5

var stats: Dictionary
var net                          # マルチプレイのとき: 通信層(他の人の最終成績が届くたびに、一覧を更新する)
var _board: VBoxContainer         # マルチプレイの成績の一覧

var _score_l: Label
var _t := 0.0                    # 開いてからの経過秒(スコアのカウントアップの開始を遅らせる)
var _counters: Array = []         # 数字のカウントアップ: [Label, 目標値, 接尾辞]
var _score_target := 0.0
var _score_disp := 0.0


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
	var rank := GameSim.rank_of(failed, int(stats.hits), float(stats.score), float(stats.get("score_base", 1000000.0)))
	var accent := UiStyle.DANGER if failed else UiStyle.rank_color(rank)

	# --- 左: ランク / 到達度 ---
	var left := Control.new()
	left.position = Vector2(90, 110)
	left.size = Vector2(420, 480)
	add_child(left)
	var lp := PanelContainer.new()
	lp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lp.add_theme_stylebox_override("panel", UiStyle.box(Color(accent.r, accent.g, accent.b, 0.05), Color(accent.r, accent.g, accent.b, 0.35), 1, 8))
	left.add_child(lp)
	var lv := VBoxContainer.new()
	lv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 0)
	left.add_child(lv)
	lv.add_child(_centered(UiStyle.label("GAME OVER" if failed else "CLEAR", 26, accent, true)))
	lv.add_child(_gap(6))
	var big: Label
	if failed:
		big = UiStyle.label("%d%%" % int(round(stats.progress * 100.0)), 140, accent, true)
		lv.add_child(_centered(big))
		lv.add_child(_centered(UiStyle.label("到達", 18, UiStyle.TEXT_DIM)))
		_counters.append([big, int(round(stats.progress * 100.0)), "%", 0.3, 0.9])
	else:
		big = UiStyle.label(rank, 220, accent, true)
		lv.add_child(_centered(big))
		lv.add_child(_centered(UiStyle.label("RANK", 16, UiStyle.TEXT_DIM)))

	# 左パネルは左から滑り込み、ランク文字は弾んで現れる
	UiStyle.pop_in(left, 0.05, Vector2(-40, 0), 0.5)
	if not failed:
		big.pivot_offset = big.get_minimum_size() * 0.5
		UiStyle.tween(big, "scale", Vector2(0.4, 0.4), Vector2.ONE, 0.6, 0.4, Tween.TRANS_BACK)
		UiStyle.tween(big, "modulate:a", 0.0, 1.0, 0.3, 0.4)

	# --- 右: 曲名 / スコア / 内訳 / 成績 ---
	var right := VBoxContainer.new()
	right.position = Vector2(560, 100)
	right.size = Vector2(640, 500)
	right.add_theme_constant_override("separation", 10)
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
	right.add_child(_gap(6))

	right.add_child(UiStyle.caption("SCORE"))
	if failed:
		right.add_child(UiStyle.label("---", 72, UiStyle.TEXT_FAINT, true))
	else:
		_score_target = float(score)
		_score_l = UiStyle.label("0", 72, UiStyle.TEXT, true)
		right.add_child(_score_l)
		right.add_child(_gap(4))
		right.add_child(UiStyle.hline())
		if not (stats.has("mp") and stats.mp.mode == "versus"):   # 対戦は、内訳の代わりに参加者の成績を並べる
			right.add_child(_row("ベーススコア", UiStyle.fmt(int(round(stats.get("score_base", 1000000.0)))), _mod_note()))
			right.add_child(_row("グレイズボーナス", "+ " + UiStyle.fmt(int(stats.score_graze)), ""))
			right.add_child(_row("被ダメージ係数", "× %.3f" % stats.damage_factor, ""))
			right.add_child(UiStyle.hline())
	right.add_child(_gap(6))

	if stats.has("mp"):   # マルチプレイ: 参加者の成績の一覧(他の人が終えるたびに更新)
		_board = VBoxContainer.new()
		_board.add_theme_constant_override("separation", 8)
		right.add_child(_board)
		_rebuild_board()
		if net != null:
			net.results_changed.connect(_rebuild_board)
	else:
		# 成績(3 つ並べる)
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 40)
		grid.add_child(_stat("GRAZE", int(stats.graze), "", 0.7))
		grid.add_child(_stat("被弾", int(stats.hits), " 回", 0.8))
		grid.add_child(_stat("被弾時間", int(stats.hit_ms), " ms", 0.9))
		right.add_child(grid)

	# 下部のボタン(Enter / R のキーでも同じ操作ができる)
	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 12)
	hint.position = Vector2(560, 626)
	for spec in ([["ロビーへ", menu_requested]] if stats.has("mp") else [["メニューへ", menu_requested], ["リトライ", retry_requested]]):
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 40)
		var sig: Signal = spec[1]
		b.pressed.connect(func(): sig.emit())
		hint.add_child(b)
	add_child(hint)

	# 右の列は右から滑り込み、中身が上から順に現れ、数字が数え上がる
	UiStyle.pop_in(right, 0.1, Vector2(40, 0), 0.5)
	var j := 0
	for c in right.get_children():
		UiStyle.tween(c, "modulate:a", 0.0, 1.0, 0.35, 0.2 + 0.07 * j)
		j += 1
	UiStyle.tween(hint, "modulate:a", 0.0, 1.0, 0.5, 1.2)
	for c in _counters:
		var lab: Label = c[0]
		var suffix: String = c[2]
		var set_text := func(v: float): lab.text = str(int(round(v))) + suffix
		UiStyle.tween_value(lab, 0.0, float(c[1]), float(c[4]), set_text, float(c[3]))


func _process(delta: float) -> void:
	_t += delta
	if _score_l == null or (UiStyle.animate and _t < 0.55):   # 右の列が現れてから数え始める
		return
	_score_disp += (_score_target - _score_disp) * (1.0 - exp(-delta * COUNT_RATE))
	if absf(_score_target - _score_disp) < 0.5:
		_score_disp = _score_target
	_score_l.text = UiStyle.fmt(int(round(_score_disp)))


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
	if net != null and net.results_changed.is_connected(_rebuild_board):
		net.results_changed.disconnect(_rebuild_board)


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
			row.add_child(UiStyle.label("被弾 %d 回" % int(r.res.hits), 13, UiStyle.TEXT_DIM))
			if lead and all_done and rows.size() > 1:
				row.add_child(UiStyle.chip("WIN", UiStyle.GOLD))
		else:
			row.add_child(UiStyle.label("GRAZE %d" % int(r.res.graze), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("被弾 %d 回" % int(r.res.hits), 15, UiStyle.TEXT))
			row.add_child(UiStyle.label("%d ms" % int(r.res.hit_ms), 15, UiStyle.TEXT_DIM))
		_board.add_child(row)
