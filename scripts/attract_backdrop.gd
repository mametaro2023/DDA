extends RefCounted
## タイトル画面の背景と曲の選び方(UI を持たない)。ランダムな曲(と、その中のランダムな譜面)を選んで、音声と背景画像を読み込む。
## 直前と同じ曲は避ける。読めない曲は飛ばす。classic も lazer も、タイトル画面はこれを使う(流す・切り替えるのは画面の仕事)。

const OszLoader = preload("res://scripts/osu/osz_loader.gd")
const SongLibrary = preload("res://scripts/song_library.gd")


## 次の曲を選んで読み込む。exclude は、避けたい曲(直前に流した曲)のパス。
## 返す辞書: {path, stream, tex(なければ null), start(試聴の開始位置・秒), title, artist}。曲が 1 つもない・どれも読めないときは空の辞書。
func pick(exclude := "") -> Dictionary:
	var paths := SongLibrary.find_all()
	if paths.is_empty():
		return {}
	paths.shuffle()
	if paths.size() > 1:
		paths.erase(exclude)
	for path in paths:
		var l = OszLoader.new()
		if not l.open(path):
			continue
		var bm = l.difficulties[randi() % l.difficulties.size()]
		var stream: AudioStream = l.load_audio(bm.audio_filename)
		var tex: Texture2D = l.load_image(bm.background) if bm.background != "" else null
		l.close()
		if stream == null:
			continue
		return {"path": path, "stream": stream, "tex": tex, "start": maxf(bm.preview_time / 1000.0, 0.0), "title": bm.title, "artist": bm.artist}
	return {}


## pick と同じものを、別スレッドで選んで読み込む(タイトルを開いた・曲が終わったときに、画面が止まらないように)。
## 終わると、メインスレッドで done(結果) を呼ぶ(結果の形は pick と同じ。画像は画面の大きさまで縮めてからテクスチャにする)。
## done の持ち主が先に消えていたら、何もしない。
static func pick_async(exclude: String, done: Callable) -> void:
	var paths := SongLibrary.find_all()
	WorkerThreadPool.add_task(func():
		var r := _pick_data(paths, exclude)
		_deliver.bind(r, done).call_deferred())


static func _pick_data(paths: Array, exclude: String) -> Dictionary:
	if paths.is_empty():
		return {}
	paths.shuffle()
	if paths.size() > 1:
		paths.erase(exclude)
	for path in paths:
		var l = OszLoader.new()
		if not l.open(path):
			continue
		var bm = l.difficulties[randi() % l.difficulties.size()]
		var stream: AudioStream = l.load_audio(bm.audio_filename)
		var img: Image = l.load_image_data(bm.background) if bm.background != "" else null
		l.close()
		if stream == null:
			continue
		if img != null and img.get_width() > 1600:   # 表示は 1280×720 を覆うだけなので、縮めてから渡す(テクスチャへの転送を軽く)
			img.resize(1600, int(round(img.get_height() * 1600.0 / img.get_width())), Image.INTERPOLATE_BILINEAR)
		return {"path": path, "stream": stream, "img": img, "start": maxf(bm.preview_time / 1000.0, 0.0), "title": bm.title, "artist": bm.artist}
	return {}


static func _deliver(r: Dictionary, done: Callable) -> void:
	if not done.is_valid():
		return
	if not r.is_empty():
		r["tex"] = ImageTexture.create_from_image(r.img) if r.img != null else null
	done.call(r)
