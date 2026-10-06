extends RefCounted
## サバイバルの曲の選び方と、選んだ譜面の用意(docs/survival_plan.md の §2)。
## 譜面の一覧は、曲の統計(ChartCache の .dcs。SongBrowser.start_prep が全曲ぶん裏で作る)から作る。統計のない曲は、まだ出さない。
## 選び方: 目標の Lv の ±0.3 → ±0.6 → ±1.0 → 長さの制限なし、の順に幅を広げ、まだ出していない曲(難易度違いも同じ曲)から、
## 目標に近いほど選ばれやすい重みで選ぶ。使い切ったら、出た曲を「加速」付きでもう一度(1 回だけ)。それもなければ、いちばん近い譜面。
## MOD を付けたときの Lv は、MOD なしの Lv × MOD の平均の上がり方(LV_EST)で見積もって選び、選んだ 1 譜面だけ、用意のときに測り直す。

const ChartCache = preload("res://scripts/chart_cache.gd")
const Mods = preload("res://scripts/mods.gd")
const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const SongBrowser = preload("res://scripts/song_browser.gd")

## MOD で上がる Lv の平均(mods.gd の「ベーススコアの加算の決め方」で測った値。46 譜面・弾幕 v2)。ない MOD は 1 倍(弾幕を変えない)
const LV_EST := {"hell": 1.25, "storm": 1.56, "giant": 1.57, "rush": 1.30, "heaven": 0.79, "slow": 0.75}
## 候補の幅と、長さの制限(true = MAX_LEN 秒を超える曲は出さない)
const STAGES := [[0.3, true], [0.6, true], [1.0, true], [1.0, false]]
const MAX_LEN := 180.0
const REPEAT_MOD := "rush"   # 使い切ったとき、もう一度出す曲に付ける MOD


## 同じ曲かどうかを見るキー(曲名とアーティスト。別の .osz・別の作り手の同じ曲も、同じとみなす)。
static func song_key(title: String, artist: String) -> String:
	return (title.strip_edges() + "|" + artist.strip_edges()).to_lower()


## 曲の一覧(SongBrowser.songs の要素 {path, ...})から、統計のある譜面の一覧を作る(別スレッドで動く)。
## 戻り値: [{path, md5, title, artist, version, key, lv(MOD なし), len(最後のノーツまでの秒), bg}]。読めた曲の path は got に足す。
static func read_charts(songs: Array, v2: bool, got: Dictionary = {}) -> Array:
	var out: Array = []
	for sg in songs:
		var path := str(sg.path)
		var saved := ChartCache.load_stats(path, v2)
		if saved.is_empty():
			continue
		got[path] = true
		var bms: Array = saved.get("bms", [])
		var stubs: Array = saved.get("stubs", [])
		for k in range(mini(bms.size(), stubs.size())):
			var m: Dictionary = bms[k]
			if int(m.get("mode", 0)) != 0:
				continue
			out.append({"path": path, "md5": str(m.md5), "title": str(m.title), "artist": str(m.artist), "version": str(m.version),
				"key": song_key(str(m.title), str(m.artist)), "lv": float((stubs[k] as Dictionary).get("level", 0.0)), "len": float(m.get("last", 0.0)) / 1000.0,
				"bg": str(m.get("background", ""))})
	return out


## MOD を付けたときの Lv の見積もり。
static func est_level(c: Dictionary, mod_ids: Array) -> float:
	var r := 1.0
	for id in Mods.params(mod_ids).ids:
		r *= float(LV_EST.get(id, 1.0))
	return float(c.lv) * r


## 曲の数(キーの種類)。準備画面に出す。
static func song_count(charts: Array) -> int:
	var keys := {}
	for c in charts:
		keys[c.key] = true
	return keys.size()


## 次の譜面を選ぶ。used: 出した曲のキー → 回数。戻り値: {chart, extra_mods(この曲だけ足す MOD), est(見積もりの Lv)}。譜面がなければ空の辞書。
static func pick(charts: Array, target: float, mod_ids: Array, used: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if charts.is_empty():
		return {}
	var rate := float(Mods.params(mod_ids).rate)
	for st in STAGES:
		var w: float = st[0]
		var cap: bool = st[1]
		var cands: Array = []
		for c in charts:
			if used.has(c.key) or (cap and float(c.len) / rate > MAX_LEN):
				continue
			var e := est_level(c, mod_ids)
			if absf(e - target) <= w:
				cands.append([c, e])
		if not cands.is_empty():
			var got: Array = _weighted(cands, target, w, rng)
			return {"chart": got[0], "extra_mods": [], "est": got[1]}
	# 使い切った: 1 回だけ出た曲を、加速付きでもう一度(減速・加速を付けているときは、しない)
	var p := Mods.params(mod_ids)
	if not p.ids.has(REPEAT_MOD) and not p.ids.has("slow"):
		var rmods := Mods.toggled(mod_ids, REPEAT_MOD, true)
		var again: Array = []
		for c in charts:
			if int(used.get(c.key, 0)) == 1:
				again.append([c, est_level(c, rmods)])
		var near := _nearest(again, target, 0.3)
		if not near.is_empty():
			var got2: Array = _weighted(near, target, 0.3, rng)
			return {"chart": got2[0], "extra_mods": [REPEAT_MOD], "est": got2[1]}
	# それもない: いちばん近い譜面(何度目でも)
	var all: Array = []
	for c in charts:
		all.append([c, est_level(c, mod_ids)])
	var got3: Array = _weighted(_nearest(all, target, 0.3), target, 0.3, rng)
	return {"chart": got3[0], "extra_mods": [], "est": got3[1]}


## いちばん近いものから margin 以内のもの。
static func _nearest(items: Array, target: float, margin: float) -> Array:
	if items.is_empty():
		return []
	var best := INF
	for it in items:
		best = minf(best, absf(float(it[1]) - target))
	return items.filter(func(it): return absf(float(it[1]) - target) <= best + margin)


## 目標に近いほど選ばれやすい重みで 1 つ選ぶ。items: [[chart, est], ...]
static func _weighted(items: Array, target: float, w: float, rng: RandomNumberGenerator) -> Array:
	var s := maxf(w * 0.6, 0.1)
	var ws: Array = []
	var total := 0.0
	for it in items:
		var d := (float(it[1]) - target) / s
		var x := exp(-d * d) + 0.02
		ws.append(x)
		total += x
	var r := rng.randf() * total
	for i in range(items.size()):
		r -= float(ws[i])
		if r <= 0.0:
			return items[i]
	return items.back()


## 選んだ譜面を、遊べる形にする(別スレッドで動く)。曲を開き、弾幕(発射の一覧まで)・MOD 込みの Lv・音声・背景の画像を用意する。
## 戻り値: {ok, error, loader, bm, gen(MOD 適用前), level(MOD 込み), audio, image}
static func load_chart(c: Dictionary, mod_ids: Array) -> Dictionary:
	var path := str(c.path)
	var p := Mods.params(mod_ids)
	var v2: bool = p.gen_v2
	var saved := ChartCache.load_stats(path, v2)
	var l := OszLoader.new()
	if saved.is_empty() or not l.open_cached(path, saved.bms):
		l = OszLoader.new()
		if not l.open(path):
			return {"ok": false, "error": l.error}
	var bm = null
	for d in l.difficulties:
		if str(d.md5) == str(c.md5):
			bm = d
	if bm == null:
		return {"ok": false, "error": "譜面が見つかりません"}
	var gen := SongBrowser.full_gen_for(path, bm, v2, true)
	var level := float(Mods.apply(gen, p).level)
	var audio: AudioStream = l.load_audio(bm.audio_filename)
	if audio == null:
		return {"ok": false, "error": "音声を読めません"}
	var image: Image = l.load_image_data(bm.background) if bm.background != "" else null
	if image != null and image.get_width() > 1280:
		image.resize(1280, maxi(int(round(1280.0 * image.get_height() / image.get_width())), 1), Image.INTERPOLATE_BILINEAR)
	return {"ok": true, "loader": l, "bm": bm, "gen": gen, "level": level, "audio": audio, "image": image}
