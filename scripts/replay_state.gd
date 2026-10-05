extends RefCounted
## リプレイのキーフレーム: シム(GameSim)・弾(BulletField)・ボス(Boss)の状態を写し取り(snapshot)、あとで戻す(restore)。
## スクリプトの変数を、get_property_list で全部走査して複製するので、変数が増えても自動で含まれる(決定性が崩れたら、tests/test_replay.gd が見つける)。

## 複製しない変数: ノード・描画の資源・時刻で変わらない大きな表(弾幕の予定)。events / gizmos / breaks は、撃破 MOD の周回で後ろへ伸びるだけ(中身は決まっている)ので、大きさだけを覚える。
const SIM_SKIP := ["field", "boss", "events", "gizmos", "breaks", "zones", "_base_events", "_base_gizmos", "_base_breaks"]
const FIELD_SKIP := ["_mm_halo", "_mm_color", "_mm_core", "_mm_ring", "_mats", "_data_img", "_data_texs", "_data_k", "_sent",
	"halo", "soft", "vis_center", "vis_r0", "vis_r1"]
## ボスの _breaks は GameSim.breaks と同じ配列(複製すると切り離される)。_anchors / _t0s / _track は、周回で後ろへ伸びるだけ
const BOSS_SKIP := ["_breaks", "_rng", "_anchors", "_t0s", "_track"]
## 弾 1 発ごとの配列(長さは MAX_BULLETS で固定)。写すときは、弾の数(count)ぶんだけにして、戻すときに元の長さへ戻す(キーフレームが 100 分の 1 ほどになる。count より後ろは使われない)
const FIELD_PER_BULLET := ["pos", "vel", "rad", "col", "colf", "grace", "turn", "grazed", "kind", "age", "pa", "pb", "pc", "tscale", "wtgt"]


## いまのシム・弾・ボスの状態を、そのまま写し取る(あとで restore で戻せる)。
static func snapshot(sim, field: Node2D) -> Dictionary:
	var fc := _capture(field, FIELD_SKIP)
	var cnt: int = field.count
	var caps := {}
	for k in FIELD_PER_BULLET:
		if fc.has(k) and fc[k].size() > cnt:
			caps[k] = fc[k].size()
			fc[k] = fc[k].slice(0, cnt)
	var s := {"sim": _capture(sim, SIM_SKIP), "field": fc, "caps": caps,
		"ev_n": sim.events.size(), "giz_n": sim.gizmos.size(), "brk_n": sim.breaks.size()}
	if sim.boss != null:
		var b = sim.boss
		s["boss"] = _capture(b, BOSS_SKIP)
		s["rng"] = [b._rng.seed, b._rng.state]
		s["bn"] = [b._anchors.size(), b._t0s.size(), b._track.size()]
	return s


## snapshot で写した状態へ戻す。撃破 MOD で、いまが写した時点より前の周なら、周の予定を足してから(後の周なら切り詰めてから)戻す。
static func restore(sim, field: Node2D, s: Dictionary) -> void:
	if sim.boss != null:
		var want: int = int(s.sim.loops_added)
		if sim.loops_added < want and want >= 2:
			sim._extend_loop(float(want - 2) * sim.loop_len)   # loops_added が want になるまで、周を足す(boss.append_loop も呼ばれる)
		var b = sim.boss
		b._anchors.resize(int(s.bn[0]))
		b._t0s.resize(int(s.bn[1]))
		b._track.resize(int(s.bn[2]))
		_apply(b, s.boss)
		b._rng.seed = int(s.rng[0])
		b._rng.state = int(s.rng[1])
	sim.events.resize(int(s.ev_n))
	sim.gizmos.resize(int(s.giz_n))
	sim.breaks.resize(int(s.brk_n))
	_apply(sim, s.sim)
	_apply(field, s.field)
	var caps: Dictionary = s.get("caps", {})   # 数だけに縮めて写した配列は、元の長さへ戻す
	for k in caps:
		var a = field.get(k)
		a.resize(int(caps[k]))
		field.set(k, a)


## 写す変数の名前の一覧(クラスごとに 1 度だけ作る)。get_property_list は、裏のスレッドから呼ぶと落ちるので、裏で使う前に warm で主スレッドで作っておく。
static var _names := {}


static func _names_for(obj: Object, skip: Array) -> Array:
	var key := "%s|%s" % [obj.get_script().resource_path, ",".join(skip)]
	if not _names.has(key):
		var list: Array = []
		for p in obj.get_property_list():
			if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not skip.has(p.name):
				list.append(str(p.name))
		_names[key] = list
	return _names[key]


## 変数の名前の一覧を、主スレッドで作っておく(あとで、裏のスレッドが snapshot を呼べるように)。
static func warm(sim, field: Node2D) -> void:
	_names_for(sim, SIM_SKIP)
	_names_for(field, FIELD_SKIP)
	if sim.boss != null:
		_names_for(sim.boss, BOSS_SKIP)


static func _capture(obj: Object, skip: Array) -> Dictionary:
	var out := {}
	for name in _names_for(obj, skip):
		var v = obj.get(name)
		if v is Object or v is Callable or v is Signal or v is RID:
			continue
		out[name] = _copy(v)
	return out


static func _apply(obj: Object, d: Dictionary) -> void:
	for k in d:
		obj.set(k, _copy(d[k]))


static func _copy(v):
	if v is Array or v is Dictionary:
		return v.duplicate(true)
	if v is PackedByteArray or v is PackedInt32Array or v is PackedInt64Array or v is PackedFloat32Array or v is PackedFloat64Array \
			or v is PackedVector2Array or v is PackedVector3Array or v is PackedColorArray or v is PackedStringArray:
		return v.duplicate()
	return v
