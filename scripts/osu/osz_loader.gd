extends RefCounted
## .osz(zip)を開き、譜面と音声/画像を取り出す。

const Beatmap = preload("res://scripts/osu/beatmap.gd")
const OsuParser = preload("res://scripts/osu/osu_parser.gd")

var path := ""
var error := ""
## osu!standard の譜面のみ。密度(easy→hard)順。
var difficulties: Array = []

var _reader: ZIPReader


func open(p: String) -> bool:
	path = p
	_reader = ZIPReader.new()
	var err := _reader.open(p)
	if err != OK:
		error = "osz を開けません: %s (%s)" % [p, error_string(err)]
		_reader = null
		return false
	for f in _reader.get_files():
		if f.to_lower().ends_with(".osu"):
			var bytes := _reader.read_file(f)
			var text := bytes.get_string_from_utf8()
			var bm := OsuParser.parse(text, f)
			bm.md5 = text.md5_text()
			if bm.mode == 0 and not bm.hit_objects.is_empty():
				difficulties.append(bm)
	if difficulties.is_empty():
		error = "osu!standard の譜面が見つかりません"
		close()
		return false
	# 暫定の並び(物量密度順)。メニューで DDA 難易度の順に並べ直す。
	difficulties.sort_custom(func(a, b): return a.density() < b.density())
	return true


func close() -> void:
	if _reader != null:
		_reader.close()
		_reader = null


func has_file(name: String) -> bool:
	if _reader == null:
		return false
	return _find(name) != ""


func read_file(name: String) -> PackedByteArray:
	var real := _find(name)
	if _reader == null or real == "":
		return PackedByteArray()
	return _reader.read_file(real)


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
	return ImageTexture.create_from_image(img)


## 大文字小文字を無視して zip 内のパスを探す。
func _find(name: String) -> String:
	var lower := name.to_lower()
	for f in _reader.get_files():
		if f.to_lower() == lower:
			return f
	return ""
