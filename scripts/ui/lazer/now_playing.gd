extends RefCounted
## いま流れている曲(上のツールバーのプレイヤー lazer_player.gd が表示・操作する)。
## 曲を流す画面(タイトルの背景曲・選曲の試聴・マルチの試聴)が、流し始めるときに set_track で申告し、画面を離れるときに clear で取り下げる。
## 前の曲・次の曲は、画面ごとに意味が違う(選曲 = 一覧の前後の曲・タイトル = 別のランダムな曲)ので、画面が Callable で渡す(なければそのボタンは効かない)。
## プレイリストを流している間(Playlist.is_active)は、前・次・曲が終わったときが、プレイリストの順に進む。実際に曲を流すのは画面で、
## 画面は play_cb(曲のパスを渡すと、その曲を流す関数)を、開いている間だけ渡す(流せない画面・流せなかった曲は play_failed で知らせる)。

const Playlist = preload("res://scripts/playlist.gd")

static var player: AudioStreamPlayer
static var title := ""
static var artist := ""
## 流している曲の場所(プレイリストに足すのに使う。画面が申告しなければ空)
static var path := ""
## 止まっているところから流し直すときの開始位置(秒。試聴の位置)
static var start := 0.0
static var on_prev := Callable()
static var on_next := Callable()
## プレイリストの曲を流す関数 func(path: String)。タイトル・選曲が、開いている間だけ渡す
static var play_cb := Callable()
static var _play_owner: Object
## プレイリストのパネルを開く関数(main が渡す。上のプレイヤーのボタンが呼ぶ)
static var on_open_playlist := Callable()
static var _fail_streak := 0
## 流している音声が、曲の途中から切り出したものなら、曲全体の音声(full_stream)と、切り出した位置(offset 秒)。
## 表示・飛ぶ位置は、曲全体の時刻で扱う。飛ぶときに、曲全体の音声へ差し替える。
static var full_stream: AudioStream
static var offset := 0.0
## 曲の入れ替わりのたびに増える(プレイヤーが表示を作り直すのに使う)
static var rev := 0
## 「前」を押したとき、この秒数より聴いていたら、前の曲ではなく、その曲の頭へ戻る
const PREV_RESTART_SEC := 3.0


## p で曲を流す(流す直前に呼ぶ)。止められていたら、解除する。
static func set_track(p: AudioStreamPlayer, song_title: String, song_artist: String, start_at := 0.0, prev := Callable(), next := Callable(), song_path := "") -> void:
	player = p
	path = song_path
	title = song_title
	artist = song_artist
	start = start_at
	full_stream = null
	offset = 0.0
	on_prev = prev
	on_next = next
	if p != null:
		p.stream_paused = false
	rev += 1


## 画面が、プレイリストの曲を流す関数を渡す(owner = その画面。取り下げるときに、自分のものか確かめる)。
static func set_play_cb(owner: Object, cb: Callable) -> void:
	_play_owner = owner
	play_cb = cb
	rev += 1


static func clear_play_cb(owner: Object) -> void:
	if _play_owner == owner:
		_play_owner = null
		play_cb = Callable()
		rev += 1


## プレイリストの曲を流せる画面か。
static func can_play_playlist() -> bool:
	return play_cb.is_valid()


## プレイリストの list の t 番目から流し始める。流せなければ false。
static func play_playlist(list: int, t := 0) -> bool:
	if not play_cb.is_valid():
		return false
	var tr: Dictionary = Playlist.start(list, t)
	if tr.is_empty():
		return false
	_fail_streak = 0
	play_cb.call(str(tr.path))
	return true


## 前(d = -1)・次(d = 1)の曲へ。プレイリストを流している間はその順に(auto = 曲が終わって自然に進むとき)。それ以外は、画面が渡した前・次。
static func step(d: int, auto := false) -> void:
	if Playlist.is_active() and play_cb.is_valid():
		if d < 0 and not auto and is_set() and player.playing and player.get_playback_position() > PREV_RESTART_SEC:
			player.seek(0.0)   # 少し聴いたあとの「前」は、その曲の頭へ(押し直すと、前の曲へ)
			return
		var tr: Dictionary = Playlist.advance(d, auto)
		if not tr.is_empty():
			_fail_streak = 0
			play_cb.call(str(tr.path))
		return
	var cb := on_next if d > 0 else on_prev
	if cb.is_valid():
		cb.call()


## 画面が、プレイリストの曲を流せなかった(曲がなくなっている・読めない)。次の曲へ進む(全部だめなら、止める)。
static func play_failed() -> void:
	_fail_streak += 1
	if not Playlist.is_active() or _fail_streak > Playlist.lists[Playlist.playing].tracks.size():
		Playlist.stop()
		return
	step(1, false)


## 前・次の曲へ進めるか(ボタンを明るくするか)。
static func can_step(d: int) -> bool:
	if not is_set():
		return false
	if Playlist.is_active() and play_cb.is_valid():
		return true
	return (on_next if d > 0 else on_prev).is_valid()


## 流している音声が切り出したものだと知らせる(set_track の直後に呼ぶ)。
static func set_full(full: AudioStream, cut_at: float) -> void:
	full_stream = full
	offset = cut_at


## p の曲を取り下げる(別の画面がもう申告していたら、何もしない)。
static func clear(p: AudioStreamPlayer) -> void:
	if player != p:
		return
	player = null
	path = ""
	title = ""
	artist = ""
	on_prev = Callable()
	on_next = Callable()
	rev += 1


static func is_set() -> bool:
	return player != null and is_instance_valid(player) and player.stream != null


static func is_playing() -> bool:
	return is_set() and player.playing and not player.stream_paused


## 再生 ⇔ 一時停止(止まっていたら、開始位置から流し直す)。
static func toggle() -> void:
	if not is_set():
		return
	if player.stream_paused:
		player.stream_paused = false
	elif player.playing:
		player.stream_paused = true
	else:
		player.play(start)


## 秒を「m:ss」にする。
static func fmt(sec: float) -> String:
	var s := maxi(int(sec), 0)
	return "%d:%02d" % [s / 60, s % 60]


## 曲の長さ・いまの位置(秒)。流していなければ 0。
static func length() -> float:
	if not is_set():
		return 0.0
	return full_stream.get_length() if full_stream != null else player.stream.get_length()


static func position() -> float:
	if not is_set() or not player.playing:
		return 0.0
	return clampf(player.get_playback_position() + offset, 0.0, length())


## 曲の長さに対する、いまの位置の割合 0..1。
static func progress() -> float:
	var l := length()
	return clampf(position() / l, 0.0, 1.0) if l > 0.0 else 0.0


## 曲の frac(0..1)の位置へ飛ぶ。止まっていた(最後まで流した・止めた)ときは、そこから流し始める。一時停止中は、止めたまま位置だけ動かす。
static func seek_to(frac: float) -> void:
	var l := length()
	if l <= 0.0:
		return
	var t := clampf(frac, 0.0, 1.0) * l
	t = minf(t, maxf(l - 0.1, 0.0))   # 最後ちょうどだと、すぐ終わってしまう
	if full_stream != null and player.stream != full_stream:   # 切り出した音声の外(や頭の側)へも飛べるように、曲全体の音声へ替える
		var was_paused := player.stream_paused
		player.stream = full_stream
		offset = 0.0
		player.play(t)
		player.stream_paused = was_paused
	elif player.playing:
		player.seek(t - offset)
	else:
		player.play(t - offset)

