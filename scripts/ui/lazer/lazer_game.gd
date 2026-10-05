extends "res://scripts/game/game_screen.gd"
## lazer 風のプレイ画面。進行(曲クロック・判定・音・入力・ポーズ・リトライ・スキップ・マルチプレイ)は GameScreen のものをそのまま使い、
## HUD の見た目(左右のパネル・体力バー・スコア・枠・進行バー・ポーズ・スキップ・リトライの輪・休憩のカウントダウン・
## 撃破 MOD のボスのゲージと WARNING・ボーナスタイム)だけを上書きする。
## アリーナは classic と同じ位置・同じ大きさ(960×720。縮小しない)。左右の 160px の余白と、アリーナの上下の縁に HUD を置く。
## 体力バー・スコアの位置と大きさは classic と同じ矩形の中(自機が近づくと薄くなる処理は、そのまま働く)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerButton = preload("res://scripts/ui/lazer/lazer_button.gd")
const LazerBossGauge = preload("res://scripts/ui/lazer/lazer_boss_gauge.gd")

const PANEL_COL := Color(0.055, 0.047, 0.086, 0.82)


func _ready() -> void:
	super._ready()
	_center_label.add_theme_font_override("font", LazerStyle.font_bold())   # READY / GO / GAME OVER


# --- 左右のパネル ---

func _card(alpha := 0.82, accent := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", LazerStyle.box(Color(PANEL_COL.r, PANEL_COL.g, PANEL_COL.b, alpha),
		Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.5) if accent else Color(1, 1, 1, 0.06), 1, 14, 12, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## 左のパネル: 曲情報・Lv(MOD 適用後)・付けた MOD・いま受けているデバフ・マルチプレイの参加者。
func _build_left_panel() -> void:
	var col := VBoxContainer.new()
	_left_col = col
	col.position = Vector2(8, 14)
	col.custom_minimum_size = Vector2(144, 0)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	if not replay_data.is_empty() and not replay_export:   # 再生: 「リプレイ」であることと、いつの・どんな結果のプレイか・再生中 / 停止中(動画には入れない)
		var ri := _replay_info()
		var rc := _card(0.82)
		col.add_child(rc)
		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 3)
		rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rc.add_child(rv)
		var rp := LazerStyle.pill("REPLAY", LazerStyle.PINK, 13)
		rp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		rv.add_child(rp)
		rv.add_child(LazerStyle.label(ri.when, 11, LazerStyle.TEXT_MUTE))
		rv.add_child(LazerStyle.label(ri.result, 12, Color(1.0, 0.45, 0.48) if ri.failed else LazerStyle.TEXT_DIM, true))
		_rp_state_l = LazerStyle.label("", 12, LazerStyle.PINK, true)
		rv.add_child(_rp_state_l)
	var info := _card(0.82, true)
	col.add_child(info)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(v)
	for spec in [[bm.artist, 12, LazerStyle.TEXT_DIM, false], [bm.title, 16, LazerStyle.TEXT, true], [bm.version, 13, LazerStyle.PINK, true]]:
		var l := LazerStyle.label(spec[0], spec[1], spec[2], spec[3])
		l.custom_minimum_size = Vector2(118, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	var lvc := LazerStyle.level_color(gen.level)
	var pill := LazerStyle.pill("★ %.2f" % gen.level, lvc, 18)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(pill)
	if absf(gen.level - gen.base_level) >= 0.005:
		v.add_child(LazerStyle.label("MODなし  %.2f" % gen.base_level, 12, LazerStyle.TEXT_MUTE))
	if not _mods.ids.is_empty():
		var mods_box := HFlowContainer.new()
		mods_box.add_theme_constant_override("h_separation", 5)
		mods_box.add_theme_constant_override("v_separation", 5)
		mods_box.custom_minimum_size = Vector2(118, 0)
		mods_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gap2 := Control.new()
		gap2.custom_minimum_size = Vector2(0, 4)
		v.add_child(gap2)
		v.add_child(mods_box)
		for id in _mods.ids:
			var m := Mods.find(id)
			var c: Color = m.color
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", LazerStyle.box(Color(c.r, c.g, c.b, 0.24), Color(c.r, c.g, c.b, 0.8), 1, 999, 8, 1))
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(LazerStyle.label(str(m.tag), 12, c, true))
			mods_box.add_child(chip)
	_debuff_l = LazerStyle.label("", 14, LazerStyle.TEXT, true)   # 危険エリアに入っている間だけ、デバフの名前を出す
	_debuff_l.visible = false
	_debuff_l.custom_minimum_size = Vector2(118, 0)
	_debuff_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_debuff_l)
	if _mp != null:   # マルチプレイ: 参加者の一覧(対戦はスコア順)
		var mp_card := _card(0.82)
		col.add_child(mp_card)
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 6)
		mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mp_card.add_child(mv)
		mv.add_child(LazerStyle.label("VERSUS" if _mp.mode == "versus" else "CO-OP", 11, LazerStyle.PINK, true))
		_mp_box = VBoxContainer.new()
		_mp_box.add_theme_constant_override("separation", 5)
		_mp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mv.add_child(_mp_box)


## 右のパネル: GRAZE / DAMAGE(ダメージ量。ゲージ満タン = 100%)。撃破 MOD では、自機の弾の強化の段階。
func _build_right_panel() -> void:
	var col := VBoxContainer.new()
	_right_col = col
	col.position = Vector2(1128, 16)
	col.custom_minimum_size = Vector2(144, 0)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var stats := _card(0.82)
	col.add_child(stats)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(v)
	v.add_child(LazerStyle.label("GRAZE", 11, LazerStyle.TEXT_MUTE))
	_graze_l = LazerStyle.label("0", 30, LazerStyle.TEXT, true)
	v.add_child(_graze_l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	v.add_child(LazerStyle.label("DAMAGE", 11, LazerStyle.TEXT_MUTE))
	_hit_l = LazerStyle.label("0%", 30, LazerStyle.TEXT, true)
	v.add_child(_hit_l)
	if sim.boss != null:   # 撃破 MOD: 自機の弾の強化(アイテムで上がる段階)
		var wp := _card(0.82)
		col.add_child(wp)
		var wv := VBoxContainer.new()
		wv.add_theme_constant_override("separation", 3)
		wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wp.add_child(wv)
		wv.add_child(LazerStyle.label("WEAPON", 11, LazerStyle.TEXT_MUTE))
		for k in ["power", "rate", "wide"]:
			var l := LazerStyle.label("", 14, LazerStyle.TEXT_DIM, true)
			wv.add_child(l)
			_weapon_ls[k] = l
		_update_weapon_labels()


# --- 体力バー・スコア・枠・進行バー ---

## 体力バー: 丸い端の細いバー。溝 + 減った分の白い残像(ゆっくり縮む)+ 塗り(残量で青緑 → 琥珀 → 赤)。20%(被ダメージ半減の境目)に小さな三角。
## 被弾中は赤みがかり、休憩中(回復が止まっている)は冷たい色に沈む。回復中は、先端にやわらかい光。
func _draw_hp_bar(_font: Font, bx: float, y: float, g: float) -> void:
	var w := _hp_w
	var h := 12.0
	var by := y + (HP_H - h) * 0.5
	_hp_node.draw_style_box(LazerStyle.box(Color(0.03, 0.025, 0.06, 0.66), Color(1, 1, 1, 0.16), 1, 9), Rect2(bx - 3.0, by - 3.0, w + 6.0, h + 6.0))
	var gw := w * clampf(_gauge_ghost, 0.0, 1.0)
	if gw > h:   # 減った分の残像(白。ゆっくり縮む)
		_hp_node.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.34), Color(0, 0, 0, 0), 0, 6), Rect2(bx, by, gw, h))
	var fc := UiStyle.hp_color(g).lerp(Color(1.0, 0.3, 0.34), clampf(_hit_glow, 0.0, 1.0) * 0.45).lerp(Color(0.62, 0.74, 1.0), _fx_break * 0.7)
	var fw := w * g
	if fw > h:
		_hp_node.draw_style_box(LazerStyle.box(fc, Color(0, 0, 0, 0), 0, 6), Rect2(bx, by, fw, h))
		_hp_node.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 3), Rect2(bx + 3.0, by + 1.5, maxf(fw - 6.0, 0.0), 3.0))   # 上面の艶
	elif fw > 0.5:
		_hp_node.draw_rect(Rect2(bx, by + 1.0, fw, h - 2.0), fc)
	var tx: float = bx + w * (sim.low_threshold if sim != null else GameSim.GAUGE_LOW_THRESHOLD)   # 20%(MOD「天国」は 35%)の目印
	_hp_node.draw_colored_polygon(PackedVector2Array([Vector2(tx - 4.0, by - 9.0), Vector2(tx + 4.0, by - 9.0), Vector2(tx, by - 3.0)]), Color(1, 1, 1, 0.55))
	if _fx_regen > 0.02 and fw > h:   # 回復中: 先端に、やわらかい光
		_hp_node.draw_circle(Vector2(bx + fw, by + h * 0.5), 9.0 * _fx_regen + 3.0, Color(fc.r, fc.g, fc.b, 0.22 * _fx_regen))
	_hp_node.draw_string(LazerStyle.font_bold(), Vector2(bx + w + 14.0, by + h - 1.0), "%d" % int(round(g * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


## スコア: 右上に大きく(被ダメージで点が減っている間は赤く)。見出しの SCORE と、下に進行率(撃破では何周目か)。
func _draw_score() -> void:
	var right := ARENA_POS.x + PatternGen.ARENA.x - 28.0   # フィールド右端の内側
	var score_text := UiStyle.fmt(int(round(_score_disp)))
	var prog_pct: float = (sim.progress if sim != null else 0.0) * 100.0
	var dy := _score_dy
	var bold := LazerStyle.font_bold()
	var score_c := Color(1, 1, 1, 0.97).lerp(Color(1.0, 0.27, 0.31, 1.0), _score_red)
	_sc_node.draw_string(bold, Vector2(right - 400.0, 24 + dy), "SCORE", HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 12, Color(1, 1, 1, 0.5).lerp(Color(1.0, 0.4, 0.42, 0.85), _score_red))
	_sc_node.draw_string(bold, Vector2(right - 400.0 + 2.0, 74.0 + 2.0 + dy), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 50, Color(0, 0, 0, 0.5))
	_sc_node.draw_string(bold, Vector2(right - 400.0, 74.0 + dy), score_text, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 50, score_c)
	var sub := ("LOOP %d" % (sim.loop_index(_now) + 1)) if sim.loop_len > 0.0 else "%.2f%%" % prog_pct
	_sc_node.draw_string(bold, Vector2(right - 400.0, 102.0 + dy), sub, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 19, LazerStyle.PINK)


func _draw_hud() -> void:
	var ax := ARENA_POS.x
	_draw_low_vignette()   # 体力が低いときの、画面の左右端の赤み(点滅・脈動なし)
	if _break_a > 0.01:   # 休憩のカウントダウン(フィールド中央の輪と、残り秒)
		_draw_break_count()
	# 進行バー(フィールド下端。休憩地帯は淡い区間で示す)。撃破 MOD では曲が繰り返すので、いまの周の中の位置を出す
	var span := maxf(_end_time, 1.0)
	var shift := 0.0
	if sim != null and sim.loop_len > 0.0:
		span = sim.loop_end + Boss.BONUS_TIME
		shift = float(sim.loop_index(_now)) * sim.loop_len
	var pr := clampf((_now - shift) / span, 0.0, 1.0)
	var aw: float = PatternGen.ARENA.x
	_hud.draw_rect(Rect2(ax, 715, aw, 5), Color(1, 1, 1, 0.10))
	if sim != null:
		for b in sim.breaks:
			var x0 := clampf((float(b[0]) - shift) / span, 0.0, 1.0)
			var x1 := clampf((float(b[1]) - shift) / span, 0.0, 1.0)
			if x1 - x0 > 0.0:
				_hud.draw_rect(Rect2(ax + x0 * aw, 715, maxf((x1 - x0) * aw, 1.0), 5), Color(1, 1, 1, 0.24))
	_hud.draw_rect(Rect2(ax, 715, aw * pr, 5), LazerStyle.PINK)
	_draw_bonus_hud()
	# アリーナの枠: 細い線と、四隅のピンクの角(被弾中は、なめらかに赤くなる)
	var k := clampf(_hit_glow, 0.0, 1.0)
	var line_c := Color(1, 1, 1, 0.22).lerp(Color(1.0, 0.35, 0.38, 0.75), k)
	var corner_c := Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.85).lerp(Color(1.0, 0.35, 0.38, 1.0), k)
	_hud.draw_rect(Rect2(ARENA_POS, PatternGen.ARENA), line_c, false, 2.0)
	var cl := 26.0
	var r := Rect2(ARENA_POS, PatternGen.ARENA)
	for q in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
		var o: Vector2 = q[0]
		var d: Vector2 = q[1]
		_hud.draw_polyline(PackedVector2Array([o + Vector2(d.x * cl, 0), o, o + Vector2(0, d.y * cl)]), corner_c, 3.0, true)


# --- ポーズ ---

## ポーズ画面(暗転 + 中央のカード)。項目は 6 行: 再開 / リトライ / メニューへ / 全体音量 / 音楽 / 効果音(設定・音量メーターと同じ名前と並び)。
## マウスを乗せた行が選択になり、強調で示す。キーでも、↑↓ で全部の行を選べる(← → は選んだ音量の行だけを動かす)。
func _build_pause() -> void:
	_pause_layer = Control.new()
	_pause_layer.size = Vector2(1280, 720)
	_pause_layer.theme = LazerStyle.make_theme()
	_pause_layer.visible = false
	add_child(_pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.05, 0.68)
	dim.size = Vector2(1280, 720)
	_pause_layer.add_child(dim)
	_pause_cover = ColorRect.new()   # 止めた弾を観察できないよう、ポーズ中のアリーナは見せない(マルチプレイのメニューは、ゲームが進むので覆わない)
	_pause_cover.color = Color(LazerStyle.BG.r, LazerStyle.BG.g, LazerStyle.BG.b, 1.0)
	_pause_cover.position = ARENA_POS
	_pause_cover.size = PatternGen.ARENA
	_pause_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_cover.visible = _mp == null
	_pause_layer.add_child(_pause_cover)
	var panel := PanelContainer.new()
	_pause_panel = panel
	panel.position = Vector2(400, 100)
	panel.size = Vector2(480, 10)
	panel.add_theme_stylebox_override("panel", LazerStyle.box(Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.97), Color(LazerStyle.PINK.r, LazerStyle.PINK.g, LazerStyle.PINK.b, 0.55), 2, 20, 30, 26))
	_pause_layer.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(LazerStyle.label("MENU" if _mp != null else "PAUSED", 28, LazerStyle.TEXT, true))   # マルチプレイでは、ゲームは止まらない
	_pause_btns.clear()
	var btn_box := VBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 8)
	v.add_child(btn_box)
	var specs := [["再開", "play", LazerStyle.PINK, Color(0.2, 0.04, 0.11)], ["リトライ", "retry", LazerStyle.PURPLE, Color(0.1, 0.04, 0.22)],
		["メニューへ", "back", Color(0.3, 0.28, 0.38), LazerStyle.TEXT]]
	for i in range(specs.size()):
		var b := LazerButton.new(specs[i][0], specs[i][2], specs[i][1], specs[i][3])
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(Callable(self, "_pause_activate").bind(i))
		b.mouse_entered.connect(func():
			_pause_sel = i
			_refresh_pause())
		btn_box.add_child(b)
		_pause_btns.append(b)
	if _mp != null:   # マルチプレイ: リトライはなく、「メニューへ」は部屋を出ることになる
		_pause_btns[1].visible = false
		(_pause_btns[2] as LazerButton).caption = "退出"
		_pause_btns[2].text = "退出"   # (確認用のコードが text を読む)
	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 6)
	v.add_child(row_box)
	_pause_vol = _pause_slider_row(row_box, 3, "全体音量", func(x: float): _set_master_volume(int(x)))
	_pause_music = _pause_slider_row(row_box, 4, "音楽", func(x: float): _set_music_volume(int(x)))
	_pause_sfx = _pause_slider_row(row_box, 5, "効果音", func(x: float): _set_sfx_volume(int(x)))


## ポーズ画面の音量スライダー 1 行(見出し + スライダー + 値。選択中は強調)。[スライダー, 値ラベル, 見出しラベル, 行の枠] を返す。
func _pause_slider_row(parent: Control, idx: int, cap: String, on_change: Callable) -> Array:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.mouse_filter = Control.MOUSE_FILTER_PASS   # 子(スライダー)の上でも、行に入ったことが分かる
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var l := LazerStyle.label(cap, 16, LazerStyle.TEXT)
	l.custom_minimum_size = Vector2(92, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.custom_minimum_size = Vector2(170, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	h.add_child(s)
	var val := LazerStyle.label("", 16, LazerStyle.PINK, true)
	val.custom_minimum_size = Vector2(50, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	var select_row := func():
		if _pause_sel != idx:
			_pause_sel = idx
			_refresh_pause()
	row.mouse_entered.connect(select_row)
	s.mouse_entered.connect(select_row)
	parent.add_child(row)
	return [s, val, l, row]


## ポーズ画面の表示を、今の設定・選択に合わせる。
func _refresh_pause() -> void:
	if Volume.loaded:   # ホイールで変えた値も出す
		settings.volume = Volume.master
		settings.music_volume = Volume.music
		settings.sfx_volume = Volume.sfx
	for i in range(_pause_btns.size()):   # 選択中のボタンは明るくなる
		var b := _pause_btns[i] as LazerButton
		b.emphasized = i == _pause_sel
		b.queue_redraw()
	var rows := [_pause_vol, _pause_music, _pause_sfx]
	var keys := ["volume", "music_volume", "sfx_volume"]
	var defaults := [80, 100, 70]
	for k in range(rows.size()):
		var row: Array = rows[k]
		var value := int(settings.get(keys[k], defaults[k]))
		row[0].set_value_no_signal(value)
		row[1].text = "%d%%" % value
		var sel := _pause_sel == 3 + k
		row[2].add_theme_color_override("font_color", LazerStyle.PINK if sel else LazerStyle.TEXT)
		(row[3] as PanelContainer).add_theme_stylebox_override("panel", LazerStyle.box(LazerStyle.PANEL_SEL if sel else Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 10, 14, 4))


# --- スキップ・リトライの輪 ---

func _build_skip_button() -> void:
	var b := LazerButton.new("", LazerStyle.PINK, "play", Color(0.2, 0.04, 0.11))
	b.slant = 12.0
	b.font_size = 17
	b.position = ARENA_POS + Vector2(PatternGen.ARENA.x * 0.5 - 130.0, 640.0)
	b.size = Vector2(260, 46)
	b.visible = false
	b.pressed.connect(func(): if _can_skip(): _request_skip())
	_skip_btn = b
	add_child(b)
	move_child(b, _arena.get_index())   # アリーナ(自機)より奥: 自機をボタンに重ねても、自機が文字に隠れない


## R 長押しの輪: 暗い円の上に、押している長さだけ時計回りに伸びる輪と「リトライ」。
func _draw_retry_ui() -> void:
	var c := Vector2(60, 32)
	var k := clampf(_retry_hold / RETRY_HOLD, 0.0, 1.0)
	var a := LazerStyle.PINK
	_retry_ui.draw_circle(c, 29.0, Color(0.03, 0.025, 0.06, 0.7))
	_retry_ui.draw_arc(c, 24.0, 0.0, TAU, 48, Color(1, 1, 1, 0.15), 4.0, true)
	if k > 0.0:
		_retry_ui.draw_arc(c, 24.0, -PI * 0.5, -PI * 0.5 + TAU * k, 48, a, 4.5, true)
	var font := LazerStyle.font_bold()
	_retry_ui.draw_string(font, c + Vector2(-30, 7), "R", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 20, Color(1, 1, 1, 0.95))
	_retry_ui.draw_string_outline(font, Vector2(0, 84), "リトライ", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 15, 5, Color(0, 0, 0, 0.8))
	_retry_ui.draw_string(font, Vector2(0, 84), "リトライ", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 15, Color(a.r, a.g, a.b, 0.95))


# --- 休憩のカウントダウン ---

## 休憩のカウントダウン: 細い輪(真上から時計回りに減る)と、大きな残り秒。下に「BREAK」の札。
## 残り 3 秒からは、輪と数字が黄色へ移る。数字は変わるたびに少し弾む(classic と同じ動き。点滅なし)。
func _draw_break_count() -> void:
	var c := _break_center()
	var a := _break_a
	var warm := smoothstep(3.4, 2.9, _break_left)
	var cool := LazerStyle.BLUE
	var col := cool.lerp(LazerStyle.YELLOW, warm)
	var grow := 1.0 - pow(1.0 - _break_in, 3.0)
	var frac := _break_frac * grow
	_hud.draw_circle(c, BREAK_R + 18.0, Color(LazerStyle.PANEL_DARK.r, LazerStyle.PANEL_DARK.g, LazerStyle.PANEL_DARK.b, 0.55 * a))
	_hud.draw_arc(c, BREAK_R, 0.0, TAU, 96, Color(1, 1, 1, 0.12 * a), 4.0, true)
	if frac > 0.002:
		var end := -PI * 0.5 + TAU * frac
		_hud.draw_arc(c, BREAK_R, -PI * 0.5, end, 96, Color(col.r, col.g, col.b, 0.95 * a), 4.0, true)
		_hud.draw_circle(c + Vector2.from_angle(end) * BREAK_R, 4.5, Color(1, 1, 1, 0.95 * a))
	var p := _break_pop * _break_pop
	var sc := 1.0 + 0.2 * p
	var txt := str(maxi(_break_sec, 0))
	var fs := 56
	var bold := LazerStyle.font_bold()
	_hud.draw_set_transform(c, 0.0, Vector2(sc, sc))
	_hud.draw_string(bold, Vector2(-80.0, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, 160.0, fs, Color(1, 1, 1, 0.97 * a).lerp(Color(col.r, col.g, col.b, a), 0.2 + 0.5 * p))
	_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tw := bold.get_string_size("BREAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20.0
	var tr := Rect2(c.x - tw * 0.5, c.y + BREAK_R + 22.0, tw, 20.0)
	_hud.draw_style_box(LazerStyle.box(Color(cool.r, cool.g, cool.b, 0.85 * a), Color(0, 0, 0, 0), 0, 999), tr)
	_hud.draw_string(bold, Vector2(tr.position.x, tr.position.y + 14.5), "BREAK", HORIZONTAL_ALIGNMENT_CENTER, tw, 12, Color(0.04, 0.1, 0.16, a))


# --- 撃破 MOD ---

func _build_boss_gauge() -> void:
	_boss_gauge = LazerBossGauge.new()
	_boss_gauge.boss = sim.boss
	_boss_gauge.warned.connect(func():
		_sfx.play("boom")
		UiSfx.play("whoosh", 0.7))
	_boss_gauge.phase_crossed.connect(func(): UiSfx.play("whoosh", 1.25))
	_hud.add_child(_boss_gauge)


## ボーナスタイム: ボスのゲージの下に「BONUS TIME」の札(早送りの印つき)と、残りの細いバー。フィールドには、左へ流れる光の筋(速いところほど長い)。
func _draw_bonus_hud() -> void:
	if sim == null or sim.boss == null or sim.boss.defeated or _dead:
		return
	var left: float = sim.bonus_left(_now)
	if left < 0.0:
		return
	var dur: float = Boss.BONUS_TIME
	var u := 1.0 - left / dur
	var env := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))
	var sp := sin(PI * u)
	var ax := ARENA_POS.x
	var aw: float = PatternGen.ARENA.x
	var gold := LazerStyle.YELLOW
	for i in range(18):   # 早送りの光の筋
		var hy := fmod(float(i) * 97.3 + 13.0, 700.0) + 10.0
		var spd := 900.0 + 700.0 * fmod(float(i) * 0.618, 1.0)
		var x := ax + aw - fposmod(_now * spd * (0.4 + sp) + float(i) * 211.0, aw + 300.0) + 150.0
		var ln := (60.0 + 260.0 * sp) * (0.6 + 0.4 * fmod(float(i) * 0.37, 1.0))
		var x0 := clampf(x, ax, ax + aw)
		var x1 := clampf(x + ln, ax, ax + aw)
		if x1 - x0 > 1.0:
			_hud.draw_line(Vector2(x0, hy), Vector2(x1, hy), Color(gold.r, gold.g, gold.b, 0.07 * env * (0.4 + sp)), 2.0)
	var cx := ax + aw * 0.5
	var bold := LazerStyle.font_bold()
	var label := "BONUS TIME"
	var tw := bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var pw := tw + 70.0
	var r := Rect2(cx - pw * 0.5, 78.0, pw, 32.0)
	_hud.draw_style_box(LazerStyle.box(Color(gold.r, gold.g, gold.b, 0.92 * env), Color(0, 0, 0, 0), 0, 999), r)
	var ink := Color(0.2, 0.13, 0.0, env)
	_hud.draw_string(bold, Vector2(r.position.x + 18.0, r.position.y + 23.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	for k in range(2):   # ▶▶(早送りの印。速いほど右へ少し流れる)
		var ox := r.position.x + 26.0 + tw + 12.0 * k + 4.0 * sp
		_hud.draw_colored_polygon(PackedVector2Array([Vector2(ox, r.position.y + 9.0), Vector2(ox + 10.0, r.position.y + 16.0), Vector2(ox, r.position.y + 23.0)]), ink)
	var bw := pw - 24.0
	var bar := Rect2(cx - bw * 0.5, r.end.y + 8.0, bw, 4.0)
	_hud.draw_style_box(LazerStyle.box(Color(1, 1, 1, 0.14 * env), Color(0, 0, 0, 0), 0, 2), bar)
	_hud.draw_style_box(LazerStyle.box(Color(gold.r, gold.g, gold.b, env), Color(0, 0, 0, 0), 0, 2), Rect2(bar.position, Vector2(bw * (left / dur), 4.0)))
