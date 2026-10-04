extends RefCounted
## リプレイ: プレイの入力(フレームごとの進め方)だけを記録して、あとで同じシミュレーションをやり直す。
##
## GameSim は決定的(弾幕は譜面から決まり、ボスの乱数もシード固定)なので、入力を同じ順で与えれば、弾・ゲージ・スコアが全部同じになる。
## 記録するのは、GameScreen._step_sim の 1 フレームごとに { 始めの時刻 t0, 進めた幅 span, ステップ数 n, 入力(移動方向 or マウスの移動量), 低速, 操作方式 }。
## 再生(Player)は、同じ値で sim.step / sim.step_relative を呼ぶだけ(ステップの幅 = span / n、時刻は t0 から足していくのも同じ)。
##
## 好きな秒へ飛ぶ(シーク)ために、記録中に KEY_INTERVAL 秒ごとの状態(キーフレーム)も残す。シムは巻き戻せないので、
## 飛ぶときは「直前のキーフレームへ戻す → 目標の時刻まで再シミュレーション」。
## 弾幕の指紋(fingerprint)が合わないとき(曲・版・MOD が違う)は再生しない。
##
## 保存先は user://replays/(1 プレイ 1 ファイル。新しい順に KEEP 件まで。記録(records.gd)に載っているものは消さない)。

const GameSim = preload("res://scripts/game/game_sim.gd")
const PatternGen = preload("res://scripts/game/pattern_gen.gd")
const PatternGenV2 = preload("res://scripts/game/pattern_gen_v2.gd")
const Mods = preload("res://scripts/mods.gd")
const SpeedStudy = preload("res://scripts/speed_study.gd")
const SongLibrary = preload("res://scripts/song_library.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const State = preload("res://scripts/replay_state.gd")

const VERSION := 1
const MAGIC := "DDAR"
const KEEP := 30
const KEY_INTERVAL := 5.0
## frames の 1 フレームあたりの数: t0, span, n, 入力 x, 入力 y, フラグ(1 = 低速 / 2 = マウス操作)
const STRIDE := 6

## 保存先(確認用に差し替えられる)
static var dir := "user://replays"
## false のあいだは、保存しない(開発用の確認・スクリーンショットで、使う人のリプレイを汚さないため)
static var enabled := true
## true なら、開発用の自動操作(--smoke など)のプレイも記録する(--smoke-replay だけが使う)
static var force_record := false


## ゲームの組み立て(弾幕・MOD・シム)。プレイ画面と、リプレイの再生が、同じ手順で同じ sim を作る。
## settings は mods / density_mul を使う。study_cond: 弾速の実験の条件("" なら通常)。pre: 選曲で作っておいた {gen}(同じ作り方のときだけ使う)。
## 戻り値: {sim, gen, mods, rate, end_time}
static func build_game(field: Node2D, bm, settings: Dictionary, study_cond: String, pre: Dictionary, practice_extra := false) -> Dictionary:
	var dm := float(settings.get("density_mul", 1.0))
	var sc: Dictionary = SpeedStudy.CONDITIONS.get(study_cond, SpeedStudy.CONDITIONS.base)
	var plain := is_equal_approx(dm, 1.0) and is_equal_approx(sc.speed_mul, 1.0) and is_equal_approx(sc.density_mul, 1.0)
	var mods := Mods.params(settings.get("mods", []))
	var v2: bool = mods.gen_v2   # MOD「弾幕 v2」: 弾幕の作り方そのものを切り替える(選曲で作ったものも、同じ作り方のときだけ使う)
	var pre_gen: Dictionary = pre.get("gen", {})
	var same_style := (str(pre_gen.get("style", "v1")) == "v2") == v2
	var gen_opts := {"density_mul": dm * float(sc.density_mul), "speed_mul": float(sc.speed_mul)}
	var gen: Dictionary = pre_gen if (not pre_gen.is_empty() and plain and same_style) else (PatternGenV2.generate(bm, gen_opts) if v2 else PatternGen.generate(bm, gen_opts))
	gen = Mods.apply(gen, mods)   # MOD を掛け、その弾幕で難易度(Lv)を測り直す
	var rate: float = mods.rate
	var end_time: float = bm.last_time() / 1000.0 / rate + 2.0   # 再生速度が上がると、曲は短くなる
	var sim := GameSim.new()
	sim.setup(field, gen, end_time, mods.practice or practice_extra, mods)
	return {"sim": sim, "gen": gen, "mods": mods, "rate": rate, "end_time": end_time}


## 弾幕の指紋(マルチプレイの確認と同じ式)。曲・版・MOD が違えば変わる。sim.setup の直後の値。
static func fingerprint_of(sim) -> int:
	return sim.events.size() * 100003 + sim.bullets_total


# --- 記録 ---

## プレイ中の記録係。GameScreen._step_sim が、進めたフレームごとに add を呼ぶ。
class Recorder extends RefCounted:
	var frames := PackedFloat64Array()
	var trail := PackedVector2Array()      # 各フレームの終わりの自機の位置(軌道の表示用)
	var trail_t := PackedFloat64Array()    # その時刻
	var keys: Array = []                   # [{t, i, s}]: t = 状態の時刻 / i = 次に進めるフレームの番号 / s = スナップショット
	var _next_key := 0.0

	## 始めの状態(最初のフレームの前)を、最初のキーフレームにする。sim.setup のあとに呼ぶ。
	func begin(sim, field: Node2D, t_start: float) -> void:
		keys.append({"t": t_start, "i": 0, "s": State.snapshot(sim, field)})
		_next_key = t_start + KEY_INTERVAL

	func add(t0: float, span: float, n: int, vec: Vector2, slow: bool, relative: bool, sim, field: Node2D) -> void:
		frames.append(t0)
		frames.append(span)
		frames.append(float(n))
		frames.append(vec.x)
		frames.append(vec.y)
		frames.append(float((1 if slow else 0) | (2 if relative else 0)))
		var te := t0 + span
		trail.append(sim.player_pos)
		trail_t.append(te)
		if te >= _next_key and not sim.finished:
			keys.append({"t": te, "i": frames.size() / STRIDE, "s": State.snapshot(sim, field)})
			_next_key = te + KEY_INTERVAL


# --- 再生 ---

## 記録の再生係。sim / field は、記録したときと同じ手順(build_game)で作ったもの。
## 1 フレームの中の n 個のステップ(幅 dt)は、途中で止めて、あとで続きから進めてもよい(同じ順・同じ幅・同じ時刻の足し方なので、結果は変わらない)。
## 遅い再生(0.25 倍など)や、秒数へ飛ぶときに、フレームの途中で止まれるのは、これのおかげ。
class Player extends RefCounted:
	var sim
	var field: Node2D
	var frames: PackedFloat64Array
	var keys: Array
	var idx := 0          # いま進めているフレーム(まだ終わっていない)
	var sub := 0          # そのフレームの中で、すでに進めたステップ数
	var sub_t := 0.0      # そのときの、ステップの時刻(足し込んだ値。続きから、同じ足し方で進める)
	var force_restore := false   # 外から状態を動かした(ゲームオーバー演出で弾を進めた)ので、次のシークは、必ずキーフレームから戻す
	var t := 0.0          # いまの状態の時刻(フレームの途中なら、そのステップの時刻。まだなら、記録の始め)
	## 直前の advance で起きたこと(描画・音の側が読む。advance のたびに作り直す)
	var hit_any := false
	var hit_started := false
	var sfx: Array = []
	var sfx_pan: Array = []

	func _init(p_sim, p_field: Node2D, p_frames: PackedFloat64Array, p_keys: Array) -> void:
		sim = p_sim
		field = p_field
		frames = p_frames
		keys = p_keys
		t = start_time()

	func frame_count() -> int:
		return frames.size() / STRIDE

	func start_time() -> float:
		return frames[0] if frames.size() >= STRIDE else 0.0

	## 最後のフレームの終わりの時刻(再生の長さの端)。
	func end_time() -> float:
		var n := frame_count()
		return frames[(n - 1) * STRIDE] + frames[(n - 1) * STRIDE + 1] if n > 0 else 0.0

	func at_end() -> bool:
		return idx >= frame_count() or sim.finished

	## 時刻 target まで進める(フレームの途中のステップでも止まる)。collect: 音・被弾のようすを残すか(シークの再計算では false)。
	## budget_ms > 0 なら、その時間を超えたところで止める(倍速で、処理が間に合わないとき。時計は t まで)。戻り値: target まで進めたら true。
	func advance_to(target: float, collect := true, budget_ms := 0.0) -> bool:
		if collect:
			hit_any = false
			hit_started = false
			sfx = []
			sfx_pan = []
		var n := frame_count()
		var t_start := Time.get_ticks_usec()
		while idx < n:
			var b := idx * STRIDE
			var steps := int(frames[b + 2])
			if frames[b] + frames[b + 1] <= target:   # このフレームは、最後まで進める
				_run(b, collect, steps)
				idx += 1
				if budget_ms > 0.0 and float(Time.get_ticks_usec() - t_start) > budget_ms * 1000.0 and idx < n and frames[idx * STRIDE] + frames[idx * STRIDE + 1] <= target:
					return false
			else:   # このフレームの途中まで(target までに終わるステップだけ)
				var dt := frames[b + 1] / float(steps)
				var upto := mini(int(floor((target - frames[b]) / dt + 1.0e-9)), steps - 1)   # 最後のステップは、フレームの終わりとして扱う(下の「最後まで進める」)
				if upto > sub:
					if _run(b, collect, upto):   # 途中で sim が終わったら、このフレームも終わり
						idx += 1
				break
		return true

	## 次のフレームの始まりの時刻(もうなければ、とても大きい値)。いまの時刻より先なら、そのあいだは記録がない(スキップしたイントロ)。
	func next_start() -> float:
		return frames[idx * STRIDE] if idx < frame_count() else 1.0e30

	## 1 つ前のフレームの終わりの時刻(コマ戻し)。フレームの途中なら、そのフレームの始め。
	func prev_frame_time() -> float:
		if sub > 0 and idx < frame_count():
			return frames[idx * STRIDE]
		if idx < 2:
			return start_time()
		var b := (idx - 2) * STRIDE
		return frames[b] + frames[b + 1]

	## 1 フレームだけ進める(コマ送り。途中なら、そのフレームの残り)。進められたら true。
	func step_frame() -> bool:
		hit_any = false
		hit_started = false
		sfx = []
		sfx_pan = []
		if idx >= frame_count():
			return false
		_run(idx * STRIDE, true, int(frames[idx * STRIDE + 2]))
		idx += 1
		return true

	## フレーム b の、sub 番目から upto 番目の手前までのステップを進める(upto = n なら、フレームの終わりまで)。戻り値: フレームが終わった(sub は 0 に戻る。idx は、呼んだ側が進める)。
	func _run(b: int, collect: bool, upto: int) -> bool:
		var t0 := frames[b]
		var span := frames[b + 1]
		var n := int(frames[b + 2])
		var vec := Vector2(frames[b + 3], frames[b + 4])
		var fl := int(frames[b + 5])
		var slow := (fl & 1) != 0
		var rel := (fl & 2) != 0
		var dt := span / float(n)   # プレイ画面の _step_sim と同じ計算(同じ値が出る)
		var st := sub_t if sub > 0 else t0
		var k := sub
		while k < upto:
			st += dt
			k += 1
			if rel:
				sim.step_relative(st, dt, vec, slow)
			else:
				sim.step(st, dt, vec, slow)
			if collect:
				hit_any = hit_any or sim.hit_now
				hit_started = hit_started or sim.just_hit
				sfx.append_array(sim.sfx_queue)
				sfx_pan.append_array(sim.sfx_pan)
			if sim.finished:
				k = n   # 終わったら、残りのステップは進めない(プレイのときと同じ)
				break
		if k >= n:
			t = t0 + span
			sub = 0
			sub_t = 0.0
			return true
		t = st
		sub = k
		sub_t = st
		return false

	## 時刻 target の状態にする(前へも後ろへも)。直前のキーフレームから、再計算で追いつく。
	func seek(target: float) -> void:
		target = clampf(target, start_time(), end_time())
		var best: Dictionary = keys[0]
		for k in keys:
			if float(k.t) <= target:
				best = k
			else:
				break
		var from_here := idx > 0 and t <= target and t >= float(best.t) and not force_restore   # いまの状態のほうが、キーフレームより目標に近い(前から来ている)
		if not from_here:
			restore_key(best)
		force_restore = false
		advance_to(target, false)

	func restore_key(k: Dictionary) -> void:
		State.restore(sim, field, k.s)
		idx = int(k.i)
		sub = int(k.get("sub", 0))
		sub_t = float(k.get("st", 0.0))
		t = sub_t if sub > 0 else float(k.t)

	## いまの状態を、キーフレームの形で取る(区間の始点など。フレームの途中でもよい)。
	func make_key() -> Dictionary:
		return {"t": t, "i": idx, "sub": sub, "st": sub_t, "s": State.snapshot(sim, field)}


# --- ファイル ---

## 保存する中身を作る。meta: {md5, title, artist, version(難易度名), settings, cond, fp}。stats: GameScreen._stats()(bg は除く)。
static func make_data(rec: Recorder, meta: Dictionary, stats: Dictionary) -> Dictionary:
	var st := stats.duplicate()
	st.erase("bg")
	st.erase("mp")
	return {
		"v": VERSION,
		"app": str(ProjectSettings.get_setting("application/config/version", "")),
		"time": int(Time.get_unix_time_from_system()),
		"md5": str(meta.md5), "title": str(meta.title), "artist": str(meta.artist), "diff": str(meta.version),
		"settings": meta.settings, "cond": str(meta.get("cond", "")), "fp": int(meta.fp),
		"frames": rec.frames, "trail": rec.trail, "trail_t": rec.trail_t, "keys": rec.keys, "stats": st,
	}


## 最後まで流した状態が、記録した結果(stats)と合っているか(版が変わって、判定や弾の動きが変わっていないかの確認)。
static func verify(sim, st: Dictionary) -> bool:
	if st.is_empty():
		return true
	return int(sim.hits) == int(st.get("hits", sim.hits)) and int(sim.graze) == int(st.get("graze", sim.graze)) \
		and absf(float(sim.score) - float(st.get("score", sim.score))) < 0.5


## 動画の書き出し(別のプロセス)が、進み具合(0..1)を書くファイル。書き出しの親が読む。
const PROGRESS_PATH := "user://replay_export_progress.txt"


static func write_progress(frac: float) -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("%.4f" % frac)
		f.close()


static func read_progress() -> float:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return 0.0
	var v := f.get_as_text().to_float()
	f.close()
	return clampf(v, 0.0, 1.0)


static var _thread: Thread
static var _pending := ""   # 書き込み中のファイル名


## 保存するファイル名を決める(同じ秒に 2 つ(確認用の連続プレイ)でも、上書きしない)。
static func _unique_name(data: Dictionary) -> String:
	var base := "%d_%s" % [int(data.time), str(data.md5).substr(0, 8)]
	var name := base + ".rpl"
	var n := 1
	while FileAccess.file_exists(dir.path_join(name)) or name == _pending:
		name = "%s_%d.rpl" % [base, n]
		n += 1
	return name


static func _write(d: String, name: String, data: Dictionary) -> bool:
	var raw := var_to_bytes(data)
	var f := FileAccess.open(d.path_join(name), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(VERSION)
	f.store_64(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	return true


## ファイルへ書く(その場で。確認用)。戻り値: 書いたファイルの名前(dir の中。書けなければ "")。
static func save(data: Dictionary) -> String:
	flush()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var name := _unique_name(data)
	return name if _write(dir, name, data) else ""


## ファイルへ書く(裏のスレッドで。圧縮に数十 ms かかり、結果画面へ移るところで止まらないように)。名前はすぐ返す。
## 読む・整理するときは、書き終わるのを待つ(flush)。
static func save_async(data: Dictionary) -> String:
	flush()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var name := _unique_name(data)
	_pending = name
	_thread = Thread.new()
	_thread.start(_write.bind(dir, name, data))
	return name


## 裏の書き込みが終わるのを待つ。
static func flush() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
		_pending = ""


## ファイル名(save の戻り値)または path から読む。読めない・版が違うときは空の辞書。
static func load_file(name_or_path: String) -> Dictionary:
	flush()
	var path := name_or_path if name_or_path.contains("/") else dir.path_join(name_or_path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	if f.get_buffer(4).get_string_from_utf8() != MAGIC:
		return {}
	var ver := f.get_32()
	var raw_n := f.get_64()
	if ver != VERSION or raw_n <= 0 or raw_n > 1 << 30:
		return {}
	var body := f.get_buffer(f.get_length() - f.get_position())
	f.close()
	var raw := body.decompress(raw_n, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_n:
		return {}
	var d = bytes_to_var(raw)
	return d if d is Dictionary and int(d.get("v", 0)) == VERSION else {}


## 古い順に消して、KEEP 件にする(reserve: これから保存する件数ぶん、あけておく)。
## keep_names: 消さないファイル名(記録に載っているもの)。「保存」したもの(kept_names)は、消さず、件数にも入れない。
static func prune(keep_names: Array = [], reserve := 0) -> void:
	flush()
	var kept := kept_names()
	var names: Array = []
	for n in DirAccess.get_files_at(dir):
		if str(n).ends_with(".rpl") and not kept.has(str(n)):
			names.append(str(n))
	names.sort()   # 名前の先頭が時刻なので、古い順
	var over := names.size() - (KEEP - reserve)
	for n in names:
		if over <= 0:
			break
		if keep_names.has(n):
			continue
		DirAccess.remove_absolute(dir.path_join(n))
		over -= 1


## 消す(記録から外れたとき・一覧から消したとき)。
static func remove(name: String) -> void:
	flush()
	if name != "" and FileAccess.file_exists(dir.path_join(name)):
		DirAccess.remove_absolute(dir.path_join(name))
	if name != "" and kept_names().has(name):
		set_kept(name, false)


# --- 一覧(リプレイの一覧パネル) ---

const KEEP_FILE := "keep.json"     # 「保存」したリプレイのファイル名の配列(自動の整理で消さない)
const INDEX_FILE := "index.json"   # 一覧に出す要約の控え(ファイルを開かずに一覧を出すため。なくなっても、作り直せる)


static func _read_json(file: String) -> Variant:
	var f := FileAccess.open(dir.path_join(file), FileAccess.READ)
	if f == null:
		return null
	var v = JSON.parse_string(f.get_as_text())
	f.close()
	return v


static func _write_json(file: String, v: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir.path_join(file), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(v))
		f.close()


## 「保存」したリプレイのファイル名。
static func kept_names() -> Array:
	var v = _read_json(KEEP_FILE)
	return v if v is Array else []


static func set_kept(name: String, on: bool) -> void:
	var names := kept_names()
	if on and not names.has(name):
		names.append(name)
	elif not on:
		names.erase(name)
	_write_json(KEEP_FILE, names)


## ファイルの中身から、一覧に出す要約を作る。
static func _meta_from(name: String, d: Dictionary, size: int) -> Dictionary:
	var st: Dictionary = d.get("stats", {})
	var failed := bool(st.get("failed", false))
	var score := float(st.get("score", 0.0))
	return {
		"name": name, "size": size, "time": int(d.get("time", 0)), "md5": str(d.get("md5", "")),
		"title": str(d.get("title", "")), "artist": str(d.get("artist", "")), "diff": str(d.get("diff", "")),
		"mods": (d.get("settings", {}) as Dictionary).get("mods", []), "app": str(d.get("app", "")),
		"failed": failed, "score": int(round(score)), "level": float(st.get("level", 0.0)), "hits": int(st.get("hits", 0)),
		"rank": GameSim.rank_of(failed, int(st.get("hits", 0)), score, float(st.get("score_base", 1000000.0))),
		"dur": float(st.get("hp_t_end", 0.0)), "progress": float(st.get("progress", 1.0)),
	}


## 保存されているリプレイの要約の一覧(新しい順)。各要素: {name, time, md5, title, artist, diff, mods, failed, score, rank, level, hits, dur, progress, size, keep}
static func list() -> Array:
	flush()
	var cached = _read_json(INDEX_FILE)
	var idx: Dictionary = cached if cached is Dictionary else {}
	var kept := kept_names()
	var names: Array = []
	for n in DirAccess.get_files_at(dir):
		if str(n).ends_with(".rpl"):
			names.append(str(n))
	names.sort()
	names.reverse()   # 新しい順
	var changed := false
	var out: Array = []
	for n in names:
		var f := FileAccess.open(dir.path_join(n), FileAccess.READ)
		if f == null:
			continue
		var size := int(f.get_length())
		f.close()
		var m = idx.get(n)
		if not (m is Dictionary) or int(m.get("size", -1)) != size:
			var d := load_file(n)
			if d.is_empty():   # 読めない(別の版で作られた・壊れた)ものは、一覧に出さない
				continue
			m = _meta_from(n, d, size)
			idx[n] = m
			changed = true
		m = (m as Dictionary).duplicate()
		m["keep"] = kept.has(n)
		out.append(m)
	for n in idx.keys():   # なくなったファイルの控えは、捨てる
		if not names.has(n):
			idx.erase(n)
			changed = true
	if changed:
		_write_json(INDEX_FILE, idx)
	return out


## 曲を探して読む(リプレイの再生用)。戻り値: {loader, bm}。見つからなければ空の辞書。
static func find_chart(md5: String) -> Dictionary:
	var found := SongLibrary.find_by_md5(md5)
	if found.is_empty():
		return {}
	var loader := OszLoader.new()
	loader.open(found.path)
	for d in loader.difficulties:
		if d.md5 == md5:
			return {"loader": loader, "bm": d}
	return {}
