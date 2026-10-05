extends Control
## 遊び方パネル(タイトル画面の上に重ねる)。ゲーム中の画面には説明文を出さない代わりに、説明はすべてここに集める。
## 左に見出し(はじめに / 画面の見かた / 操作 / 弾とグレイズ / 特殊エリア / ゲージとスコア / MOD / 選曲画面 / マルチプレイ / 曲の追加)、右に内容。
## 文章のほかに、ゲームの絵と同じ色・形で描いた挿絵(howto_art.gd)と、色つきの囲み(_callout)・番号つきの説明(_numrow)で、ひとつずつ丁寧に説明する。右上の ✕ / 閉じる / パネルの外 / Esc で閉じる。

signal closed

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")
const HowtoArt = preload("res://scripts/ui/howto_art.gd")
const GameSim = preload("res://scripts/game/game_sim.gd")

const SECTIONS := ["はじめに", "画面の見かた", "操作", "弾とグレイズ", "特殊エリア", "ゲージとスコア", "MOD", "選曲画面", "マルチプレイ", "曲の追加"]
## 各セクションの中身を作る関数(SECTIONS と同じ並び。lazer 版も、これを使う)
const PAGE_BUILDERS := ["_page_intro", "_page_hud", "_page_controls", "_page_graze", "_page_zones", "_page_score", "_page_mods", "_page_select", "_page_multi", "_page_songs"]

var _pages: Array = []
var _nav: Array = []
var _dim: ColorRect
var _panel: PanelContainer
var _cur := -1
var _closing := false


func _ready() -> void:
	theme = UiStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var panel := PanelContainer.new()
	_panel = panel
	panel.position = Vector2(150, 36)
	panel.size = Vector2(980, 648)
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, UiStyle.LINE, 1, 8, 0, 0))
	add_child(panel)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)

	# 左: 見出し
	var nav_box := VBoxContainer.new()
	nav_box.custom_minimum_size = Vector2(210, 0)
	nav_box.add_theme_constant_override("separation", 6)
	var nav_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		nav_margin.add_theme_constant_override("margin_" + side, 22)
	nav_margin.add_child(nav_box)
	root.add_child(nav_margin)
	nav_box.add_child(UiStyle.label("HOW TO PLAY", 22, UiStyle.TEXT, true))
	nav_box.add_child(UiStyle.caption("遊び方"))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	nav_box.add_child(sp)
	var group := ButtonGroup.new()
	for i in range(SECTIONS.size()):
		var b := Button.new()
		b.text = SECTIONS[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _show(i))
		nav_box.add_child(b)
		_nav.append(b)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_box.add_child(fill)
	var close := Button.new()
	close.text = "閉じる"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	nav_box.add_child(close)
	var vline := ColorRect.new()
	vline.color = UiStyle.LINE
	vline.custom_minimum_size = Vector2(1, 0)
	root.add_child(vline)

	# 右: 内容(各セクションはスクロールできる)
	var content_margin := MarginContainer.new()
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content_margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(content_margin)
	var stack := Control.new()
	content_margin.add_child(stack)
	for fn in PAGE_BUILDERS:
		_pages.append(call(fn))
	for p in _pages:
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	var x_btn := UiStyle.close_button(close_panel)   # 右上の ✕(スクロールバーと重ならないよう、少し内側)
	x_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	x_btn.offset_left = -52.0
	x_btn.offset_right = -14.0
	x_btn.offset_bottom = 36.0
	stack.add_child(x_btn)
	UiStyle.close_on_outside_click(self, panel, close_panel)
	_show(0)
	UiStyle.tween(_dim, "color:a", 0.0, 0.7, 0.22)
	UiStyle.pop_scale(panel, 0.93, 0.42)
	for k in range(_nav.size()):   # 項目が上から順に、弾んで現れる
		UiStyle.pop_scale(_nav[k], 0.88, 0.4, 0.12 + 0.05 * k)


func _show(i: int) -> void:
	var changed_page: bool = not _pages[i].visible
	var dir := 1 if i >= _cur else -1
	var first := _cur < 0
	_cur = i
	for k in range(_pages.size()):
		_pages[k].visible = (k == i)
		_nav[k].set_pressed_no_signal(k == i)
	if changed_page and _panel != null and _panel.is_inside_tree():
		UiStyle.tween(_pages[i], "modulate:a", 0.0, 1.0, 0.25)
		if not first:
			UiStyle.slide_page(_pages[i], 30.0 * dir)
			UiSfx.play("select", UiSfx.scale_pitch(float(i) / maxf(_pages.size() - 1, 1.0), 1.0))


func close_panel() -> void:
	if _closing:
		return
	_closing = true
	UiSfx.play("close")
	if not UiStyle.animate:
		closed.emit()
		return
	_panel.pivot_offset = _panel.size * 0.5
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_panel, "modulate:a", 0.0, 0.16)
	t.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(func(): closed.emit())


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			var cur := 0
			for k in range(_pages.size()):
				if _pages[k].visible:
					cur = k
			_show((cur + (-1 if event.shift_pressed else 1) + _pages.size()) % _pages.size())
			get_viewport().set_input_as_handled()
		KEY_UP, KEY_DOWN:
			var cur2 := 0
			for k in range(_pages.size()):
				if _pages[k].visible:
					cur2 = k
			_show(clampi(cur2 + (-1 if event.keycode == KEY_UP else 1), 0, _pages.size() - 1))
			get_viewport().set_input_as_handled()


# --- 部品 ---

## スクロールできるセクションの器。中身を入れる VBox を返す([スクロール, VBox])。
func _section(title: String) -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	scroll.add_child(v)
	v.add_child(UiStyle.label(title, 24, UiStyle.TEXT, true))
	v.add_child(UiStyle.hline())
	return [scroll, v]


func _para(v: VBoxContainer, text: String, color := UiStyle.TEXT_DIM, size := 15) -> void:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(l)


func _head(v: VBoxContainer, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap)
	v.add_child(UiStyle.label(text, 17, UiStyle.ACCENT, true))


## 挿絵(howto_art.gd)を置く。
func _art(v: VBoxContainer, kind: String) -> void:
	v.add_child(HowtoArt.make(kind))


## 色つきの囲み: 左に太い線、見出し(色つき)と、説明。ヒント・注意・要点に使う。
func _callout(v: VBoxContainer, title: String, text: String, color: Color) -> void:
	var p := PanelContainer.new()
	var sb := UiStyle.box(Color(color.r, color.g, color.b, 0.09), Color(color.r, color.g, color.b, 0.35), 1, 8, 14, 10)
	sb.border_width_left = 4
	sb.border_color = color
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 3)
	b.add_child(UiStyle.label(title, 15, color, true))
	var l := UiStyle.label(text, 14, UiStyle.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(l)
	p.add_child(b)
	v.add_child(p)


## 番号つきの説明(絵の中の番号と対応させる・手順を並べる)。番号は黄色い丸。
func _numrow(v: VBoxContainer, n: int, title: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiStyle.box(Color(1.0, 0.85, 0.3), Color(0, 0, 0, 0), 0, 12, 0, 0))
	badge.custom_minimum_size = Vector2(24, 24)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UiStyle.label(str(n), 14, Color(0.1, 0.07, 0.0), true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(nl)
	h.add_child(badge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiStyle.label(title, 15, UiStyle.TEXT, true))
	var t := UiStyle.label(text, 14, UiStyle.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(t)
	h.add_child(col)
	v.add_child(h)


## 「キー … 内容」の 1 行。key_color の不透明度が 0 でなければ、見出しをその色にする。
func _row(v: VBoxContainer, key: String, text: String, key_color := Color(0, 0, 0, 0)) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var k := UiStyle.label(key, 15, key_color if key_color.a > 0.0 else UiStyle.TEXT, true)
	k.custom_minimum_size = Vector2(190, 0)
	h.add_child(k)
	var t := UiStyle.label(text, 15, UiStyle.TEXT_DIM)
	t.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	v.add_child(h)


# --- 各セクション ---

func _page_intro() -> Control:
	var s := _section("はじめに")
	var v: VBoxContainer = s[1]
	_para(v, "Danmaku は、osu! の譜面(.osz)を「弾幕よけ」に変えて遊ぶゲームです。曲のノーツに合わせて、画面に弾が飛んできます。自機を動かして弾をよけ、曲の最後まで生き残るのが目的です。", UiStyle.TEXT)
	_art(v, "flow")
	_head(v, "ルールは 3 つだけ")
	_callout(v, "① 弾に当たっている間だけ、体力が減る", "体力のゲージが 0 になると、ゲームオーバーです。当たっていなければ、少しずつ回復します。", Color(1.0, 0.45, 0.47))
	_callout(v, "② 弾のすぐそばを通ると、ボーナス(グレイズ)", "当たらないぎりぎりを通るほど、スコアが増えます。危ない場所へ入る勇気が、得点になります。", Color(1.0, 0.85, 0.3))
	_callout(v, "③ 被弾が少ないほど、スコアが高い", "スコアは、被弾するたびに少しずつ下がります。ノーミスでクリアすると、最高ランクの SS です。", Color(0.5, 1.0, 0.7))
	_head(v, "はじめの一曲")
	_numrow(v, 1, "曲を選ぶ", "タイトルの「プレイ」で、曲の一覧が開きます。曲がまだないときは、「曲の追加」のページを見てください。")
	_numrow(v, 2, "難易度(Lv)を選ぶ", "一覧の上(← 側)が易しく、下(→ 側)が難しい譜面です。はじめは、色が青〜緑の Lv から。")
	_numrow(v, 3, "PLAY を押す", "READY のあと、曲が始まります。最初の弾まで長いときは、Space でスキップできます。")
	_numrow(v, 4, "クリアすると、結果が出る", "ランク・スコア・体力の推移のグラフが出ます。ひとりで遊んだ記録は、この PC に残ります。")
	_callout(v, "ヒント: 迷ったら「練習」MOD", "選曲画面で M キー → 「練習」を付けると、体力が 0 になってもゲームオーバーにならず、最後まで試せます(ベーススコア −50%)。", UiStyle.ACCENT)
	_head(v, "難易度(Lv)の見かた")
	_para(v, "Lv は、画面に出る弾の量・弾の速さ・大きさ・曲の長さから、このゲーム独自の方法で計算した値です。本家 osu! の★と同じ目盛りで、MOD を付けると、付けた状態の値に変わります。色でも、おおよそが分かります。")
	_art(v, "lv")
	_head(v, "キアイ")
	_para(v, "譜面のキアイ(盛り上がり)の区間では、テンポに合わせて背景と弾が少し光ります。")
	_head(v, "このアプリについて")
	_para(v, "osu! の譜面データ(.osz)を、弾幕よけゲームに変換して遊ぶ、非公式のファンメイド作品です。osu! および ppy Pty Ltd とは関係がありません(「osu!」は ppy Pty Ltd の商標です)。曲・譜面は同梱していません。権利は、それぞれの制作者にあります。", UiStyle.TEXT_FAINT, 13)
	return s[0]


func _page_hud() -> Control:
	var s := _section("画面の見かた")
	var v: VBoxContainer = s[1]
	_para(v, "プレイ中の画面は、真ん中の盤面(アリーナ)と、その周りの情報でできています。見るのは、次の 7 か所です(絵は、画面の配置を簡単に描いたものです)。", UiStyle.TEXT)
	_art(v, "hud")
	_numrow(v, 1, "体力のゲージ", "弾に当たっている間だけ減ります。0 になるとゲームオーバー。低くなると、画面の縁が赤みを帯びます。")
	_numrow(v, 2, "スコア", "いまの得点です。被弾しているあいだは赤くなります。下の % は、曲の進み具合です。")
	_numrow(v, 3, "GRAZE / DAMAGE", "GRAZE は、グレイズ(かすった弾)の数。DAMAGE は、受けたダメージの合計で、ゲージ満タン = 100% です。回復しても減らず、100% を超えることもあります。")
	_numrow(v, 4, "曲の情報", "曲名・アーティスト・難易度の名前と Lv、付けている MOD が出ます。")
	_numrow(v, 5, "曲の進み具合", "画面の下の細い線です。白く区切られたところは、休憩(BREAK)です。")
	_numrow(v, 6, "危険エリア", "盤面の一部が、色つきの枠と面になります。種類によって、自機が不利にも有利にもなります(「特殊エリア」のページ)。")
	_numrow(v, 7, "自機", "水色の三角形です。当たり判定は、真ん中の白い点だけ。黄色い点線の輪の中を弾の縁が通ると、グレイズです。")
	_callout(v, "マルチプレイでは", "ほかの人の自機が、淡い色で表示されます。協力プレイでは、体力が全員で 1 本です。", UiStyle.TEXT_DIM)
	return s[0]


func _page_controls() -> Control:
	var s := _section("操作")
	var v: VBoxContainer = s[1]
	_para(v, "キーボードでもマウスでも遊べます(標準はマウス)。設定の「操作」で切り替えられます。", UiStyle.TEXT)
	_art(v, "keys")
	_head(v, "プレイ中")
	_row(v, "移動", "キーボード: 矢印キー または WASD。マウス: 動かした分だけ自機が動きます(カーソルは隠れます。感度は設定で変えられます)")
	_row(v, "低速", "Shift(マウスなら右クリックでも可)。ゆっくり細かく動けます。弾の間を縫うときに")
	_row(v, "イントロをスキップ", "Space、または画面下の「スキップ」ボタン。最初のノーツの少し前まで飛ばします(マルチプレイは、全員が押したら、いっせいに飛ばします。ボタンに押した人数が出ます)")
	_row(v, "ポーズ", "Esc。再開 / リトライ / メニューへ と、全体音量・音楽・効果音の調整ができます。↑ ↓ で行を選び、Enter で実行、音量の行は ← → で動かせます。R でリトライ、Q でメニューへ。ひとりで遊ぶとき、ウィンドウのフォーカスが外れると、自動でポーズします")
	_row(v, "再開のしかた", "「再開」のあとは、すぐには動き出しません。自機だけが見えて、クリックまたは移動キー・Space で動き出します(止めた弾は見えません)")
	_row(v, "リトライ", "R を長押し(約 0.6 秒)。すぐに最初からやり直せます(ゲームオーバーの演出中も。マルチプレイ以外)")
	_row(v, "音量", "マウスホイール。回すと「全体 / 音楽 / 効果音」のメーターが出て、全体音量が変わります。メーターをクリックしてから回すか、バーをマウスで動かすと、その音量を変えられます(スクロールできる一覧の上では、Ctrl を押しながら)")
	_head(v, "選曲画面")
	_row(v, "↑ ↓", "曲を選ぶ(難易度順のときは、1 譜面ずつ)")
	_row(v, "← →", "難易度を選ぶ(左が易しく、右が難しい)")
	_row(v, "Enter", "開始(難易度をダブルクリック、または選んでいる難易度をもう一度押しても開始)")
	_row(v, "ドラッグ", "曲・難易度の一覧をスクロール(左ドラッグは、一覧をつかんで動かす。右ドラッグは、スクロールバーのように、下へ動かすと先へ進み、速く動く)")
	_row(v, "M / O", "M: MOD を選ぶ / O: 設定を開く")
	_row(v, "/", "曲を検索する(lazer 風の選曲画面。右上の入力欄でも)。入力中は、Enter・↓ で、表示している先頭の曲を選び、Esc で入力をやめます")
	_row(v, "Esc", "タイトルへ戻る")
	_head(v, "リプレイ")
	_row(v, "見返す", "ひとりで遊んだプレイは、自動で保存されます(新しい 30 件まで)。タイトルの「リプレイ」の一覧、リザルトの「リプレイ」(P)から開きます。「保存」しておくと、古くなっても消えません")
	_row(v, "Space / クリック", "再生 / 停止(プレイ画面のクリックでも)")
	_row(v, "← →", "5 秒 戻る / 進む(Shift で 1 秒、Ctrl で 15 秒)。下の体力グラフをクリック・ドラッグしても、その秒へ飛べます")
	_row(v, "PgUp / PgDn", "前の / 次の被弾の少し前へ(避けそこねた場面を見る)")
	_row(v, "[ ] / , .", "速さを変える(下の「速さ」のスライダーなら、0.25〜8 倍の好きな値に)/ 1 コマずつ戻る・進む")
	_row(v, "T", "自機の軌道(過去 3 秒)の 表示 / 非表示。被弾した場所には赤い × が出ます")
	_row(v, "H / ?", "操作パネルを隠す・出す / 操作の一覧")
	_row(v, "動画出力", "動画に書き出します(最後にリザルト画面つき。ビデオ/Danmaku/。PC に ffmpeg があれば mp4 にもなります)")
	_head(v, "どの画面でも")
	_row(v, "F11", "全画面とウィンドウを切り替える(プレイ中は使えません。ポーズ中は使えます)")
	_row(v, "F3", "FPS の表示を、一時的に切り替える")
	_row(v, "パネルを閉じる", "右上の ✕、パネルの外のクリック、Esc のどれでも(MOD・設定・遊び方・更新・終了の確認)")
	_head(v, "設定")
	_para(v, "操作方式、マウス感度、音量(全体・音楽・効果音)、音と弾のズレの校正(オフセット)、解像度(ウィンドウの大きさ。枠をドラッグして好きな大きさにもできます)、垂直同期、FPS の表示などを変えられます。プレイ中以外は、どの画面でも開けます(タイトルの「設定」、そのほかの画面は右上の「設定」、または左上の歯車。選曲画面は O でも)。「画面」では、UI の見た目(クラシック / lazer 風)や、弾が多いときの目のチカチカを抑える「目に優しい表示」も切り替えられます。")
	return s[0]


func _page_graze() -> Control:
	var s := _section("弾とグレイズ")
	var v: VBoxContainer = s[1]
	_para(v, "このゲームでいちばん大事なのは、「自機の当たり判定は、見た目よりずっと小さい」ことです。弾は、自機の三角形をかすめても当たりません。中心の白い点に触れたときだけ、被弾です。", UiStyle.TEXT)
	_art(v, "arena")
	_head(v, "グレイズ(かすり)")
	_para(v, "弾の縁が、自機の周りの輪(グレイズの範囲)に入ると、グレイズです。同じ弾は 1 回だけ数えます。グレイズが増えるほど、ボーナス点(最大 30,000 点)に近づきます。曲が長く弾が多い譜面ほど、近づくのに多くのグレイズが必要です。")
	_head(v, "よけるコツ")
	_callout(v, "低速(Shift)を使いこなす", "弾の間を抜けるときは、Shift(マウスは右クリック)でゆっくり動きます。通常の半分以下の速さなので、細かい位置合わせができます。", Color(0.42, 0.88, 1.0))
	_callout(v, "予兆の輪を見る", "弾が出る少し前に、予兆の印(輪など)が出ることがあります。どこから、どちら向きに弾が来るかを、先に読めます。", Color(1.0, 0.85, 0.3))
	_callout(v, "発射点のそばは、少しのあいだ安全", "弾が出た直後、発射点の近く(約 100px 以内)にいると、その弾は少しのあいだ当たりません。出た瞬間の弾を、すり抜ける手もあります。", Color(0.5, 1.0, 0.7))
	_callout(v, "休憩(BREAK)は、息継ぎ", "譜面の休憩区間では、得点も回復もありません。周りの弾はなくなり、休憩が終わるまでの残り時間が出ます。", UiStyle.TEXT_DIM)
	return s[0]


func _page_zones() -> Control:
	var s := _section("特殊エリア")
	var v: VBoxContainer = s[1]
	_para(v, "弾幕 v2(初期状態)では、盤面の一部が「特殊エリア」になることがあります。円・半面・帯・流れる帯などの形で、フレーズごとに 1 つ(または 1 組)出ます。エリアの中にいる間だけ、色と名前に応じた効果を受けます。", UiStyle.TEXT)
	_art(v, "zones")
	_head(v, "出かた")
	_art(v, "timeline")
	_para(v, "予告は、2 小節前から、点線の枠が点滅して現れます(最初の弾が出る前には出ません)。発動すると枠が実線になり、白い合図が走ります。エリアの色は上の絵と同じで、受けている間は、左のパネルに「デバフ(試練)/ 恩恵」と名前が出ます。")
	_head(v, "試練・恩恵・対")
	_row(v, "試練", "自機が不利になるエリア。入った分の見返りに、エリアの中のグレイズは 1.5 倍に数えられます", Color(1.0, 0.45, 0.45))
	_row(v, "恩恵", "自機が有利になるエリア。休むのに使ったり、稼ぎに使ったりできます", Color(0.5, 1.0, 0.7))
	_row(v, "対", "盤面を半分に割って、片方が試練・片方が恩恵。安全地帯のない、どちらの代償を払うかを選ぶ形です")
	_para(v, "難易度の★が低いほど恩恵が多く、高いほど対や試練が増えます。どのエリアにも、逃げ込める安全な場所は残してあります(試練のエリアは、動ける範囲の半分以下です)。")
	_head(v, "うまく使うには")
	_callout(v, "稼ぎ(金色の星)", "中でグレイズすると、ボーナスの点が 2 倍になります。さらに、グレイズのたびに、被弾で下がった被ダメージ係数を少しだけ取り戻します(失っているほど、戻る量も大きい)。", GameSim.zone_color("bonus"))
	_callout(v, "癒し(ピンクの十字)", "ゲージが毎秒 5% 回復します。ダメージを受けたあとの、立て直しに。", GameSim.zone_color("heal"))
	_callout(v, "流れ(白い矢印)", "入力に関係なく、矢印の向きへ押されます(自機の移動の約 3 割の強さ)。逆向きに動けば押し返せます。", GameSim.zone_color("flow"))
	_callout(v, "時の急流(赤)/ 時の淀み(紫)", "どちらも、エリアの中の弾の速さだけが変わります(自機には何も効きません)。急流は 1.5 倍、淀みは 0.55 倍。エリアに入る・出るときは、弾の速さがなめらかに変わります。", GameSim.zone_color("haste"))
	_head(v, "弾幕 v1 のとき")
	_para(v, "MOD「弾幕 v1」を付けると、危険エリアは、盤面を 3×3 に分けたマスになります。受ける効果は、鈍足・脆弱・毒・巨大などのデバフです。", UiStyle.TEXT_DIM)
	return s[0]


func _page_score() -> Control:
	var s := _section("ゲージとスコア")
	var v: VBoxContainer = s[1]
	_head(v, "ゲージ")
	_para(v, "弾に当たっているあいだだけ減ります。満タンは約 0.3 秒ぶんの被弾(弾幕 v1 は 0.25 秒)。残りが 20% 以下になると被ダメージが半分になり、当たっていないあいだは、毎秒 1.5% ずつ回復します。")
	_art(v, "gauge")
	_head(v, "スコアのしくみ")
	_para(v, "基本の 1,000,000 点に、グレイズのボーナス(最大 30,000 点)を足し、被ダメージ係数を掛けたものが、最終スコアです。スコアは、弾が発射されるたびに少しずつ積み上がり、クリアで最終スコアになります。ゲームオーバーは 0 点です。")
	_art(v, "eq")
	_callout(v, "被ダメージ係数とは", "受けたダメージの合計が増えるほど、1 から 0 へ向かって下がる数です。ゲージ 1 本ぶん(DAMAGE 100%)を受けると、およそ 0.72 倍になります(長い曲ほど、下がり方はゆるやかです)。回復しても、取り戻せません(稼ぎのエリアだけは、少し戻ります)。", Color(1.0, 0.45, 0.47))
	_head(v, "ランク")
	_para(v, "クリアすると、ランクが決まります。達成率 = 最終スコア ÷ ベーススコアです。MOD の倍率は打ち消した率なので、「練習」や「加速」などでランクが上下することはありません。")
	_art(v, "ranks")
	return s[0]


func _page_mods() -> Control:
	var s := _section("MOD")
	var v: VBoxContainer = s[1]
	_para(v, "プレイ前に付ける修飾です。複数付けると、効果もベーススコアの倍率も掛け算で重なります。難易度選択画面の「MOD」ボタン(M キー)で選びます。難しくする MOD はスコアが増え、「練習」のように易しくする MOD は減ります。", UiStyle.TEXT)
	for m in Mods.ALL:
		var pct := int(round((float(m.get("score_mul", 1.0)) - 1.0) * 100.0))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		head.add_child(UiStyle.label(m.name, 17, m.color, true))
		head.add_child(UiStyle.chip("ベーススコア %+d%%" % pct, m.color))
		v.add_child(head)
		var effects: Array = []
		for p in (m.desc as String).split(" / "):
			if not p.begins_with("ベーススコア"):
				effects.append(p)
		_para(v, "  /  ".join(effects))
	return s[0]


func _page_select() -> Control:
	var s := _section("選曲画面")
	var v: VBoxContainer = s[1]
	_para(v, "曲と難易度を選ぶ画面です(絵は lazer 風の画面。クラシックは、配置が少し違います)。", UiStyle.TEXT)
	_art(v, "select")
	_numrow(v, 1, "検索", "曲名・アーティスト名から探せます(/ キーでも)。")
	_numrow(v, 2, "並び替え", "検索の右の「並び替え」ボタンを押して、曲名 / アーティスト / 追加順 / ランク / 難易度 / 長さから選びます。選んだ並びは覚えています。")
	_numrow(v, 3, "曲の行", "背景は曲の画像。小さな色の札は難易度の色(左が易しい)、右端は長さと、その曲の最高ランクです。")
	_numrow(v, 4, "難易度の一覧", "曲を選ぶと、その下に開きます。押すと選び、選んでいる難易度をもう一度押すと開始です。")
	_numrow(v, 5, "曲の情報と内訳", "平均の弾数・最大の弾数・弾速、イベント数、長さなどが出ます。")
	_numrow(v, 6, "ローカル記録", "選んでいる難易度の上位 5 件(ランク・スコア・付けた MOD・日付)。ひとりでクリアしたプレイだけが、この PC の中に残ります(ゲームオーバーとマルチプレイは残りません。どこにも送りません)。")
	_numrow(v, 7, "下のボタン", "戻る / MOD / ランダム / 設定 / プレイ。")
	_head(v, "並び替えの詳しい説明")
	_row(v, "ランク", "その曲の最高ランクの高い順。記録のない曲は後ろ")
	_row(v, "難易度", "曲ではなく、譜面ごとに 1 行ずつ、Lv の低い順。↑ ↓ で 1 譜面ずつ進み、押すと、その曲のその難易度を選びます")
	_row(v, "長さ", "短い順。まだ長さが分かっていない曲は後ろに置き、裏で調べて、分かった曲から並びに入ります")
	_callout(v, "2 回目から、読み込みが速くなります", "曲を選ぶと、譜面と弾幕の準備に少し時間がかかります。一度作ったものは保存されるので、次からは数倍速く読み込めます。", UiStyle.ACCENT)
	return s[0]


func _page_multi() -> Control:
	var s := _section("マルチプレイ")
	var v: VBoxContainer = s[1]
	_para(v, "サーバーなしで、友達と直接つないで遊びます(最大 4 人)。部屋を立てる人(ホスト)が招待コードを作り、参加する人がそのコードを入力します。", UiStyle.TEXT)
	_art(v, "multi")
	_head(v, "遊び方")
	_numrow(v, 1, "ホスト: 部屋を作る", "タイトルの「マルチプレイ」→「部屋を作る」。出てきた招待コードを友達に伝え、曲・MOD を選びます。")
	_numrow(v, 2, "参加する人: コードを入れる", "「マルチプレイ」→ 招待コードを入力 →「参加する」。曲があれば「準備完了」を押して、ホストの開始を待ちます(モード・曲・MOD が変わると、準備完了は外れます)。")
	_numrow(v, 3, "ホスト: ゲーム開始", "参加者が全員「準備完了」を押したら、「ゲーム開始」が押せます。")
	_row(v, "曲", "全員が同じ曲(.osz)を持っている必要があります。持っていない人には「ダウンロードして取り込む」ボタンが出ます(ボタンを押したときだけ通信します)。自分で入れたい場合は、公式ページを開いて、ダウンロードした .osz をこのアプリで開くか songs フォルダに入れてください")
	_row(v, "MOD", "ホストが選んだものが、全員に共通で掛かります(全員が同じ弾幕になります)")
	_row(v, "版", "全員が同じバージョンのアプリである必要があります")
	_head(v, "モード")
	_row(v, "対戦", "各自が自分の画面で同じ弾幕を避けます。スコアの高い人の勝ち。体力が 0 になってもゲームオーバーにならず、最後まで続けられます。他の人の自機は淡く表示されます", Color(1.0, 0.7, 0.4))
	_row(v, "協力", "全員が同じフィールドで、いっしょに避けます。体力は全員で 1 本を共有し、人数に応じて増えます。体力が 0 になると全員がゲームオーバー、最後まで体力が残ればクリアです", Color(0.5, 1.0, 0.7))
	_head(v, "つながらないとき")
	_para(v, "ホストが部屋を作るとき、ルーターの UPnP で UDP ポートを自動で開けます。UPnP が使えないルーターでは、ルーターの設定で、コードの下に表示されるポート(UDP 24680〜24935 のいずれか)を、ホストの PC へ転送してください。同じ LAN の中なら、そのまま参加できます。")
	_para(v, "プロバイダによっては(IPv4 の共有アドレスなど)、外から直接つなぐことができません。その場合は、Tailscale・ZeroTier などの VPN で同じネットワークに入り、招待コードの代わりに、ホストの VPN の IP アドレス(例: 100.64.0.5)を入力してください。初めて部屋を作るとき、Windows のファイアウォールの確認が出たら、許可してください。", UiStyle.TEXT_DIM)
	return s[0]


func _page_songs() -> Control:
	var s := _section("曲の追加")
	var v: VBoxContainer = s[1]
	_para(v, "曲は .osz(osu! の譜面パッケージ)を追加して増やせます。次のどれでも追加できます。", UiStyle.TEXT)
	_art(v, "songs")
	_row(v, "songs フォルダ", "ゲームの隣の songs フォルダに .osz を入れると、しばらくして画面の下に「曲が追加されました」と出ます(選曲画面の一覧にも加わります)")
	_row(v, "ドラッグ&ドロップ", "選曲画面に .osz をドロップ、または「.osz を開く…」から選ぶ")
	_row(v, "osu! の曲", "設定の「曲」で「osu! の Songs フォルダの曲を使う」を入れると、osu! に入っている曲を、コピーせずにそのまま一覧に加えます(初めては、裏で準備するので少し待ちます)")
	_row(v, ".osz を開く", "エクスプローラーで .osz をこのアプリで開くと、自動で取り込まれ、選曲画面で選ばれます(設定の「その他」で、「プログラムから開く」に追加できます)")
	var btn := Button.new()
	btn.text = "songs フォルダを開く"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(220, 40)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.pressed.connect(_open_songs_dir)
	v.add_child(btn)
	_callout(v, "曲が 1 つもないとき", "タイトルの曲は流れず、選曲画面は空になります。譜面は osu! の公式サイトなどで配布されています(.osz を探してください)。", UiStyle.TEXT_DIM)
	return s[0]


## 曲を入れるフォルダを開く。ゲームの隣に songs を作れなければ、ユーザーデータ内の songs を開く。
func _open_songs_dir() -> void:
	var d := OS.get_executable_path().get_base_dir().path_join("songs")
	if DirAccess.make_dir_recursive_absolute(d) != OK:
		d = ProjectSettings.globalize_path("user://songs")
		DirAccess.make_dir_recursive_absolute(d)
	OS.shell_open(d)
