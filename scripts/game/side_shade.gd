extends ColorRect
## プレイ画面のアリーナの外(左右の余白)の背景。曲の絵を、ぼかして・彩度を落として・暗くして敷く。
## アリーナの縁では、アリーナの下地(暗幕)を通した絵と同じ明るさにして、境目の段差をなくす。外へ向かって、少しずつ明るくなる(縁から FEATHER_PX で OUTER に届く)。
## アリーナの中は何も描かない(透明)ので、中は元のまま。背景の絵(下の層)と同じ「画面いっぱい」の大きさで置き、リプレイで画面を縮めたときは refit で合わせ直す。

const ARENA_X := 160.0     # アリーナの左端(GameScreen.ARENA_POS.x)
const ARENA_W := 960.0     # アリーナの幅(PatternGen.ARENA.x)
const FEATHER_PX := 110.0  # 縁から、いちばん明るい所までの距離
const OUTER := 0.75        # 縁から離れた所の明るさ(背景の絵に掛ける BG_TINT を 1 とした割合)
const SAT := 0.55          # 彩度(1 = そのまま)

const CODE := """
shader_type canvas_item;
uniform sampler2D img : filter_linear_mipmap, repeat_disable;
uniform vec2 cover_scale = vec2(1.0);
uniform float edge_l = 0.125;
uniform float edge_r = 0.875;
uniform float feather = 0.09;
uniform float inner = 0.24;
uniform float outer = 0.75;
uniform float sat = 0.55;
uniform float gain = 1.0;
uniform vec3 tint = vec3(0.28, 0.28, 0.32);

void fragment() {
	float d = UV.x < 0.5 ? edge_l - UV.x : UV.x - edge_r;
	if (d <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = (UV - 0.5) * cover_scale + 0.5;
		float lod = 4.5;
		vec3 c = textureLod(img, uv, lod).rgb * 0.4;
		c += textureLod(img, uv + vec2(0.016, 0.0), lod).rgb * 0.15;
		c += textureLod(img, uv - vec2(0.016, 0.0), lod).rgb * 0.15;
		c += textureLod(img, uv + vec2(0.0, 0.016), lod).rgb * 0.15;
		c += textureLod(img, uv - vec2(0.0, 0.016), lod).rgb * 0.15;
		float g = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(vec3(g), c, sat);
		float k = mix(inner, outer, smoothstep(0.0, feather, d));
		COLOR = vec4(c * tint * (k * gain), 1.0);
	}
}
"""

var _mat: ShaderMaterial
var _tex_size := Vector2(16.0, 9.0)


## tex: 背景の絵。tint: 背景の絵に掛けている色(GameScreen.BG_TINT)。inner: アリーナの縁での明るさ(= 1 − 下地の不透明度)。
func setup(tex: Texture2D, tint: Color, inner: float) -> void:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()   # ぼかしは、ミップマップの小さい段(textureLod)で作る
	var mt := ImageTexture.create_from_image(img)
	_tex_size = Vector2(maxf(float(img.get_width()), 1.0), maxf(float(img.get_height()), 1.0))
	var sh := Shader.new()
	sh.code = CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("img", mt)
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mat.set_shader_parameter("outer", OUTER)
	_mat.set_shader_parameter("sat", SAT)
	_mat.set_shader_parameter("inner", inner)
	material = _mat
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 見える範囲(この画面の座標。左端・右端・下端)に合わせる。リプレイで画面を縮めると、範囲が広がる。
func refit(view_l: float, view_r: float, view_b: float) -> void:
	position = Vector2(view_l, 0.0)
	size = Vector2(view_r - view_l, view_b)
	var w := maxf(view_r - view_l, 1.0)
	_mat.set_shader_parameter("edge_l", (ARENA_X - view_l) / w)
	_mat.set_shader_parameter("edge_r", (ARENA_X + ARENA_W - view_l) / w)
	_mat.set_shader_parameter("feather", FEATHER_PX / w)
	# 絵を、背景と同じ「画面いっぱいに、はみ出す分は切る」置き方にする
	var na := w / maxf(view_b, 1.0)
	var ta := _tex_size.x / _tex_size.y
	_mat.set_shader_parameter("cover_scale", Vector2(1.0, ta / na) if na > ta else Vector2(na / ta, 1.0))


## キアイの拍で、背景の絵と同じだけ明るくする(1 = 通常)。
func set_gain(k: float) -> void:
	_mat.set_shader_parameter("gain", k)


## アリーナの下地の不透明度が変わったとき(キアイ)に、縁の明るさをそろえる。
func set_inner(v: float) -> void:
	_mat.set_shader_parameter("inner", v)
