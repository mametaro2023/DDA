extends SceneTree
## リプレイの単体テスト: 記録 → 再生で、シムが完全に同じ状態になること / キーフレームからのシーク / ファイルの往復・拒否・整理。
## godot --headless --path . --script tests/test_replay.gd

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")
const Replay = preload("res://scripts/replay.gd")

const SECS := 40.0   # 確かめる長さ(秒)。長いほど確かだが、時間がかかる

var _fail := 0
var _nodes: Array = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("ok:   ", msg)
	else:
		_fail += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	var reol := OszLoader.new()
	reol.open("C:/Desktop/my_apps/DDA/320118 Reol - No title.osz")
	var laur := OszLoader.new()
	laur.open("C:/Desktop/my_apps/DDA/813569 Laur - Sound Chimera.osz")
	var easy = null
	var hard = null
	for bm in reol.difficulties:
		if bm.version == "Irre's Beginner":
			easy = bm
	for bm in laur.difficulties:
		if bm.version == "Chimera":
			hard = bm
	Replay.dir = "user://replays_test"
	for cfg in [["入門(練習)", easy, ["practice"], 0], ["Chimera(通常。途中で死ぬ)", hard, [], 1], ["Chimera(小型化 + 撃破)", hard, ["boss", "shrink", "practice"], 2],
			["Chimera(弾幕 v1)", hard, ["v1", "practice"], 3]]:
		_test_roundtrip(cfg[0], cfg[1], cfg[2], cfg[3])
	_test_loops(easy)
	_test_files(easy)
	for n in _nodes:
		n.free()
	print("test_replay: ", "OK" if _fail == 0 else "%d FAILED" % _fail)
	quit(_fail)


## 録りながら、キーボード/マウスを混ぜて動くボットでプレイする(プレイ画面の _step_sim と同じ手順)。戻り値: 録ったもの + 最後の状態。
func _play(bm, mods: Array, seed_n: int, secs := SECS) -> Dictionary:
	var field := BulletField.new()
	_nodes.append(field)
	var g := Replay.build_game(field, bm, {"mods": mods, "density_mul": 1.0}, "", {})
	var sim = g.sim
	var rec := Replay.Recorder.new()
	rec.begin(sim, field, -1.5)
	var sim_t := -1.5
	var now := -1.5
	var i := 0
	while now < secs and not sim.finished:
		var span := 1.0 / 60.0 if (i / 400) % 2 == 0 else 1.0 / 144.0   # 描画のフレームレートが途中で変わる
		now += span
		var step := clampf(float(field.count) * 0.000002, 0.001, 0.004)
		var n := clampi(ceili((now - sim_t) / step), 1, 100)
		var dt := (now - sim_t) / float(n)
		var ang := sin(float(i) * 0.037 + float(seed_n)) * 3.0 + float(i) * 0.011
		var relative := (i / 700) % 2 == 1
		var vec := Vector2.from_angle(ang) * (2.5 if relative else 1.0)
		var slow := (i % 300) < 40
		var t0 := sim_t
		var span_real := now - sim_t
		for _k in range(n):
			sim_t += dt
			if relative:
				sim.step_relative(sim_t, dt, vec, slow)
			else:
				sim.step(sim_t, dt, vec, slow)
			if sim.finished:
				break
		if not sim.finished:
			sim_t = now
		rec.add(t0, span_real, n, vec, slow, relative, sim, field)
		i += 1
	return {"rec": rec, "sim": sim, "field": field, "gen": g, "digest": _digest(sim, field)}


func _digest(sim, field) -> Array:
	var d := [sim.gauge, sim.hits, sim.graze, sim.score, field.count, sim.player_pos, sim.bullets_fired, hash(field.pos.slice(0, field.count)),
		hash(field.vel.slice(0, field.count)), sim.finished, sim.failed, sim.loops_added, sim.damage_total, sim._ev_idx, sim.zone_debuff]
	if sim.boss != null:
		d.append_array([sim.boss.hp, sim.boss.pos, sim.boss.hits_total, sim.boss.power, sim.boss.items.size(), sim.boss.shots.size(), sim.boss._rng.state])
	return d


## 同じ譜面・同じ MOD で、新しく組み立てたシムを、記録から再生する。
func _player_for(bm, mods: Array, rec: Replay.Recorder) -> Replay.Player:
	var field := BulletField.new()
	_nodes.append(field)
	var g := Replay.build_game(field, bm, {"mods": mods, "density_mul": 1.0}, "", {})
	return Replay.Player.new(g.sim, field, rec.frames, rec.keys)


func _test_roundtrip(label: String, bm, mods: Array, seed_n: int) -> void:
	var played := _play(bm, mods, seed_n)
	var rec: Replay.Recorder = played.rec
	var sim = played.sim
	print("-- %s: %d フレーム, キーフレーム %d 個, 被弾 %d, 終了 %s%s" % [label, rec.frames.size() / Replay.STRIDE, rec.keys.size(), sim.hits, str(sim.finished), "(失敗)" if sim.failed else ""])
	var ts0 := Time.get_ticks_usec()
	for _i in range(10):
		Replay.State.snapshot(sim, played.field)
	print("      スナップショット 1 回: %.2f ms(弾 %d 発)" % [float(Time.get_ticks_usec() - ts0) / 10000.0, played.field.count])
	# 1) 先頭から通しで再生 → 最後の状態が同じ
	var p := _player_for(bm, mods, rec)
	p.advance_to(1.0e9)
	_check(p.idx == rec.frames.size() / Replay.STRIDE or p.sim.finished, "%s: 最後まで再生できる" % label)
	_check(_digest(p.sim, p.field) == played.digest, "%s: 通しで再生すると、最後の状態(ゲージ・スコア・弾の位置・ボス)が記録時と完全に同じ" % label)
	# 2) 途中の時刻でも同じ(記録時の途中と、再生の途中を、同じ時刻で比べる)
	var probe := _player_for(bm, mods, rec)
	var ref_marks := {}
	for tm in [5.0, 12.5, 23.0]:
		probe.advance_to(tm)
		ref_marks[tm] = _digest(probe.sim, probe.field)
	# 3) シーク(前・後ろ・近く・遠く)の結果が、通しで進めた同じ時刻の状態と同じ
	var sk := _player_for(bm, mods, rec)
	var order := [23.0, 5.0, 12.5, 23.0, 12.5, 6.0, 12.5, 5.0]
	var ok := true
	var bad := ""
	for tm in order:
		var tgt: float = clampf(tm, sk.start_time(), sk.end_time())
		sk.seek(tgt)
		var ref := _player_for(bm, mods, rec)
		ref.advance_to(tgt, false)
		if _digest(sk.sim, sk.field) != _digest(ref.sim, ref.field):
			ok = false
			bad = "%.1f" % tgt
			break
	_check(ok, "%s: シーク(前後・同じ場所へ)した状態が、先頭から通した状態と同じ %s" % [label, bad])
	# 4) シークのあと、続きを再生しても、最後は同じ
	sk.seek(8.0)
	sk.advance_to(1.0e9)
	_check(_digest(sk.sim, sk.field) == played.digest, "%s: シークのあとの続きも、最後の状態が同じ" % label)
	# 5) 記録を使った再計算の速さ(目安)
	var t0 := Time.get_ticks_msec()
	var sp := _player_for(bm, mods, rec)
	sp.seek(minf(30.0, sp.end_time()))
	print("      シーク 30 秒(最大 %.0f 秒ぶんの再計算): %d ms" % [Replay.KEY_INTERVAL, Time.get_ticks_msec() - t0])


## 撃破 MOD: 周回(弾幕を足していく)をまたぐシーク。後ろの周から前の周へ(切り詰め)、前の周から後ろの周へ(足す)戻しても、同じ状態になる。
func _test_loops(bm) -> void:
	var mods := ["boss", "practice"]
	var probe_field := BulletField.new()
	_nodes.append(probe_field)
	var probe = Replay.build_game(probe_field, bm, {"mods": mods, "density_mul": 1.0}, "", {}).sim
	var secs: float = probe.loop_from + probe.loop_len + 12.0
	var played := _play(bm, mods, 5, secs)
	var rec: Replay.Recorder = played.rec
	print("-- 撃破の周回: 1 周 %.1f 秒, %.0f 秒まで記録(周の数 %d), キーフレーム %d 個" % [probe.loop_len, secs, played.sim.loops_added, rec.keys.size()])
	_check(played.sim.loops_added >= 3, "2 周目に入って、3 周目の弾幕が足されている(loops_added = %d)" % played.sim.loops_added)
	var p := _player_for(bm, mods, rec)
	p.advance_to(1.0e9)
	_check(_digest(p.sim, p.field) == played.digest, "撃破の周回をまたいで通しで再生しても、最後の状態が同じ")
	var sk := _player_for(bm, mods, rec)
	var ok := true
	var bad := ""
	for tm in [secs - 3.0, 8.0, secs - 8.0, 20.0, secs - 1.0]:   # 後ろの周 → 前の周 → 後ろの周 …
		sk.seek(tm)
		var ref := _player_for(bm, mods, rec)
		ref.advance_to(tm, false)
		if _digest(sk.sim, sk.field) != _digest(ref.sim, ref.field):
			ok = false
			bad = "%.1f" % tm
			break
	_check(ok, "撃破: 周をまたぐシーク(前後)の状態が、先頭から通した状態と同じ %s" % bad)


func _test_files(bm) -> void:
	var played := _play(bm, ["practice"], 9)
	var rec: Replay.Recorder = played.rec
	var meta := {"md5": bm.md5, "title": bm.title, "artist": bm.artist, "version": bm.version, "settings": {"mods": ["practice"], "density_mul": 1.0}, "cond": "", "fp": Replay.fingerprint_of(played.sim)}
	var data := Replay.make_data(rec, meta, {"score": 123.0, "bg": null, "hits": 3})
	var name := Replay.save(data)
	_check(name != "" and FileAccess.file_exists(Replay.dir.path_join(name)), "ファイルに保存できる: %s" % name)
	var back := Replay.load_file(name)
	_check(not back.is_empty() and back.frames == rec.frames and back.trail == rec.trail and back.keys.size() == rec.keys.size(), "読み込むと、フレーム・軌道・キーフレームが同じ")
	_check(not back.stats.has("bg") and int(back.fp) == int(meta.fp) and back.md5 == bm.md5, "bg は保存せず、指紋・譜面の識別子が残る")
	# 読み込んだものを再生しても、最後は同じ
	var p := _player_for(bm, ["practice"], rec)
	p.frames = back.frames
	p.keys = back.keys
	p.advance_to(1.0e9)
	_check(_digest(p.sim, p.field) == played.digest, "ファイルから読んだ記録の再生も、最後の状態が同じ")
	p.seek(10.0)
	var q := _player_for(bm, ["practice"], rec)
	q.advance_to(10.0, false)
	_check(_digest(p.sim, p.field) == _digest(q.sim, q.field), "ファイルから読んだキーフレームへのシークも同じ")
	_check(Replay.load_file("no_such_file.rpl").is_empty(), "ないファイルは空の辞書")
	# 壊れたファイル・別の版
	var bad := FileAccess.open(Replay.dir.path_join("bad.rpl"), FileAccess.WRITE)
	bad.store_string("not a replay")
	bad.close()
	_check(Replay.load_file("bad.rpl").is_empty(), "壊れたファイルは読まない")
	# 整理: 古い順に KEEP 件へ。守るものは消さない
	for i in range(Replay.KEEP + 5):
		var f := FileAccess.open(Replay.dir.path_join("%d_dummy.rpl" % (1000 + i)), FileAccess.WRITE)
		f.store_string("x")
		f.close()
	Replay.prune(["1000_dummy.rpl"])
	var left := 0
	for n in DirAccess.get_files_at(Replay.dir):
		if str(n).ends_with(".rpl"):
			left += 1
	_check(left == Replay.KEEP, "整理すると %d 件になる(いま %d 件)" % [Replay.KEEP, left])
	_check(FileAccess.file_exists(Replay.dir.path_join("1000_dummy.rpl")), "守る指定のファイルは、古くても消さない")
	_check(not FileAccess.file_exists(Replay.dir.path_join("1001_dummy.rpl")), "守らない古いものは消える")
	for n in DirAccess.get_files_at(Replay.dir):
		DirAccess.remove_absolute(Replay.dir.path_join(n))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Replay.dir))
