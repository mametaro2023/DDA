extends RefCounted
## 効果音のファイル(assets/sfx/<音>_<変種の番号>.sfx)を読み込んで、使い回す。
## ファイルは tools/sfx_forge.gd が作った標準の WAV(拡張子だけ .sfx)。Godot のインポートを通さず、そのまま読む
## (書き出した exe の中でも、export_presets.cfg の include_filter で同じように読める)。
## 名前が _loop で終わる音は、継ぎ目なくループ再生する音として読む(ループの印は WAV に入れず、ここで付ける)。
## 見つからない音は、警告を出して空の一覧を返す(その音は鳴らないだけで、ゲームは止まらない)。

const DIR := "res://assets/sfx/"
const MAX_VARIANTS := 16

static var _cache := {}   # 音の名前 → [AudioStreamWAV, ...]


## その音の変種の一覧(番号の順)。初めて呼ばれたときに読み込み、以後は同じものを返す。
static func variants(sfx_name: String) -> Array:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var list: Array = []
	for k in range(MAX_VARIANTS):
		var path := "%s%s_%d.sfx" % [DIR, sfx_name, k]
		if not FileAccess.file_exists(path):
			break
		var s := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
		if s != null:
			if sfx_name.ends_with("_loop"):
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = s.data.size() / (4 if s.stereo else 2)
			list.append(s)
	if list.is_empty():
		push_warning("効果音が見つかりません: " + sfx_name)
	_cache[sfx_name] = list
	return list


## まとめて先に読み込む(最初の再生で止まらないように、起動時に呼ぶ)。
static func preload_all(names: Array) -> void:
	for n in names:
		variants(str(n))


## 読み込み済みを捨てる(開発用)。
static func clear() -> void:
	_cache.clear()
