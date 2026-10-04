extends RefCounted
## .osz(zip)、または osu! の Songs フォルダの中の 1 曲ぶんのフォルダ(.osz を展開したもの)を開き、譜面と音声/画像を取り出す。

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const OsuParser = preload("res://scripts/osu/osu_parser.gd")

var path := ""
var error := ""
## osu!standard の譜面のみ。密度(easy→hard)順。
var difficulties: Array = []

var _reader: ZIPReader
var _dir := ""                           # フォルダとして開いたときの、そのフォルダ(zip のときは空)
var _dir_files: PackedStringArray = []   # フォルダ直下のファイル名

## osu! の譜面のモード(Mode の番号)の名前
const MODE_NAMES := {0: "osu!standard", 1: "taiko", 2: "catch", 3: "mania"}


## osu!standard の譜面がないときの説明。入っていた譜面のモードを添える(mania だけの曲を開いた、などが分かるように)。
static func no_standard_message(modes: Array) -> String:
	var names: Array = []
	for m in modes:
		var nm: String = MODE_NAMES.get(int(m), "?")
		if int(m) != 0 and not names.has(nm):
			names.append(nm)
	var inside := ("(入っているのは %s の譜面だけです)" % "・".join(names)) if not names.is_empty() else ""
	return "osu!standard(通常モード)の譜面が入っていません%s。このアプリは osu!standard の譜面にだけ対応しています" % inside


## zip として開けないときの説明。
static func zip_error_message(err: int) -> String:
	return "zip として開けません(%s)。ダウンロードが途中で終わっていないか、確かめてください" % error_string(err)


## パスがフォルダか(osu! の Songs フォルダの中の 1 曲。.osz はファイルなので false)。
static func is_folder(p: String) -> bool:
	return DirAccess.dir_exists_absolute(p)


## 曲の入れもの(zip またはフォルダ)を開く。中の譜面は読まない。開けなければ false(理由は error)。
func _open_container(p: String) -> bool:
	path = p
	_dir = ""
	if is_folder(p):
		_dir = p
		_dir_files = DirAccess.get_files_at(p)
	else:
		_reader = ZIPReader.new()
		var err := _reader.open(p)
		if err != OK:
			error = zip_error_message(err)
			_reader = null
			return false
	return true


## 保存した情報(Beatmap.to_meta の一覧。難易度の並びのまま)から、譜面を解析せずに開く(ChartCache)。
## 譜面は軽い版で、ノーツは、使うときに、その譜面のファイルだけを開き直して読み込む。
func open_cached(p: String, metas: Array) -> bool:
	if not _open_container(p):
		return false
	for m in metas:
		var file := str(m.source_file)
		difficulties.append(Beatmap.from_meta(m, Callable(get_script(), "read_objects").bind(p, file)))   # この OszLoader を持たない(持つと、譜面と互いに参照し合って、解放されない)
	if difficulties.is_empty():
		close()
		return false
	return true


## p の中の譜面ファイル file を解析して、ノーツだけを返す(軽い版が、使うときに呼ぶ。開き直すので、元の OszLoader が閉じていてもよい)。
static func read_objects(p: String, file: String) -> Array:
	var l := new()
	if not l._open_container(p):
		return []
	var real := l._find(file)
	var bm := OsuParser.parse(l._read(real if real != "" else file).get_string_from_utf8(), file) if real != "" else null
	l.close()
	return bm.hit_objects if bm != null else []


func open(p: String) -> bool:
	if not _open_container(p):
		return false
	var modes: Array = []   # 入っていた譜面のモード(osu!standard がないときの説明に使う)
	for f in _files():
		if f.to_lower().ends_with(".osu"):
			var bytes := _read(f)
			var text := bytes.get_string_from_utf8()
			var bm := OsuParser.parse(text, f)
			bm.md5 = OsuParser.play_key(text)
			if bm.beatmapset_id <= 0:   # 古い譜面は BeatmapSetID を持たない。osu! の .osz は「曲ID 曲名.osz」なので、名前の先頭の数字を使う
				var head := p.get_file().split(" ")[0]
				if head.is_valid_int():
					bm.beatmapset_id = int(head)
			modes.append(bm.mode)
			if bm.mode == 0 and not bm.hit_objects.is_empty():
				difficulties.append(bm)
	if difficulties.is_empty():
		error = no_standard_message(modes)
		close()
		return false
	# 暫定の並び(物量密度順)。メニューで Danmaku 難易度の順に並べ直す。
	difficulties.sort_custom(func(a, b): return a.density() < b.density())
	return true


func close() -> void:
	if _reader != null:
		_reader.close()
		_reader = null


func has_file(name: String) -> bool:
	return _find(name) != ""


func read_file(name: String) -> PackedByteArray:
	var real := _find(name)
	if real == "":
		return PackedByteArray()
	return _read(real)


func load_audio(name: String) -> AudioStream:
	var bytes := read_file(name)
	if bytes.is_empty():
		return null
	var ext := name.get_extension().to_lower()
	if ext == "mp3":
		var s := AudioStreamMP3.new()
		s.data = bytes
		return s
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null


func load_image(name: String) -> Texture2D:
	var img := load_image_data(name)
	return ImageTexture.create_from_image(img) if img != null else null


## 画像の読み込み(デコードまで)。別スレッドで動かせる(テクスチャにするのは、呼び出し側で)。
func load_image_data(name: String) -> Image:
	var bytes := read_file(name)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var ext := name.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	if ext == "jpg" or ext == "jpeg":
		err = img.load_jpg_from_buffer(bytes)
	elif ext == "png":
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return img


## 中にあるファイルの名前(zip の中のパス、またはフォルダ直下のファイル名)。
func _files() -> PackedStringArray:
	if _dir != "":
		return _dir_files
	return _reader.get_files() if _reader != null else PackedStringArray()


func _read(real: String) -> PackedByteArray:
	if _dir != "":
		return FileAccess.get_file_as_bytes(_dir.path_join(real))
	return _reader.read_file(real)


## 大文字小文字を無視して、中のファイルを探す(フォルダのときは、直下になければ「sub/a.mp3」のような下の階層も見る)。
func _find(name: String) -> String:
	var lower := name.replace("\\", "/").to_lower()
	for f in _files():
		if f.to_lower() == lower:
			return f
	if _dir != "" and lower.contains("/") and not lower.contains("..") and FileAccess.file_exists(_dir.path_join(lower)):
		return lower
	return ""
