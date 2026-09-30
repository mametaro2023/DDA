extends RefCounted
## Windows の「.osz を開くアプリ」に、このアプリを加える(現在のユーザーだけ。レジストリの HKCU\Software\Classes)。
## 既定のアプリは奪わない: 「プログラムから開く」の一覧に DDA が出るようにするだけ(Windows は、既定のアプリをアプリが勝手に
## 変えることを許していない)。既定にするには、Windows の設定(既定のアプリ)で選ぶ。
## 起動コマンドは `"DDA.exe" -- "%1"`(-- のあとの引数がゲームに届く)。

const PROG_ID := "DDA.osz"
const CLASSES := "HKCU\\Software\\Classes\\"


static func supported() -> bool:
	return OS.get_name() == "Windows"


## 登録する(登録済みなら上書き)。成功したら true。ext は ".osz"(テストでは別の拡張子)。
static func register(exe: String, ext := ".osz", prog_id := PROG_ID) -> bool:
	if not supported():
		return false
	exe = exe.replace("/", "\\")
	var cmd := "\"%s\" -- \"%%1\"" % exe
	# 値に引用符を含むので、コマンドの引数では渡せない(引用符がこわれる)。.reg ファイル(UTF-16。パスに日本語があってもよい)を作って取り込む
	var root := "[HKEY_CURRENT_USER\\Software\\Classes\\"
	var lines := PackedStringArray(["Windows Registry Editor Version 5.00", "",
		root + prog_id + "]", "@=" + _q("osu! beatmap (DDA)"), "",
		root + prog_id + "\\DefaultIcon]", "@=" + _q("\"%s\",0" % exe), "",
		root + prog_id + "\\shell\\open\\command]", "@=" + _q(cmd), "",
		root + ext + "\\OpenWithProgids]", "\"%s\"=hex(0):" % prog_id, "",
		root + "Applications\\" + exe.get_file() + "\\shell\\open\\command]", "@=" + _q(cmd), ""])
	var path := OS.get_temp_dir().path_join("dda_assoc_%d.reg" % Time.get_ticks_usec())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(PackedByteArray([0xFF, 0xFE]))   # UTF-16 LE の BOM
	f.store_buffer("\r\n".join(lines).to_utf16_buffer())
	f.close()
	var code := OS.execute("reg", ["import", path.replace("/", "\\")])
	DirAccess.remove_absolute(path)
	return code == 0


## 登録を消す。
static func unregister(exe: String, ext := ".osz", prog_id := PROG_ID) -> void:
	if not supported():
		return
	OS.execute("reg", ["delete", CLASSES + ext + "\\OpenWithProgids", "/v", prog_id, "/f"])
	OS.execute("reg", ["delete", CLASSES + prog_id, "/f"])
	OS.execute("reg", ["delete", CLASSES + "Applications\\" + exe.replace("/", "\\").get_file(), "/f"])


## いま登録されているコマンド(なければ空文字)。
static func registered_command(prog_id := PROG_ID) -> String:
	if not supported():
		return ""
	var out: Array = []
	if OS.execute("reg", ["query", CLASSES + prog_id + "\\shell\\open\\command", "/ve"], out) != 0:
		return ""
	return str(out[0]).strip_edges() if not out.is_empty() else ""


## この exe が、いま登録されているか。
static func is_registered(exe: String, prog_id := PROG_ID) -> bool:
	return registered_command(prog_id).contains(exe.replace("/", "\\"))


## osu!(stable / lazer)の実行ファイル。.osz を開く登録(ProgID)から探し、なければ、標準の場所を見る。見つからなければ空文字。
static func osu_exe() -> String:
	if not supported():
		return ""
	for prog in ["osustable.File.osz", "osu.File.osz", "osu!"]:
		var out: Array = []
		if OS.execute("reg", ["query", "HKCR\\" + prog + "\\shell\\open\\command", "/ve"], out) != 0 or out.is_empty():
			continue
		var text := str(out[0])
		var i := text.find("REG_")
		if i < 0:
			continue
		var exe := parse_command_exe(text.substr(text.find(" ", i)).strip_edges())
		if exe != "" and FileAccess.file_exists(exe):
			return exe
	var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	for p in [local + "/osu!/osu!.exe", local + "/osulazer/current/osu!.exe"]:
		if local != "" and FileAccess.file_exists(p):
			return p.replace("/", "\\")
	return ""


## 「"C:\path\app.exe" "%1"」のような起動コマンドから、exe のパスを取り出す。
static func parse_command_exe(cmd: String) -> String:
	cmd = cmd.strip_edges()
	if cmd.begins_with("\""):
		var j := cmd.find("\"", 1)
		return cmd.substr(1, j - 1) if j > 0 else ""
	var k := cmd.to_lower().find(".exe")
	return cmd.substr(0, k + 4) if k >= 0 else ""


## .osz を osu! で開く(起動していなければ起動する)。開始できたら true。
static func open_in_osu(path: String) -> bool:
	var exe := osu_exe()
	if exe == "":
		return false
	return OS.create_process(exe, [path.replace("/", "\\")]) > 0


## Windows の「既定のアプリ」の設定を開く。
static func open_default_apps() -> void:
	OS.shell_open("ms-settings:defaultapps")


## .reg ファイルの文字列値(バックスラッシュと引用符をエスケープして、引用符で囲む)。
static func _q(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
