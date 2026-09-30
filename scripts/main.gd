extends Node
## 画面遷移(メニュー → プレイ → リザルト)。

const TitleScreen = preload("res://scripts/ui/title_screen.gd")
const MenuScreen = preload("res://scripts/ui/menu_screen.gd")
const GameScreen = preload("res://scripts/game/game_screen.gd")
const ResultScreen = preload("res://scripts/ui/result_screen.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const Settings = preload("res://scripts/settings.gd")
const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")

var _current: Node
var _last_play := {}
var _music: AudioStreamPlayer = null   # クリアで引き継いだ曲(リザルト中に流れ続ける)

## 画面切替の暗転フェード(通常起動のときだけ。開発用フックは即時に切り替える)
var _fade_enabled := false
var _fade: ColorRect
var _fading := false
var _pending: Node = null


func _ready() -> void:
	Settings.apply_volume(Settings.load_all().volume)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i >= 0 and args.size() > i + 2:
		UiStyle.animate = false   # スクリーンショットは動きを待たず、最終状態で撮る
		_shot(args[i + 1], args[i + 2], args.slice(i + 3))
		return
	# 動きの確認: --shot-anim <画面> <出力の接頭辞> [...]  →  接頭辞_0.png ... を、開いてからの経過時間ごとに撮る
	i = args.find("--shot-anim")
	if i >= 0 and args.size() > i + 2:
		_shot(args[i + 1], args[i + 2], args.slice(i + 3), true)
		return
	if args.has("--smoke-ui"):
		_smoke_ui()
		return
	if args.has("--smoke-clock"):
		_smoke_clock()
		return
	if args.has("--smoke-slider"):
		_smoke_slider()
		return
	if args.has("--smoke-kiai"):
		_smoke_kiai()
		return
	if args.has("--smoke-title"):
		_smoke_title()
		return
	if args.has("--smoke-back"):
		_smoke_back()
		return
	if args.has("--smoke-clear"):
		_smoke_clear()
		return
	if args.has("--smoke-rush"):
		_smoke_rush()
		return
	if args.has("--smoke-skip"):
		_smoke_skip()
		return
	if args.has("--smoke-score"):
		_smoke_score()
		return
	if args.has("--smoke-death"):
		_smoke_death()
		return
	if args.has("--smoke"):
		_smoke()
		return
	_setup_fade()
	show_title()


## 開発用: 実時間で数秒プレイ(音声クロック/入力の確認)。-- --smoke
func _smoke() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[1]
	var mouse := OS.get_cmdline_user_args().has("mouse")
	start_game(loader, bm, {"mods": ["practice", "dark"] if OS.get_cmdline_user_args().has("dark") else ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "mouse" if mouse else "keyboard", "sfx_volume": 70})
	var g = _current
	var t0 := Time.get_ticks_msec()
	var press := InputEventKey.new()
	press.physical_keycode = KEY_LEFT
	press.keycode = KEY_LEFT
	press.pressed = true
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(300, 300)
	motion.global_position = motion.position
	motion.relative = Vector2(50, -40)
	for sec in range(8):
		if sec == 4:
			if mouse:
				Input.parse_input_event(motion)
			else:
				Input.parse_input_event(press)
		await get_tree().create_timer(1.0).timeout
		print("real=%.2fs song_now=%.2f audio_playing=%s player=(%.0f,%.0f) bullets=%d sfx_played=%s" % [
			(Time.get_ticks_msec() - t0) / 1000.0, g._now, str(g._audio.playing), g.sim.player_pos.x, g.sim.player_pos.y, g.field.count, str(g._sfx._last.keys())])
	get_tree().quit()


## 画面を切り替える。通常起動では、短い暗転(フェードアウト → 入れ替え → フェードイン。点滅・フラッシュなし)を挟む。
func _swap(n: Node, instant := false) -> void:
	if not _fade_enabled or _current == null or (instant and not _fading):
		_swap_now(n)
		return
	if _pending != null:
		_pending.free()   # 暗転中にさらに要求が来たら、新しいほうだけ使う
	_pending = n
	if not _fading:
		_run_fade()


func _swap_now(n: Node) -> void:
	if _current != null:
		_current.queue_free()
	_current = n
	add_child(n)


func _setup_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.035, 0.06, 0.0)
	_fade.size = Vector2(1280, 720)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fade_enabled = true


func _run_fade() -> void:
	_fading = true
	while _pending != null:
		var t_in := create_tween()
		t_in.tween_property(_fade, "color:a", 1.0, 0.12)
		await t_in.finished
		var n := _pending
		_pending = null
		_swap_now(n)
		var t_out := create_tween()
		t_out.tween_property(_fade, "color:a", 0.0, 0.2)
		await t_out.finished
	_fading = false


## タイトル画面(起動時)。プレイ → 選曲画面。遊び方・設定はタイトルの上に重なるパネル。
func show_title() -> void:
	var t := TitleScreen.new()
	t.play_requested.connect(show_menu)
	_stop_music()
	_swap(t)


func show_menu() -> void:
	var m := MenuScreen.new()
	m.play_requested.connect(start_game)
	m.back_requested.connect(show_title)
	_stop_music()
	_swap(m)


func start_game(loader, bm, settings: Dictionary, debug_seek := -1.0, debug_death_t := -1.0) -> void:
	_last_play = {"loader": loader, "bm": bm, "settings": settings}
	var g := GameScreen.new()
	g.setup(loader, bm, settings)
	g.debug_seek = debug_seek
	g.debug_death_t = debug_death_t
	g.finished.connect(func(stats, music): show_result(stats, music))
	g.quit_requested.connect(show_menu)
	g.retry_requested.connect(func(): start_game(loader, bm, settings))
	_stop_music()
	_swap(g)


## music: クリアで引き継いだ曲(鳴ったまま、リザルトでも流し続ける。メニュー/リトライで消える)。画面は間を置かずに切り替える。
func show_result(stats: Dictionary, music: AudioStreamPlayer = null) -> void:
	var r := ResultScreen.new()
	r.setup(stats)
	r.menu_requested.connect(show_menu)
	r.retry_requested.connect(func():
		start_game(_last_play.loader, _last_play.bm, _last_play.settings))
	if music != null:
		_stop_music(0.0)
		_music = music
		add_child(music)
		music.finished.connect(func(): if _music == music: _stop_music(0.0))
	_swap(r, music != null)


## 引き継いだ曲を止める(fade 秒でなめらかに小さくして消す)。
func _stop_music(fade := 0.4) -> void:
	if _music == null:
		return
	var m := _music
	_music = null
	if fade <= 0.0 or not m.playing:
		m.queue_free()
		return
	var t := m.create_tween()
	t.tween_property(m, "volume_db", -50.0, fade)
	t.tween_callback(m.queue_free)


## スクリーンショット(開発用): -- --shot menu|game|result out.png [difficulty-substring] [seconds]
func _shot(kind: String, out: String, extra: Array, animated := false) -> void:
	match kind:
		"title":
			show_title()   # 例: --shot title out.png [howto|options 0..4]
			if extra.size() > 0 and extra[0] == "howto":
				_current._activate(1)
				if extra.size() > 1 and extra[1].is_valid_int():
					_current._overlay._show(int(extra[1]))
			elif extra.size() > 0 and extra[0] == "options":
				_current._activate(2)
		"menu":
			show_menu()
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))   # 例: --shot menu out.png rush storm
		"options":
			show_menu()   # 例: --shot options out.png 0 rush storm(先頭の数字はセクション 0=MOD 1=操作 2=音 3=ゲーム)
			_current.debug_set_mods(extra.filter(func(x): return not Mods.find(x).is_empty()))
			_current.open_options(int(extra[0]) if extra.size() > 0 and extra[0].is_valid_int() else 0)
		"game":
			var loader := OszLoader.new()
			var path := "C:/Desktop/my_apps/DDA/320118 Reol - No title.osz"
			if extra.size() > 3 and extra[3] == "soleily":
				path = "C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz"
			loader.open(path)
			var want: String = extra[0] if extra.size() > 0 else "Extra"
			var secs: float = float(extra[1]) if extra.size() > 1 else 30.0
			var bm = loader.difficulties[loader.difficulties.size() - 1]
			for d in loader.difficulties:
				if d.version.contains(want):
					bm = d
			var gs := {"offset_ms": 0, "density_mul": 1.0,
				"mods": extra.filter(func(x): return not Mods.find(x).is_empty())}   # 例: ... Extra 40 hell rush
			var death_t := -1.0
			if extra.size() > 2 and extra[2].begins_with("death"):
				death_t = float(extra[2].trim_prefix("death"))
			start_game(loader, bm, gs, secs, death_t)
			if extra.size() > 2 and extra[2] == "pause":
				_current._set_paused(true)
			if extra.has("nearhp") or extra.has("nearscore"):   # 自機を体力バー / スコアの近くに置いて、HUD の透過を撮る
				_current.sim.player_pos = Vector2(200, 34) if extra.has("nearhp") else Vector2(800, 40)
				_current._update_hud_fade(0.0, true)
				_current._refresh()
			if extra.has("scorered"):   # 被ダメージでスコアが減っている間の赤い数字
				_current._score_red = 1.0
				_current._refresh()
			if extra.has("trail"):   # 自機が右へ動いているときの尾を撮る
				var vw = _current._view_over
				for i in range(20):
					_current.sim.player_pos += Vector2(3.8, 0)
					vw.now += 0.01
					vw._update_trail()
				vw.queue_redraw()
			if extra.has("kiai"):   # キアイの光のピークを撮る(拍の頭)
				_current._kiai_a = 1.0
				_current._beat_glow = 1.0
				_current._apply_kiai()
				_current._refresh()
			if extra.has("slow"):   # 低速中の見た目(暗闇の可視範囲が狭まる)を撮る  例: ... Extra 40 dark slow
				_current.sim.slow = true
				_current._dark_scale = _current.DARK_SLOW_SCALE
				_current._refresh()
			for e in extra:   # 体力を指定して撮る(例: ... Extra 40 practice hp0.15)
				if e.begins_with("hp") and e.trim_prefix("hp").is_valid_float():
					var hp := float(e.trim_prefix("hp"))
					_current.sim.gauge = hp
					_current._gauge_ghost = minf(1.0, hp + 0.12)
					_current._hit_any = extra.has("hit")   # 例: ... hp0.6 hit(被弾中の先端の演出)
					_current._hit_glow = 1.0 if extra.has("hit") else 0.0
					for f in range(100):   # 先端の演出(火花・流れる光)を 100 フレームぶん進めてから撮る
						_current._animate_hud(1.0 / 60.0)
					_current._low_vis = _current._low_target()
					_current._refresh()
		"bullets":
			_shot_bullets()
		"result":
			var rl := OszLoader.new()
			rl.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
			var rbm = rl.difficulties[rl.difficulties.size() - 1]
			show_result({"title": "Reol - No title [Insane]", "level": 5.8, "mean": 105.0, "peak": 141.0, "failed": extra.size() > 0 and extra[0] == "failed", "progress": 0.63, "hits": 0 if extra.has("ss") else 2, "hit_ms": 180, "graze": 123, "score": 1013000.0 if extra.has("ss") else (300000.0 if extra.has("f") else 830660.0), "score_gross": 1013000.0, "damage_factor": 0.82, "score_graze": 13000.0, "practice": false,
				"score_base": 1060000.0, "mod_ids": ["hell", "rush"], "mods": "地獄 + 加速",
				"bg": rl.load_image(rbm.background) if rbm.background != "" else null})
			if not (extra.size() > 0 and extra[0] == "failed"):
				_current._score_disp = _current._score_target   # スクリーンショットではカウントアップを待たない
	if animated:
		var t0 := Time.get_ticks_msec()
		var k := 0
		for at in [0.1, 0.3, 0.6, 1.2, 2.5]:
			while (Time.get_ticks_msec() - t0) / 1000.0 < at:
				await get_tree().process_frame
			var path := "%s_%d.png" % [out, k]
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path, " at %.2fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
			k += 1
		get_tree().quit()
		return
	for n in range(6):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()


## 開発用: 動かずに被弾するまで待ち、ゲームオーバー演出→リザルト遷移を確認する。-- --smoke-death
func _smoke_death() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[3]
	start_game(loader, bm, {"mods": [], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 70})
	var g = _current
	var t0 := Time.get_ticks_msec()
	var was_dead := false
	var dead_at := 0.0
	var last_pos := 0.0
	var last_log: Array = []
	while Time.get_ticks_msec() - t0 < 60000:
		await get_tree().create_timer(0.5).timeout
		var real := (Time.get_ticks_msec() - t0) / 1000.0
		if not is_instance_valid(g) or _current != g:
			print("[%.1fs] screen switched -> %s" % [real, _current.get_script().resource_path])
			break
		last_log = g._sfx.log
		if g._dead:
			if not was_dead:
				await _sample_death_frames(g)
				was_dead = true
				dead_at = real
				last_pos = g._audio.get_playback_position()
				print("[%.1fs] DEAD at song_now=%.2f hits=%d" % [real, g._now, g.sim.hits])
			var pos: float = g._audio.get_playback_position()
			var rate := (pos - last_pos) / 0.5
			last_pos = pos
			print("  +%.1fs pitch=%.2f vol_db=%.1f playing=%s playback_rate=%.2fx bullets_alpha=%.2f label=%s a=%.2f" % [
				real - dead_at, g._audio.pitch_scale, g._audio.volume_db, str(g._audio.playing), rate, g.field.modulate.a, g._center_label.text, g._center_label.modulate.a])
	# 爆発音の再生要求以降に、何が何回要求されたか(連打がなければ explosion 1 回のみ)
	var t_exp := -1
	for e in last_log:
		if e[0] == "explosion":
			t_exp = e[1]
	var after := {}
	for e in last_log:
		if t_exp >= 0 and e[1] >= t_exp:
			after[e[0]] = after.get(e[0], 0) + 1
	print("sfx requests since explosion: ", after, "   (total requests in run: ", last_log.size(), ")")
	get_tree().quit()


## ゲームオーバー中の 100 フレームを記録し、揺れ・点滅がないことを確認する。
func _sample_death_frames(g) -> void:
	var max_shift := 0.0
	var alpha_ok := true
	var prev_alpha: float = g.field.modulate.a
	var max_alpha_step := 0.0
	var bullets_moved := 0.0
	var first_pos: Vector2 = g.field.pos[0] if g.field.count > 0 else Vector2.ZERO
	for i in range(100):
		await get_tree().process_frame
		max_shift = maxf(max_shift, (g._arena.position - g.ARENA_POS).length())
		var a: float = g.field.modulate.a
		if a > prev_alpha + 0.0001:
			alpha_ok = false
		max_alpha_step = maxf(max_alpha_step, prev_alpha - a)
		prev_alpha = a
		if g.field.count > 0:
			bullets_moved = maxf(bullets_moved, (g.field.pos[0] - first_pos).length())
	print("death frames: arena_shift_max=%.3fpx alpha_monotonic=%s alpha_max_step_per_frame=%.3f bullet_moved=%.3fpx" % [
		max_shift, str(alpha_ok), max_alpha_step, bullets_moved])


## 弾の見た目の確認用: 上段=通常の弾、下段=発射直後(当たり判定なし)の弾。
func _shot_bullets() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.07)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var BulletFieldScript = load("res://scripts/game/bullet_field.gd")
	var f = BulletFieldScript.new()
	f.position = Vector2(100, 100)
	add_child(f)
	f.setup_render()
	for i in range(10):
		f.add(Vector2(i * 110, 0), Vector2.ZERO, 7.5, i % 10, 0.0)           # 通常
		f.add(Vector2(i * 110, 100), Vector2.ZERO, 7.5, i % 10, 100.0)       # 発射直後(無害)
		f.add(Vector2(i * 110, 220), Vector2.ZERO, 12.0, i % 10, 0.0)        # 大きい弾
		f.add(Vector2(i * 110, 320), Vector2.ZERO, 12.0, i % 10, 100.0)
	f.sync_render()


## 開発用: 選曲・設定・ポーズの操作を、実際のキー入力で通しで確認する。-- --smoke-ui(ユーザーの設定ファイルは終了時に元へ戻す)
func _smoke_ui() -> void:
	var orig := Settings.load_all()
	show_menu()
	for i in range(4):
		await get_tree().process_frame
	var m = _current
	print("menu: songs=%d diffs=%d diff_sel=%d focus_diff=%s" % [m._song_cards.size(), m._diff_cards.size(), m._diff_sel, str(m._focus_diff)])
	await _key(KEY_DOWN)
	print("Down       -> diff_sel=%d" % m._diff_sel)
	await _key(KEY_TAB)
	var song_before: int = m._song_sel
	await _key(KEY_UP)
	print("Tab, Down  -> focus_diff=%s song_sel %d -> %d (diffs=%d)" % [str(m._focus_diff), song_before, m._song_sel, m._diff_cards.size()])
	await _key(KEY_TAB)
	var lv_before: float = m._ratings[m._diff_sel].level
	await _key(KEY_O)
	print("O          -> options open=%s" % str(m._options != null))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	m._options._mod_cards["storm"].gui_input.emit(click)
	await get_tree().process_frame
	print("click STORM-> mods=%s Lv %.2f -> %.2f | summary: %s" % [str(m.settings.mods), lv_before, m._ratings[m._diff_sel].level, m._options._mod_summary.text])
	await _key(KEY_TAB)
	print("Tab in options -> page 1 visible=%s" % str(m._options._pages[1].visible))
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.4).timeout   # 閉じる動きのぶん待つ
	print("Esc        -> options open=%s (menu still %s)" % [str(m._options != null), str(_current == m)])
	await _key(KEY_ENTER)
	for i in range(4):
		await get_tree().process_frame
	var g = _current
	print("Enter      -> screen=%s mods=%s Lv=%.2f (MODなし %.2f)" % [g.get_script().resource_path.get_file(), str(g._mods.ids), g.gen.level, g.gen.base_level])
	await _key(KEY_ESCAPE)
	print("Esc        -> paused=%s layer=%s" % [str(g._paused), str(g._pause_layer.visible)])
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	print("Down,Right -> sel=%d volume=%d" % [g._pause_sel, int(g.settings.volume)])
	for i in range(3):
		await _key(KEY_UP)
	await _key(KEY_ENTER)
	print("Up x3, Enter  -> paused=%s" % str(g._paused))
	await _key(KEY_ESCAPE)
	await _key(KEY_Q)
	for i in range(3):
		await get_tree().process_frame
	print("Q          -> screen=%s" % _current.get_script().resource_path.get_file())
	Settings.save_all(orig)   # ユーザーの設定ファイルを元に戻す
	print("settings restored")
	get_tree().quit()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


## 開発用: MOD「加速」(再生速度 ×1.5)の曲クロックを実時間で確認する。-- --smoke-rush
func _smoke_rush() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[2]   # Normal: 最初のノーツは 2.40 秒(加速で 1.60 秒)
	start_game(loader, bm, {"offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0, "mods": ["practice", "rush"]})
	var g = _current
	print("first fire (game time) = %.3f  end_time=%.2f  pitch=%.2f  Lv=%.2f (MODなし %.2f)" % [g.sim.first_fire_time, g._end_time, g._audio.pitch_scale, g.gen.level, g.gen.base_level])
	var t0 := Time.get_ticks_msec()
	var last_now := 0.0
	var last_real := 0.0
	for i in range(6):
		await get_tree().create_timer(1.0).timeout
		var real := (Time.get_ticks_msec() - t0) / 1000.0
		var pos: float = g._audio.get_playback_position()
		print("real=%.2f now=%.2f (%.2f/s) audio_pos=%.2f (pos/now=%.2f) fired=%d bullets=%d" % [real, g._now, (g._now - last_now) / (real - last_real), pos, pos / maxf(g._now, 0.001), g.sim.bullets_fired, g.field.count])
		last_now = g._now
		last_real = real
	get_tree().quit()


## 開発用: イントロのスキップを実時間で確認する(READY 中 / 再生中の 2 通り)。-- --smoke-skip
func _smoke_skip() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]   # Beginner: 最初のノーツが約 12 秒
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	space.pressed = true
	for when in [0.5, 3.0]:   # 0.5 秒 = READY(リードイン)中、3.0 秒 = 再生中
		start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
		var g = _current
		await get_tree().create_timer(when).timeout
		var before: float = g._now
		var can_before: bool = g._can_skip()
		Input.parse_input_event(space)
		await get_tree().process_frame
		await get_tree().process_frame
		var after: float = g._now
		var can_after: bool = g._can_skip()
		var first: float = g.sim.first_fire_time
		print("[press at %.1fs] now %.2f -> %.2f (target %.2f, first note %.2f) can_skip before=%s after=%s audio_playing=%s audio_pos=%.2f" % [
			when, before, after, g._skip_target(), first, str(can_before), str(can_after), str(g._audio.playing), g._audio.get_playback_position()])
		Input.parse_input_event(space)   # 2 回目は無視される(進む幅がない)
		await get_tree().create_timer(1.0).timeout
		print("   +1.0s: now=%.2f bullets=%d (first note at %.2f)" % [g._now, g.field.count, first])
		await get_tree().create_timer(1.2).timeout
		print("   +2.2s: now=%.2f bullets=%d fired=%d" % [g._now, g.field.count, g.sim.bullets_fired])
	get_tree().quit()


## 開発用: 表示スコアのイージングをフレームごとに記録して確認する。-- --smoke-score
func _smoke_score() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[2]   # Normal: 最初のノーツが約 2.4 秒
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	g.sim.debug_invincible = true   # ダメージによる目標の低下を除き、上昇だけを見る
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var max_lag := 0.0
	var overshoot := false
	var early_nonzero := false
	var target_moves := 0
	var last_target := 0.0
	var eased_frames := 0     # 目標に追いついていない(イージング中)のフレーム
	var last_disp := 0.0
	var monotone := true
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		frames += 1
		var target: float = g.sim.score
		var disp: float = g._score_disp
		if g._now < g.sim.events[0].t - 0.05 and (target > 0.0 or disp > 0.0):
			early_nonzero = true      # 最初のノーツより前にスコアが動いた(あってはならない)
		if target > last_target + 0.5:
			target_moves += 1
		if disp > target + 0.5 and target >= last_target:
			overshoot = true          # 上昇中に目標を追い越した(イージングなら起きない)
		if absf(target - disp) > 0.5:
			eased_frames += 1
		max_lag = maxf(max_lag, target - disp)
		if disp < last_disp - 0.5 and target >= last_target:
			monotone = false
		last_target = target
		last_disp = disp
	print("frames=%d first_note=%.2fs | target moved in %d frames, easing active in %d frames | max lag=%.0f pts | overshoot=%s early_nonzero=%s monotone=%s" % [
		frames, g.sim.events[0].t, target_moves, eased_frames, max_lag, str(overshoot), str(early_nonzero), str(monotone)])
	print("final: target=%.0f disp=%.0f bullets_fired=%d/%d" % [g.sim.score, g._score_disp, g.sim.bullets_fired, g.sim.bullets_total])
	get_tree().quit()


## 開発用: クリアの流れを実時間で確認する(弾が抜けたら即クリア → リザルトでも曲が流れ続ける)。-- --smoke-clear
func _smoke_clear() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout   # READY(1.5s)のあと、曲が流れ始める
	var last: float = g.sim.events[g.sim.events.size() - 1].t
	print("seek audio to %.2f (last event %.2f)  audio_playing=%s" % [last - 0.5, last, str(g._audio.playing)])
	g._audio.seek((last - 0.5) * g._rate)
	var t0 := Time.get_ticks_msec()
	var was_game := true
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		if was_game and is_instance_valid(g) and g.sim.finished:
			print("sim finished at now=%.2f  failed=%s  bullets=%d  score_progress=%.2f" % [g._now, str(g.sim.failed), g.field.count, g.sim.score_progress])
			was_game = false
		if not is_instance_valid(g) or _current != g:
			print("screen swapped to result at %.2fs  music=%s playing=%s pos=%.2f" % [(Time.get_ticks_msec() - t0) / 1000.0, str(_music != null), str(_music != null and _music.playing), _music.get_playback_position() if _music != null else -1.0])
			break
	await get_tree().create_timer(1.0).timeout
	print("+1.0s in result: music playing=%s pos=%.2f" % [str(_music != null and _music.playing), _music.get_playback_position() if _music != null else -1.0])
	_current.menu_requested.emit()
	await get_tree().create_timer(0.1).timeout
	print("after menu request: music node alive=%s (fading)" % str(_music != null))
	await get_tree().create_timer(0.6).timeout
	print("+0.7s: music=%s" % str(_music))
	get_tree().quit()


## 開発用: 曲クロック(_now)の増分が、実際のフレーム時間とどれだけずれるか(= 弾の移動距離のばらつき)を測る。-- --smoke-clock
func _smoke_clock() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[0]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	while not g._audio_started or g._now < 3.0:
		await get_tree().process_frame
	var last_now: float = g._now
	var last_us := Time.get_ticks_usec()
	var errs: Array = []   # 曲クロックの増分 − 実時間の増分(ms)
	var frozen := 0
	var drift_max := 0.0   # 曲クロックと音声クロックのずれ(ms)の絶対値の最大
	var drift_sum := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		var us := Time.get_ticks_usec()
		var dn: float = g._now - last_now
		var dr := (us - last_us) / 1e6
		errs.append((dn - dr) * 1000.0)
		if dn <= 0.0:
			frozen += 1
		var ta: float = g._audio.get_playback_position() / g._rate + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		drift_max = maxf(drift_max, absf(g._now - ta) * 1000.0)
		drift_sum += (g._now - ta) * 1000.0
		last_now = g._now
		last_us = us
	var mean := 0.0
	for e in errs:
		mean += e
	mean /= errs.size()
	var var_sum := 0.0
	var worst := 0.0
	for e in errs:
		var_sum += (e - mean) * (e - mean)
		worst = maxf(worst, absf(e - mean))
	print("frames=%d  clock-step minus real-step: mean=%.3fms  stdev=%.3fms  worst=%.2fms  frozen_frames=%d  |  vs audio clock: mean=%.2fms max=%.1fms" % [errs.size(), mean, sqrt(var_sum / errs.size()), worst, frozen, drift_sum / errs.size(), drift_max])
	get_tree().quit()


## 開発用: プレイして選択画面に戻ったとき、直前の曲・難易度が選ばれていることを確認する。-- --smoke-back
func _smoke_back() -> void:
	var original := Settings.load_all()
	show_menu()
	await get_tree().create_timer(0.5).timeout
	var m = _current
	var target_song := -1
	for i in range(m._songs.size()):
		if m._songs[i].path.contains("Reol"):
			target_song = i
	m._select_song(target_song)
	await get_tree().create_timer(0.5).timeout
	m._select_diff(4)
	var want: String = m._loader.difficulties[4].version
	print("song=%s  diff picked: idx=%d '%s' (of %d)" % [m._songs[m._song_sel].path.get_file(), m._diff_sel, want, m._loader.difficulties.size()])
	m._start()
	await get_tree().create_timer(0.5).timeout
	_current.quit_requested.emit()   # ゲームからメニューへ戻る
	await get_tree().create_timer(1.0).timeout
	var m2 = _current
	var got: String = m2._loader.difficulties[m2._diff_sel].version if m2._diff_sel >= 0 else "-"
	print("back in menu: song=%s idx=%d '%s'  -> %s" % [m2._songs[m2._song_sel].path.get_file(), m2._diff_sel, got, "OK" if got == want else "MISMATCH"])
	Settings.save_all(original)   # ユーザーの設定を元に戻す
	get_tree().quit()


## 開発用: 実時間で曲を進め、スライダーの軌道の描画(CanvasGroup)を撮る。-- --smoke-slider <出力の接頭辞>
func _smoke_slider() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/241526 Soleily - Renatus.osz")
	var bm = loader.difficulties[loader.difficulties.size() - 1]
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout
	g._audio.seek(48.0 * g._rate)   # 鋭く折れ返るスライダー(48.4 秒)の直前
	await get_tree().create_timer(0.55).timeout
	var pref: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--smoke-slider") + 1] if OS.get_cmdline_user_args().size() > OS.get_cmdline_user_args().find("--smoke-slider") + 1 else "tmp_slider"
	get_viewport().get_texture().get_image().save_png("C:/Desktop/my_apps/DDA/%s.png" % pref)
	print("now=%.2f nodes=%d" % [g._now, g._view_under._slider_nodes.size()])
	get_tree().quit()


## 開発用: キアイ中の光が、拍に合わせて出入りすることを実時間で確認する。-- --smoke-kiai
func _smoke_kiai() -> void:
	var loader := OszLoader.new()
	loader.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var bm = loader.difficulties[loader.difficulties.size() - 1]   # キアイは 50〜70 秒、BPM 200(1 拍 0.3 秒)
	start_game(loader, bm, {"mods": ["practice"], "offset_ms": 0, "density_mul": 1.0, "control": "keyboard", "sfx_volume": 0})
	var g = _current
	await get_tree().create_timer(2.5).timeout
	g._audio.seek(48.0)
	var samples: Array = []   # [曲の時刻, 光, キアイの度合い]
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		samples.append([g._now, g._beat_glow, g._kiai_a, g.field.halo])
	var pre_max := 0.0
	var kiai_max := 0.0
	var kiai_min := 9.0
	var peaks: Array = []
	for i in range(samples.size()):
		var s: Array = samples[i]
		if s[0] < 49.6:
			pre_max = maxf(pre_max, s[1])
		elif s[0] > 51.0:
			kiai_max = maxf(kiai_max, s[1])
			kiai_min = minf(kiai_min, s[1])
			if i > 0 and i < samples.size() - 1 and s[1] > samples[i - 1][1] and s[1] >= samples[i + 1][1] and s[1] > 0.5:
				peaks.append(s[0])
	var gaps: Array = []
	for i in range(1, peaks.size()):
		gaps.append(snappedf(peaks[i] - peaks[i - 1], 0.001))
	print("frames=%d  キアイ前(<49.6s)の最大の光=%.3f  キアイ中(>51s)の光: 最小=%.3f 最大=%.3f  拍のピーク %d 回、間隔(秒)=%s  (1 拍 = 0.300 秒)" % [samples.size(), pre_max, kiai_min, kiai_max, peaks.size(), str(gaps.slice(0, 8))])
	get_tree().quit()


## 開発用: タイトル画面の流れを、実際のキー入力で通して確認する。-- --smoke-title
##   起動 → タイトル(曲が流れる)→ 遊び方を開閉 → 設定を開閉 → プレイ → 選曲画面 → Esc → タイトル
func _smoke_title() -> void:
	var original := Settings.load_all()
	show_title()
	await get_tree().create_timer(2.0).timeout
	var t = _current
	print("title: %s  items=%d  music_playing=%s  song=%s" % [t.get_script().resource_path.get_file(), t._cards.size(), str(t._audio.playing), t._last_path.get_file()])
	await _key(KEY_DOWN)   # 遊び方
	print("selected=%d (expect 1)" % t._sel)
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	print("howto open=%s  music_still_playing=%s" % [str(t._overlay != null), str(t._audio.playing)])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("howto closed=%s" % str(t._overlay == null))
	await _key(KEY_DOWN)   # 設定
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	print("options open=%s (selected=%d)" % [str(t._overlay != null), t._sel])
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.6).timeout
	print("options closed=%s" % str(t._overlay == null))
	await _key(KEY_UP)
	await _key(KEY_UP)   # プレイ
	await _key(KEY_ENTER)
	await get_tree().create_timer(1.2).timeout
	print("after PLAY: %s" % _current.get_script().resource_path.get_file())
	await _key(KEY_ESCAPE)
	await get_tree().create_timer(0.8).timeout
	print("after Esc:  %s" % _current.get_script().resource_path.get_file())
	Settings.save_all(original)
	get_tree().quit()
