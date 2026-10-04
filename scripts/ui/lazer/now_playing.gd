extends RefCounted
## いま流れている曲(上のツールバーのプレイヤー lazer_player.gd が表示・操作する)。
## 曲を流す画面(タイトルの背景曲・選曲の試聴・マルチの試聴)が、流し始めるときに set_track で申告し、画面を離れるときに clear で取り下げる。
## 前の曲・次の曲は、画面ごとに意味が違う(選曲 = 一覧の前後の曲・タイトル = 別のランダムな曲)ので、画面が Callable で渡す(なければそのボタンは効かない)。

static var player: AudioStreamPlayer
static var title := ""
static var artist := ""
## 止まっているところから流し直すときの開始位置(秒。試聴の位置)
static var start := 0.0
static var on_prev := Callable()
static var on_next := Callable()
## 曲の入れ替わりのたびに増える(プレイヤーが表示を作り直すのに使う)
static var rev := 0


## p で曲を流す(流す直前に呼ぶ)。止められていたら、解除する。
static func set_track(p: AudioStreamPlayer, song_title: String, song_artist: String, start_at := 0.0, prev := Callable(), next := Callable()) -> void:
	player = p
	title = song_title
	artist = song_artist
	start = start_at
	on_prev = prev
	on_next = next
	if p != null:
		p.stream_paused = false
	rev += 1


## p の曲を取り下げる(別の画面がもう申告していたら、何もしない)。
static func clear(p: AudioStreamPlayer) -> void:
	if player != p:
		return
	player = null
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


## 曲の長さに対する、いまの位置の割合 0..1。
static func progress() -> float:
	if not is_set() or not player.playing:
		return 0.0
	var length := player.stream.get_length()
	return clampf(player.get_playback_position() / length, 0.0, 1.0) if length > 0.0 else 0.0
