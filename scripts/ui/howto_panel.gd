extends Control
## 遊び方パネル(タイトル画面の上に重ねる)。ゲーム中の画面には説明文を出さない代わりに、説明はすべてここに集める。
## 左に見出し(はじめに / 操作 / ゲージとスコア / MOD / マルチプレイ / 曲の追加)、右に内容。右上の ✕ / 閉じる / パネルの外 / Esc で閉じる。

signal closed

const Mods = preload("res://scripts/mods.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiSfx = preload("res://scripts/ui/ui_sfx.gd")

const SECTIONS := ["はじめに", "操作", "ゲージとスコア", "MOD", "マルチプレイ", "曲の追加"]

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
	_pages = [_page_intro(), _page_controls(), _page_score(), _page_mods(), _page_multi(), _page_songs()]
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


## 「キー … 内容」の 1 行。
func _row(v: VBoxContainer, key: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var k := UiStyle.label(key, 15, UiStyle.TEXT, true)
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
	_para(v, "曲の譜面(.osz)のノーツに合わせて、画面に弾が発射されます。自機を動かして弾をよけ、曲の最後まで生き残るのが目的です。", UiStyle.TEXT)
	_para(v, "弾に当たっているあいだだけゲージが減り、ゲージが 0 になるとゲームオーバーです。弾のすぐそばを通り抜ける(グレイズ)と、ボーナス点が入ります。盤面の一部が、危険エリアになることがあります(薄い枠で予告 → 色と名前つきで発動)。予告は 2 小節前から、点線の枠が点滅して現れます(最初の弾が出る前には出ません)。弾幕 v2(初期状態)の危険エリアは「特殊エリア」です: 円・半面・帯・流れる帯などの形で、フレーズごとに 1 つ(または 1 組)出ます。自機が不利になる試練(鈍足・脆弱・毒・流れ・時の急流)のほかに、有利になる恩恵(癒し・精密・稼ぎ)と、エリアの中の弾が遅くなる時の淀みがあります。流れは自機を一定の向きへ押し、時の急流はエリアの中の弾を速くします(弾の速さは、エリアを出たあと、ゆっくり元に戻ります)。効果が効いているあいだは、自機の周りと、速さが変わっている弾に、種類ごとの演出が出ます。試練の中でグレイズすると、ボーナス点が少し増えます。MOD「弾幕 v1」(旧い弾幕)では、盤面が 3×3 の 9 マスに分かれ、小節ごとにいくつかのマスが危険エリアになって、入っている間そのマスのデバフ(鈍足・脆弱・毒・巨大)を受けます。")
	_head(v, "難易度(Lv)")
	_para(v, "Lv は、画面に出る弾の量・弾の速さ・大きさ・曲の長さから、このゲーム独自の方法で計算した値です。本家 osu! の★と同じ目盛りで、MOD を付けると、付けた状態の値に変わります。")
	_head(v, "キアイ")
	_para(v, "譜面のキアイ(盛り上がり)の区間では、テンポに合わせて背景と弾が少し光ります。")
	_head(v, "このアプリについて")
	_para(v, "osu! の譜面データ(.osz)を、弾幕よけゲームに変換して遊ぶ、非公式のファンメイド作品です。osu! および ppy Pty Ltd とは関係がありません(「osu!」は ppy Pty Ltd の商標です)。曲・譜面は同梱していません。権利は、それぞれの制作者にあります。")
	return s[0]


func _page_controls() -> Control:
	var s := _section("操作")
	var v: VBoxContainer = s[1]
	_head(v, "プレイ中")
	_row(v, "移動(キーボード)", "矢印キー または WASD")
	_row(v, "移動(マウス)", "マウスを動かす(カーソルは隠れて、動いた分だけ自機が動きます)")
	_row(v, "低速", "Shift(マウスなら右クリックでも可)。ゆっくり細かく動けます")
	_row(v, "イントロをスキップ", "Space、または画面下の「スキップ」ボタン。最初のノーツの少し前まで飛ばします(マルチプレイは、全員が押したら、いっせいに飛ばします。ボタンに押した人数が出ます)")
	_row(v, "ポーズ", "Esc。再開 / リトライ / メニューへ と、全体音量・音楽・効果音の調整ができます(マルチプレイでは、ゲームは止まらず、退出と音量の調整ができます)。マウスで押すほか、↑ ↓ で行を選び、Enter で実行、音量の行は ← → で動かせます。R でリトライ、Q でメニューへ")
	_row(v, "リトライ", "R を長押し(約 0.6 秒)。すぐに最初からやり直せます(ゲームオーバーの演出中も。マルチプレイ以外)")
	_row(v, "音量", "マウスホイール。回すと「全体 / 音楽 / 効果音」のメーターが出て、全体音量が変わります。メーターをクリックしてから回すか、バーをマウスで動かすと、その音量を変えられます(スクロールできる一覧の上では、Ctrl を押しながら)")
	_head(v, "選曲画面")
	_row(v, "↑ ↓", "曲を選ぶ")
	_row(v, "← →", "難易度を選ぶ(左が易しく、右が難しい)")
	_row(v, "Enter", "開始(難易度をダブルクリック、または選んでいる難易度をもう一度押しても開始)")
	_row(v, "ドラッグ", "曲・難易度の一覧をスクロール(左ドラッグはふつう、右ドラッグは速い)")
	_row(v, "M", "MOD を選ぶ")
	_row(v, "O", "設定を開く")
	_row(v, "/", "曲を検索する(lazer 風の選曲画面。右上の入力欄でも)。入力中は、Enter・↓ で、表示している先頭の曲を選び、Esc で入力をやめます")
	_row(v, "Esc", "タイトルへ戻る")
	_head(v, "リプレイ")
	_row(v, "見返す", "ひとりで遊んだプレイは、自動で保存されます(新しい 30 件まで)。タイトルの「リプレイ」の一覧、リザルトの「リプレイ」(P)から開きます。「保存」しておくと、古くなっても消えません")
	_row(v, "Space / クリック", "再生 / 停止(プレイ画面のクリックでも)")
	_row(v, "← →", "5 秒 戻る / 進む(Shift で 1 秒、Ctrl で 15 秒)。下の体力グラフをクリック・ドラッグしても、その秒へ飛べます")
	_row(v, "PgUp / PgDn", "前の / 次の被弾の少し前へ(避けそこねた場面を見る)")
	_row(v, "[ ] / , .", "速さを変える(0.25〜8 倍)/ 1 コマずつ戻る・進む")
	_row(v, "I / O / X", "区間の 始点 / 終点 / 解除。区間は繰り返し再生され、動画もその区間だけ書き出せます(グラフを Shift を押しながらドラッグしても選べます)")
	_row(v, "T / Y", "自機の軌道の 切り替え(切 → 過去 → 過去+未来)/ 長さ。被弾した場所には赤い × が出ます")
	_row(v, "H / ?", "操作パネルを隠す・出す / 操作の一覧")
	_row(v, "動画出力", "動画に書き出します(ビデオ/Danmaku/。PC に ffmpeg があれば mp4 にもなります)")
	_head(v, "どの画面でも")
	_row(v, "F11", "全画面とウィンドウを切り替える(プレイ中は使えません。ポーズ中は使えます)")
	_row(v, "F3", "FPS の表示を、一時的に切り替える")
	_row(v, "パネルを閉じる", "右上の ✕、パネルの外のクリック、Esc のどれでも(MOD・設定・遊び方・更新・終了の確認)")
	_head(v, "設定")
	_para(v, "操作方式(標準はマウス)、マウス感度、音量(全体・音楽・効果音)、音と弾のズレの校正(オフセット)、解像度(ウィンドウの大きさ。枠をドラッグして好きな大きさにもできます)、垂直同期、FPS の表示を変えられます。プレイ中以外は、どの画面でも開けます(タイトルの「設定」、そのほかの画面は右上の「設定」、または左上の歯車。選曲画面は O でも)。「画面」では、UI の見た目(クラシック / lazer 風)も切り替えられます。")
	return s[0]


func _page_score() -> Control:
	var s := _section("ゲージとスコア")
	var v: VBoxContainer = s[1]
	_head(v, "ゲージ")
	_para(v, "弾に当たっているあいだだけ減ります。満タンは 250 ミリ秒ぶんの被弾で、残りが 20% 以下になると被ダメージは半分になります。当たっていないときは、少しずつ自然に回復します。")
	_head(v, "休憩(BREAK)")
	_para(v, "譜面の休憩区間です。得点も回復もありません。自機の周りの弾がなくなると、弾が消えて、休憩が終わるまでの残り時間が表示されます。")
	_head(v, "スコア")
	_para(v, "基本の 1,000,000 点に、グレイズのボーナス(最大 30,000 点)を足し、被ダメージ係数を掛けたものが最終スコアです。被弾するほど係数が下がり、ゲームオーバーは 0 点です。スコアは、弾が発射されるたびに少しずつ積み上がり、クリアで最終スコアになります。")
	_head(v, "ランク")
	_row(v, "SS", "ノーミス(被弾 0 回)でクリア")
	_row(v, "S / A / B / C / D / F", "被弾の少なさに応じて決まります(S が最高、F が最低)。MOD の倍率には影響されません")
	return s[0]


func _page_mods() -> Control:
	var s := _section("MOD")
	var v: VBoxContainer = s[1]
	_para(v, "プレイ前に付ける修飾です。複数付けると、効果もベーススコアの倍率も掛け算で重なります。難易度選択画面の「MOD」ボタン(M キー)で選びます。")
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


func _page_multi() -> Control:
	var s := _section("マルチプレイ")
	var v: VBoxContainer = s[1]
	_para(v, "サーバーなしで、友達と直接つないで遊びます(最大 4 人)。部屋を立てる人(ホスト)が招待コードを作り、参加する人がそのコードを入力します。", UiStyle.TEXT)
	_head(v, "遊び方")
	_row(v, "ホスト", "タイトルの「マルチプレイ」→「部屋を作る」。出てきた招待コードを友達に伝え、曲・MOD を選びます。参加者が全員「準備完了」を押したら「ゲーム開始」が押せます")
	_row(v, "参加する人", "「マルチプレイ」→ 招待コードを入力 →「参加する」。曲があれば「準備完了」を押して、ホストの開始を待ちます(モード・曲・MOD が変わると、準備完了は外れます)")
	_row(v, "曲", "全員が同じ曲(.osz)を持っている必要があります。持っていない人には「ダウンロードして取り込む」ボタンが出ます(ボタンを押したときだけ通信します)。自分で入れたい場合は、公式ページを開いて、ダウンロードした .osz をこのアプリで開くか songs フォルダに入れてください")
	_row(v, "MOD", "ホストが選んだものが、全員に共通で掛かります(全員が同じ弾幕になります)")
	_head(v, "モード")
	_row(v, "対戦", "各自が自分の画面で同じ弾幕を避けます。スコアの高い人の勝ち。体力が 0 になってもゲームオーバーにならず、最後まで続けられます。他の人の自機は淡く表示されます")
	_row(v, "協力", "全員が同じフィールドで、いっしょに避けます。体力は全員で 1 本を共有し、人数に応じて増えます。体力が 0 になると全員がゲームオーバー、最後まで体力が残ればクリアです")
	_head(v, "つながらないとき")
	_para(v, "ホストが部屋を作るとき、ルーターの UPnP で UDP ポートを自動で開けます。UPnP が使えないルーターでは、ルーターの設定で、コードの下に表示されるポート(UDP 24680〜24935 のいずれか)を、ホストの PC へ転送してください。同じ LAN の中なら、そのまま参加できます。")
	_para(v, "プロバイダによっては(IPv4 の共有アドレスなど)、外から直接つなぐことができません。その場合は、Tailscale・ZeroTier などの VPN で同じネットワークに入り、招待コードの代わりに、ホストの VPN の IP アドレス(例: 100.64.0.5)を入力してください。初めて部屋を作るとき、Windows のファイアウォールの確認が出たら、許可してください。", UiStyle.TEXT_DIM)
	return s[0]


func _page_songs() -> Control:
	var s := _section("曲の追加")
	var v: VBoxContainer = s[1]
	_para(v, "曲は .osz(osu! の譜面パッケージ)を追加して増やせます。次のどちらでも追加できます。", UiStyle.TEXT)
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
	_head(v, "検索・並び替え・記録(lazer 風の選曲画面)")
	_para(v, "右上の入力欄で、曲名・アーティスト名から曲を探せます。並び替えは「曲名 / アーティスト / 追加順 / ランク / 難易度 / 長さ」(長さは短い順。ランクは、その曲の最高ランクの高い順。記録のない曲は後ろ。難易度は、曲ではなく譜面ごとに 1 行ずつ、Lv の低い順。選んだ並び順は覚えておきます)。曲の行の右には、その曲の最高ランクが出ます。曲の行の小さな色の札は、難易度ごとの色(左が易しい)です。曲を選ぶと、その下に難易度の一覧が開きます。")
	_para(v, "左下の「ローカル記録」には、選んでいる難易度の上位 5 件(ランク・スコア・付けた MOD・日付)が出ます。記録は、ひとりでクリアしたプレイだけが、この PC の中に残ります(ゲームオーバーとマルチプレイは残りません。どこにも送りません)。")
	_para(v, "曲が 1 つもないと、タイトルの曲は流れず、選曲画面は空になります。", UiStyle.TEXT_FAINT, 13)
	return s[0]


## 曲を入れるフォルダを開く。ゲームの隣に songs を作れなければ、ユーザーデータ内の songs を開く。
func _open_songs_dir() -> void:
	var d := OS.get_executable_path().get_base_dir().path_join("songs")
	if DirAccess.make_dir_recursive_absolute(d) != OK:
		d = ProjectSettings.globalize_path("user://songs")
		DirAccess.make_dir_recursive_absolute(d)
	OS.shell_open(d)
