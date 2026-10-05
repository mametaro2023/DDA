extends RefCounted
## プレイヤーの名前とアイコン(右上のプレイヤー名・プロフィールの変更パネルが使う)。
## 名前は settings.player_name(マルチプレイの表示名と同じ)。アイコンは settings.player_icon:
##   ""                  … 既定(ピンクの丸に、名前の頭文字)
##   "<色の番号>:<図柄>"  … 色(COLORS)と図柄(GLYPHS)の組み合わせ。図柄が "image" なら、選んだ画像(user://player_icon.png)を丸く切り抜いて使う
## 画像は、選んだとき正方形に切り抜いて IMAGE_PX に縮めて保存する(元のファイルには依存しない)。

const LazerStyle = preload("res://scripts/ui/lazer/lazer_style.gd")
const LazerIcons = preload("res://scripts/ui/lazer/lazer_icons.gd")

const IMAGE_PATH := "user://player_icon.png"
const IMAGE_PX := 128
const MAX_NAME := 16
const DEFAULT_NAME := "Player"
const COLORS := [
	Color(1.0, 0.400, 0.671), Color(0.400, 0.800, 1.0), Color(0.549, 0.400, 1.0), Color(0.698, 1.0, 0.400),
	Color(1.0, 0.867, 0.333), Color(0.878, 0.314, 0.416), Color(1.0, 0.62, 0.30), Color(0.85, 0.87, 0.95),
]
const GLYPHS := ["letter", "ship", "ring", "star", "heart", "bolt", "note"]
const GLYPH_NAMES := {"letter": "頭文字", "ship": "自機", "ring": "輪", "star": "星", "heart": "ハート", "bolt": "稲妻", "note": "音符", "image": "画像"}
const INK := Color(0.2, 0.05, 0.12)

## パネルを開く関数(main が渡す。lazer 風のツールバーの名前を押したとき)
static var open_cb := Callable()

static var _tex: Texture2D
static var _tex_time := -1


## アイコンの指定を {color, glyph} にする(不正・空は既定)。
static func parse(spec: String) -> Dictionary:
	var parts := spec.split(":")
	if parts.size() == 2 and (GLYPHS.has(parts[1]) or parts[1] == "image") and parts[0].is_valid_int():
		return {"color": clampi(int(parts[0]), 0, COLORS.size() - 1), "glyph": parts[1]}
	return {"color": 0, "glyph": "letter"}


static func spec_of(color: int, glyph: String) -> String:
	return "%d:%s" % [color, glyph]


## 表示する名前(空なら "Player")。
static func name_of(settings: Dictionary) -> String:
	var n := str(settings.get("player_name", "")).strip_edges()
	return n if n != "" else DEFAULT_NAME


## 保存した画像(なければ null)。ファイルが変わったら、読み直す。
static func texture() -> Texture2D:
	if not FileAccess.file_exists(IMAGE_PATH):
		_tex = null
		_tex_time = -1
		return null
	var t := FileAccess.get_modified_time(IMAGE_PATH)
	if _tex == null or t != _tex_time:
		var img := Image.load_from_file(ProjectSettings.globalize_path(IMAGE_PATH))
		_tex = ImageTexture.create_from_image(img) if img != null else null
		_tex_time = t
	return _tex


## 画像ファイルを、アイコンの画像として取り込む(正方形に切り抜いて縮める)。読めなければ false。
static func import_image(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	var side := mini(img.get_width(), img.get_height())
	var crop := img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	crop.resize(IMAGE_PX, IMAGE_PX, Image.INTERPOLATE_LANCZOS)
	if crop.save_png(ProjectSettings.globalize_path(IMAGE_PATH)) != OK:
		return false
	_tex = null
	return true


static func remove_image() -> void:
	if FileAccess.file_exists(IMAGE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IMAGE_PATH))
	_tex = null


## 名前とアイコンの指定を settings に入れる(保存は呼び出し側)。
static func apply(settings: Dictionary, name: String, spec: String) -> void:
	settings["player_name"] = name.strip_edges().left(MAX_NAME)
	settings["player_icon"] = spec


## ci の c を中心に、半径 r のアイコンを描く。spec = settings.player_icon・name = 表示する名前(頭文字に使う)。
static func draw_avatar(ci: CanvasItem, c: Vector2, r: float, spec: String, name: String) -> void:
	var p := parse(spec)
	var col: Color = COLORS[int(p.color)]
	var glyph: String = p.glyph
	var tex: Texture2D = texture() if glyph == "image" else null
	if glyph == "image" and tex != null:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in range(48):
			var a := TAU * float(i) / 48.0
			pts.append(c + Vector2.from_angle(a) * r)
			uvs.append(Vector2(0.5, 0.5) + Vector2.from_angle(a) * 0.5)
		ci.draw_colored_polygon(pts, Color.WHITE, uvs, tex)
		ci.draw_arc(c, r - 0.5, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.9), 1.5, true)
		return
	ci.draw_circle(c, r, col)
	if glyph == "image":
		glyph = "letter"   # 画像がなくなっていた
	match glyph:
		"letter":
			var fs := int(r * 1.2)
			var ch := name.substr(0, 1).to_upper()
			ci.draw_string(LazerStyle.font_bold(), Vector2(c.x - r, c.y + fs * 0.36), ch, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, INK)
		"ship":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.62), c + Vector2(r * 0.5, r * 0.5), c + Vector2(0, r * 0.22), c + Vector2(-r * 0.5, r * 0.5)]), INK)
		"ring":
			ci.draw_arc(c, r * 0.52, 0.0, TAU, 28, INK, maxf(r * 0.16, 1.2), true)
			ci.draw_circle(c, r * 0.14, INK)
		"star":
			var pts2 := PackedVector2Array()
			for i in range(10):
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				pts2.append(c + Vector2(0, r * 0.06) + Vector2.from_angle(a) * (r * 0.68 if i % 2 == 0 else r * 0.3))
			ci.draw_colored_polygon(pts2, INK)
		"heart":
			var hp := PackedVector2Array()
			for i in range(40):
				var t := TAU * float(i) / 40.0
				var x := 16.0 * pow(sin(t), 3.0)
				var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				hp.append(c + Vector2(x, -y + 1.5) * (r * 0.58 / 16.0))
			ci.draw_colored_polygon(hp, INK)
		"bolt":
			var bp := PackedVector2Array([Vector2(0.15, -0.8), Vector2(-0.45, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.8), Vector2(0.45, -0.15), Vector2(0.05, -0.15)])
			for i in range(bp.size()):
				bp[i] = c + bp[i] * r * 0.82
			ci.draw_colored_polygon(bp, INK)
		"note":
			LazerIcons.draw_icon(ci, "note", c + Vector2(r * 0.04, 0), r * 0.62, INK, maxf(r * 0.14, 1.4))
