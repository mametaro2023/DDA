extends RefCounted
## 弾速の実験: 弾速が難易度に与える影響を、人間のプレイで確かめる(設定「その他」の「弾速の実験に参加する」)。
##
## Lv の計算は「弾が速いほど難しい」として、弾速を PatternGen.SPEED_EXP 乗で効かせている(実測した値ではない)。
## これが正しければ、同じ Lv に合わせて作った弾幕は、弾速が違っても同じくらい難しいはず。そこで、1 回のプレイごとに次の条件のどれかで弾幕を作り、
## 被弾の多さを記録して比べる:
##   slow  … 弾速 ×0.8   (同じ Lv。弾数は自動で増える)
##   base  … ふだんどおり
##   fast  … 弾速 ×1.25  (同じ Lv。弾数は自動で減る)
##   dense … 弾速はそのまま、目標の難易度 ×1.25(Lv が 1 段上)。「難易度が 25% 上がると被弾がどれだけ増えるか」の物差し(結果を SPEED_EXP の値に直すのに使う)
## 条件は、譜面ごとに、いちばん遊んだ回数の少ないものを選ぶ(同じ回数ならランダム。慣れの影響が条件に偏らないように)。
## プレイ中は条件を出さない(知っていると遊び方が変わるため)。選曲画面の Lv も変わらない(dense だけは、結果画面の Lv が上がる)。
## 実験するのは、ひとりで遊ぶときで、弾幕に効く MOD を付けていないときだけ(練習は可)。
## 記録は user://speed_study.csv(1 プレイ 1 行)。集計は tools/speed_study_report.gd。

const PatternGen = preload("res://scripts/game/pattern_gen.gd")

## 記録のファイル(確認用のテストでは、別のファイルに差し替える)
static var path := "user://speed_study.csv"
const CONDITIONS := {
	"slow": {"speed_mul": 0.8, "density_mul": 1.0},
	"base": {"speed_mul": 1.0, "density_mul": 1.0},
	"fast": {"speed_mul": 1.25, "density_mul": 1.0},
	"dense": {"speed_mul": 1.0, "density_mul": 1.25},
}
const ORDER := ["base", "slow", "fast", "dense"]
## 付けていても実験してよい MOD(弾幕・見え方を変えないもの)
const NEUTRAL_MODS := ["practice"]
const COLUMNS := ["time", "app", "map", "stars", "cond", "speed_mul", "density_mul", "speed", "size", "level", "mean",
	"control", "practice", "failed", "progress", "played_s", "hits", "hit_ms", "graze", "score"]
## 集計で、SPEED_EXP の推定を出すのに要る最低限(条件 slow・fast・dense・base がそろった譜面の数と、被弾の合計秒数)
const MIN_MAPS := 5
const MIN_HIT_S := 3.0


## この設定・状況で、実験するか。
static func eligible(settings: Dictionary, is_net: bool) -> bool:
	if is_net or not bool(settings.get("speed_study", false)):
		return false
	for id in settings.get("mods", []):
		if not NEUTRAL_MODS.has(str(id)):
			return false
	return true


## 譜面の名前(記録の鍵)。CSV の区切りの「,」は含めない。
static func map_key(bm) -> String:
	return str(bm.display_name()).replace(",", " ").replace("\n", " ")


## 条件を選ぶ: この譜面で遊んだ回数がいちばん少ない条件(同じならランダム)。
static func choose(key: String, rows: Array, rng: RandomNumberGenerator = null) -> String:
	var counts := {}
	for c in ORDER:
		counts[c] = 0
	for r in rows:
		if str(r.get("map", "")) == key and counts.has(str(r.get("cond", ""))):
			counts[str(r.cond)] += 1
	var least := 1 << 30
	for c in ORDER:
		least = mini(least, int(counts[c]))
	var cands: Array = []
	for c in ORDER:
		if int(counts[c]) == least:
			cands.append(c)
	var i := (rng.randi() if rng != null else randi()) % cands.size()
	return cands[i]


## 記録を読む(1 行 = 1 プレイの辞書。数値の列は float)。ファイルがなければ空。
static func read_rows(file := "") -> Array:
	var p := file if file != "" else path
	var out: Array = []
	if not FileAccess.file_exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	var header := f.get_line().split(",")
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var cells := line.split(",")
		var d := {}
		for i in range(mini(header.size(), cells.size())):
			var k := header[i]
			d[k] = cells[i] if k in ["time", "app", "map", "cond", "control"] else cells[i].to_float()
		out.append(d)
	return out


## 1 プレイを書き足す(ファイルがなければ見出しの行から作る)。
static func record(row: Dictionary, file := "") -> void:
	var p := file if file != "" else path
	var exists := FileAccess.file_exists(p)
	var f := FileAccess.open(p, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		push_warning("弾速の実験の記録を書けません: " + p)
		return
	if exists:
		f.seek_end()
	else:
		f.store_line(",".join(COLUMNS))
	var cells: Array = []
	for k in COLUMNS:
		var v = row.get(k, "")
		cells.append(str(v).replace(",", " ") if v is String else (("%.4f" % v) if v is float else str(v)))
	f.store_line(",".join(cells))
	f.close()


## 集計。条件ごとの被弾(1 分あたりの被弾秒数)と、base と比べた比、SPEED_EXP の推定(データが足りれば)を返す。
## 比は、比べる 2 つの条件を両方遊んだ譜面だけで出す(譜面ごとの被弾の多さ(1 分あたり)を足し合わせて割る。どの譜面も同じ重み)。
static func summarize(rows: Array) -> Dictionary:
	var by_map := {}   # 譜面 → 条件 → {hit_s, min, n, fails, progress}
	var per_cond := {}
	for c in ORDER:
		per_cond[c] = {"n": 0, "hit_s": 0.0, "min": 0.0, "fails": 0, "progress": 0.0}
	for r in rows:
		var c := str(r.get("cond", ""))
		if not per_cond.has(c):
			continue
		var m := str(r.get("map", ""))
		var hit_s := float(r.get("hit_ms", 0.0)) / 1000.0
		var mins := maxf(float(r.get("played_s", 0.0)), 1.0) / 60.0
		var pc: Dictionary = per_cond[c]
		pc.n += 1
		pc.hit_s += hit_s
		pc.min += mins
		pc.fails += 1 if float(r.get("failed", 0.0)) > 0.5 else 0
		pc.progress += float(r.get("progress", 1.0))
		if not by_map.has(m):
			by_map[m] = {}
		if not by_map[m].has(c):
			by_map[m][c] = {"hit_s": 0.0, "min": 0.0}
		by_map[m][c].hit_s += hit_s
		by_map[m][c].min += mins
	var out := {"conditions": {}, "ratios": {}, "maps_all": 0, "estimate": null, "note": ""}
	for c in ORDER:
		var pc: Dictionary = per_cond[c]
		out.conditions[c] = {"n": pc.n, "rate": pc.hit_s / maxf(pc.min, 1e-6), "fail_rate": float(pc.fails) / maxf(pc.n, 1),
			"progress": pc.progress / maxf(pc.n, 1), "minutes": pc.min}
	for c in ["slow", "fast", "dense"]:
		out.ratios[c] = _ratio(by_map, c, "base")
	out.ratios["fast/slow"] = _ratio(by_map, "fast", "slow")
	# SPEED_EXP の推定: 被弾は「本当の難しさ」の β 乗で増えるとみなす(β は dense と base の比から: β = log(比) / log(1.25))。
	# 同じ Lv(計算上の難しさが同じ)で、弾速が 1.25/0.8 倍のとき被弾が R 倍なら、本当の難しさは弾速の (SPEED_EXP + log R / (β log 1.5625)) 乗で効いている。
	var all_maps := 0
	var hit_total := 0.0
	for m in by_map:
		var ok := true
		for c in ORDER:
			if not by_map[m].has(c):
				ok = false
		if ok:
			all_maps += 1
			for c in ORDER:
				hit_total += float(by_map[m][c].hit_s)
	out.maps_all = all_maps
	var rd: Dictionary = out.ratios.dense
	var rfs: Dictionary = out.ratios["fast/slow"]
	if all_maps < MIN_MAPS or hit_total < MIN_HIT_S:
		out.note = "データが足りません(4 条件をすべて遊んだ譜面 %d / %d、被弾の合計 %.1f / %.0f 秒)" % [all_maps, MIN_MAPS, hit_total, MIN_HIT_S]
	elif rd.ratio == null or float(rd.ratio) <= 1.05:
		out.note = "dense(難易度 ×1.25)で被弾が増えていないため、物差しに使えません(dense / base = %s)" % ("-" if rd.ratio == null else "%.2f" % rd.ratio)
	elif rfs.ratio == null or float(rfs.ratio) <= 0.0:
		out.note = "fast と slow の比が出せません(被弾が 0)"
	else:
		var beta := log(float(rd.ratio)) / log(1.25)
		out.estimate = PatternGen.SPEED_EXP + log(float(rfs.ratio)) / (beta * log(1.25 / 0.8))
		out["beta"] = beta
	return out


## 条件 a と b を両方遊んだ譜面での、被弾の比(a / b)。{ratio(null なら出せない), maps}
static func _ratio(by_map: Dictionary, a: String, b: String) -> Dictionary:
	var sa := 0.0
	var sb := 0.0
	var n := 0
	for m in by_map:
		if by_map[m].has(a) and by_map[m].has(b):
			sa += float(by_map[m][a].hit_s) / maxf(float(by_map[m][a].min), 1e-6)
			sb += float(by_map[m][b].hit_s) / maxf(float(by_map[m][b].min), 1e-6)
			n += 1
	return {"ratio": (sa / sb) if sb > 0.0 else null, "maps": n}
