extends RefCounted
## パース済みの osu!standard 譜面。

const KIND_CIRCLE := 0
const KIND_SLIDER := 1
const KIND_SPINNER := 2

const HS_WHISTLE := 2
const HS_FINISH := 4
const HS_CLAP := 8

var source_file := ""
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
var hit_objects: Array = []
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
	if hit_objects.is_empty():
		return 0.0
	return hit_objects[hit_objects.size() - 1].end_time


func first_time() -> float:
	if hit_objects.is_empty():
		return 0.0
	return hit_objects[0].time


## 難易度の目安: 1秒あたりのオブジェクト数(最初〜最後の間)。
func density() -> float:
	if hit_objects.size() < 2:
		return 0.0
	var span := (last_time() - first_time()) / 1000.0
	if span <= 0.0:
		return 0.0
	return hit_objects.size() / span


func display_name() -> String:
	return "%s - %s [%s]" % [artist, title, version]
