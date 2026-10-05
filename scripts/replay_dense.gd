extends RefCounted
## リプレイの追加のキーフレーム(再生の係 Replay.Player が、飛ぶときに使う)。
## 記録に入っているキーフレームは 5 秒おきなので、まだ見ていないところへ飛ぶと、最大 5 秒ぶんをシミュレーションし直す(重い曲では 1 秒近く止まる)。
## そこで、再生を開いたら、裏のスレッドで別のシム(同じ譜面・MOD)を最初から流して、0.5 秒おきの状態を作っておく。
## 見ながら通ったところ(キャッシュ)も足す。飛ぶときは、記録のキーフレームと、これの中から、いちばん近いものを使う。
## 追加・取り出しは Mutex で守る(スレッドと主スレッドの両方が触る)。

const Replay = preload("res://scripts/replay.gd")
const BulletField = preload("res://scripts/game/bullet_field.gd")

const INTERVAL := 0.5   # 裏で作るキーフレームの間隔(秒)。1 個は 10〜15 KB なので、3 分の曲でも 4 MB ほど

var _mx := Mutex.new()
var _list: Array = []   # 時刻の順
var _thread: Thread
var _cancel := false
var done := false       # 裏の作業が、最後まで終わった


## 時刻 t の前後 gap 秒以内に、すでにあるか。
func near(t: float, gap: float) -> bool:
	_mx.lock()
	var hit := false
	for k in _list:
		if absf(float(k.t) - t) < gap:
			hit = true
			break
	_mx.unlock()
	return hit


func add(k: Dictionary) -> void:
	_mx.lock()
	var i := _list.size()
	while i > 0 and float(_list[i - 1].t) > float(k.t):
		i -= 1
	_list.insert(i, k)
	_mx.unlock()


## target 以前で、cur より後ろのものがあれば、そのうちいちばん近いキーフレーム。なければ cur。
func best(target: float, cur: Dictionary) -> Dictionary:
	var out := cur
	_mx.lock()
	for k in _list:
		if float(k.t) > target:
			break
		if float(k.t) > float(out.t):
			out = k
	_mx.unlock()
	return out


func count() -> int:
	_mx.lock()
	var n := _list.size()
	_mx.unlock()
	return n


## 裏で、最初から流しながら、INTERVAL 秒おきの状態を足していく。bm・settings・cond・practice_extra は、プレイ画面が組み立てたときと同じもの。ref_sim / ref_field: 主スレッドのシム・弾(同じクラスの物なら、何でもよい)。
func start(bm, settings: Dictionary, cond: String, practice_extra: bool, frames: PackedFloat64Array, keys: Array, ref_sim, ref_field: Node2D) -> void:
	Replay.State.warm(ref_sim, ref_field)   # 写す変数の名前の一覧を、主スレッドで作っておく(裏のスレッドでは作れない)
	_thread = Thread.new()
	_thread.start(_run.bind(bm, settings.duplicate(true), cond, practice_extra, frames, keys), Thread.PRIORITY_LOW)


func _run(bm, settings: Dictionary, cond: String, practice_extra: bool, frames: PackedFloat64Array, keys: Array) -> void:
	var field := BulletField.new()
	var g := Replay.build_game(field, bm, settings, cond, {}, practice_extra)   # 弾幕の組み立ては、主スレッドの物と共有しない(周回で伸びるので)
	var p := Replay.Player.new(g.sim, field, frames, keys)
	var next := p.start_time() + INTERVAL
	while not _cancel and not p.at_end():
		if p.next_start() > next:   # 記録のない区間(スキップしたイントロ)は、飛ばす
			next = p.next_start() + INTERVAL
		p.advance_to(next, false)
		if p.at_end():
			break
		if not near(p.t, INTERVAL * 0.5):
			add(p.make_key())
		next += INTERVAL
	field.free()
	done = not _cancel


## 裏の作業を止めて、終わるのを待つ(画面を離れるとき)。
func stop() -> void:
	_cancel = true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
