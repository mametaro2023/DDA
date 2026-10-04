extends RefCounted
## パース済みの osu!standard 譜面。

const KIND_CIRCLE := 0
const KIND_SLIDER := 1
const KIND_SPINNER := 2

const HS_WHISTLE := 2
const HS_FINISH := 4
const HS_CLAP := 8

var source_file := ""
## 譜面の中身の識別子(OsuParser.play_key。マルチプレイで、参加者が同じ譜面を持っているかの照合に使う。
## プレイに関わる部分だけから作るので、配布元・版が違っても、同じ譜面なら同じ値)
var md5 := ""
## osu! の譜面ID(BeatmapID: 難易度ごと / BeatmapSetID: 曲全体)。ダウンロードページのリンクに使う。無ければ 0
var beatmap_id := 0
var beatmapset_id := 0
var title := ""
var artist := ""
var version := ""
var creator := ""
var audio_filename := ""
var audio_lead_in := 0
var preview_time := 0
var mode := 0
var background := ""
var hp := 5.0
var cs := 5.0
var od := 5.0
var ar := 5.0
var ar_set := false
## 基準用の推定星評価(star_rating.gd)。パース後に設定される。
var stars := 0.0
var slider_multiplier := 1.4
var slider_tick_rate := 1.0

## 時刻順。各要素: {time, beat_length, uninherited, kiai, meter}
var timing_points: Array = []
## 時刻順。各要素は Dictionary:
##   kind, pos(Vector2), time, end_time, new_combo, hitsound, combo_index
##   スライダーのみ: curve(SliderPath), repeats, span_duration, edge_sounds
## 保存した情報から作った「軽い版」(from_meta)では、ノーツは重い(スライダーの曲線まで作る)ので、使うとき(弾幕を作り直すときなど)まで読み込まない。
## 最初・最後の時刻と密度は、保存した値を返すので、ノーツを読み込まない(first_time / last_time / density)。
var hit_objects: Array:
	get:
		if _lite:
			_load_lite()
		return _objs
	set(v):
		_objs = v
var _objs: Array = []
var _lite := false
var _lite_loader := Callable()   # ノーツを読み込んで返す関数(譜面のファイルを開き直す)
var _lite_first := 0.0
var _lite_last := 0.0
var _lite_density := 0.0
## [[start_ms, end_ms], ...]
var breaks: Array = []


func _point_index_at(t: float) -> int:
	var lo := 0
	var hi := timing_points.size() - 1
	var res := 0
	while lo <= hi:
		var mid := (lo + hi) >> 1
		if timing_points[mid].time <= t:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res


func beat_length_at(t: float) -> float:
	if timing_points.is_empty():
		return 500.0
	var idx := _point_index_at(t)
	for i in range(idx, -1, -1):
		if timing_points[i].uninherited:
			return timing_points[i].beat_length
	for i in range(idx + 1, timing_points.size()):
		if timing_points[i].uninherited:
			return timing_points[i].beat_length
	return 500.0


func sv_at(t: float) -> float:
	if timing_points.is_empty():
		return 1.0
	var p: Dictionary = timing_points[_point_index_at(t)]
	if p.uninherited or p.beat_length >= 0.0:
		return 1.0
	return clampf(-100.0 / p.beat_length, 0.1, 10.0)


## 時刻 t(ms)の拍の位相 0..1(直前の拍の頭が 0、次の拍の頭の直前が 1 に近い)。基準は、直前の非継承のタイミングポイント(赤線)。
func beat_phase_at(t: float) -> float:
	if timing_points.is_empty():
		return 0.0
	var idx := _point_index_at(t)
	var cand: Array = []
	for i in range(idx, -1, -1):
		if timing_points[i].uninherited:
			cand = [timing_points[i]]
			break
	if cand.is_empty():   # 最初の赤線より前 → 最初の赤線を基準に(位相は前の拍として続く)
		for i in range(idx + 1, timing_points.size()):
			if timing_points[i].uninherited:
				cand = [timing_points[i]]
				break
	if cand.is_empty() or cand[0].beat_length <= 0.0:
		return 0.0
	var len: float = cand[0].beat_length
	return fposmod(t - float(cand[0].time), len) / len


func kiai_at(t: float) -> bool:
	if timing_points.is_empty():
		return false
	return timing_points[_point_index_at(t)].kiai


func in_break(t: float) -> bool:
	for b in breaks:
		if t >= b[0] and t <= b[1]:
			return true
	return false


## AR から算出したアプローチ時間(ms)。予兆表示に使う。
func preempt_ms() -> float:
	if ar < 5.0:
		return 1200.0 + 600.0 * (5.0 - ar) / 5.0
	return 1200.0 - 750.0 * (ar - 5.0) / 5.0


func last_time() -> float:
	if _lite:
		return _lite_last
	if hit_objects.is_empty():
		return 0.0
	return hit_objects[hit_objects.size() - 1].end_time


func first_time() -> float:
	if _lite:
		return _lite_first
	if hit_objects.is_empty():
		return 0.0
	return hit_objects[0].time


## 難易度の目安: 1秒あたりのオブジェクト数(最初〜最後の間)。
func density() -> float:
	if _lite:
		return _lite_density
	if hit_objects.size() < 2:
		return 0.0
	var span := (last_time() - first_time()) / 1000.0
	if span <= 0.0:
		return 0.0
	return hit_objects.size() / span


## 保存用の情報(ノーツは含めない)。from_meta で、同じ譜面の軽い版に戻せる。
func to_meta() -> Dictionary:
	return {"source_file": source_file, "md5": md5, "beatmap_id": beatmap_id, "beatmapset_id": beatmapset_id, "title": title, "artist": artist,
		"version": version, "creator": creator, "audio_filename": audio_filename, "audio_lead_in": audio_lead_in, "preview_time": preview_time,
		"mode": mode, "background": background, "hp": hp, "cs": cs, "od": od, "ar": ar, "ar_set": ar_set, "stars": stars,
		"slider_multiplier": slider_multiplier, "slider_tick_rate": slider_tick_rate, "timing_points": timing_points, "breaks": breaks,
		"first": first_time(), "last": last_time(), "density": density()}


## to_meta の情報から、軽い版を作る。load_objects は、使うときに呼ぶ(ノーツの Array を返す関数)。
static func from_meta(d: Dictionary, load_objects: Callable):
	var bm = new()
	bm.source_file = str(d.source_file)
	bm.md5 = str(d.md5)
	bm.beatmap_id = int(d.beatmap_id)
	bm.beatmapset_id = int(d.beatmapset_id)
	bm.title = str(d.title)
	bm.artist = str(d.artist)
	bm.version = str(d.version)
	bm.creator = str(d.creator)
	bm.audio_filename = str(d.audio_filename)
	bm.audio_lead_in = int(d.audio_lead_in)
	bm.preview_time = int(d.preview_time)
	bm.mode = int(d.mode)
	bm.background = str(d.background)
	bm.hp = float(d.hp)
	bm.cs = float(d.cs)
	bm.od = float(d.od)
	bm.ar = float(d.ar)
	bm.ar_set = bool(d.ar_set)
	bm.stars = float(d.stars)
	bm.slider_multiplier = float(d.slider_multiplier)
	bm.slider_tick_rate = float(d.slider_tick_rate)
	bm.timing_points = d.timing_points
	bm.breaks = d.breaks
	bm._lite_first = float(d.first)
	bm._lite_last = float(d.last)
	bm._lite_density = float(d.density)
	bm._lite_loader = load_objects
	bm._lite = true
	return bm


func _load_lite() -> void:
	_lite = false   # 先に外す(読み込みの中で hit_objects を触っても、入れ子にならない)
	if _lite_loader.is_valid():
		var objs = _lite_loader.call()
		if objs is Array:
			_objs = objs


func display_name() -> String:
	return "%s - %s [%s]" % [artist, title, version]
