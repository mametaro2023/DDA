extends RefCounted
## 招待コード。サーバーを持たない P2P なので、コードそのものが「ホストへの行き先」になる。
##   グローバル IP(4 バイト)+ LAN の IP(4 バイト)+ ポート(BASE_PORT からの差 1 バイト)+ チェック(CRC-8、1 バイト)
##   = 10 バイト = 80 ビット → 32 進の 16 文字(4 文字ずつ区切って表示。例: K7QM-2D9X-H4WB-0ZPA)
## 32 進の文字は、読み間違えやすいもの(I / L / O / U)を除く。入力では小文字・区切り(- 空白)を無視し、O → 0、I・L → 1 と読み替える。
## IP アドレス(と :ポート)を直接入力しても行き先にできる(VPN や、手動でポート開放したとき)。

const BASE_PORT := 24680
const PORT_SPAN := 256
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const LEN := 16


## コードを作る。IP は "a.b.c.d"(なければ空文字 = 0.0.0.0)。ポートが範囲外なら空文字を返す。
static func encode(public_ip: String, local_ip: String, port: int) -> String:
	if port < BASE_PORT or port >= BASE_PORT + PORT_SPAN:
		return ""
	var bytes := PackedByteArray()
	bytes.append_array(_ip_bytes(public_ip))
	bytes.append_array(_ip_bytes(local_ip))
	bytes.append(port - BASE_PORT)
	bytes.append(_crc8(bytes))
	var out := ""
	var acc := 0
	var nbits := 0
	for b in bytes:
		acc = (acc << 8) | b
		nbits += 8
		while nbits >= 5:
			nbits -= 5
			out += ALPHABET[(acc >> nbits) & 31]
		acc &= (1 << nbits) - 1
	return "-".join([out.substr(0, 4), out.substr(4, 4), out.substr(8, 4), out.substr(12, 4)])


## コードを読む。{ok, public, local, port}。文字数・使えない文字・チェックが合わなければ ok=false。
static func decode(text: String) -> Dictionary:
	var s := ""
	for ch in text.to_upper():
		if ch == "-" or ch == " " or ch == "\t" or ch == "　":
			continue
		match ch:
			"O":
				ch = "0"
			"I", "L":
				ch = "1"
		s += ch
	if s.length() != LEN:
		return {"ok": false}
	var bytes := PackedByteArray()
	var acc := 0
	var nbits := 0
	for ch in s:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {"ok": false}
		acc = (acc << 5) | v
		nbits += 5
		if nbits >= 8:
			nbits -= 8
			bytes.append((acc >> nbits) & 255)
			acc &= (1 << nbits) - 1
	if bytes.size() != 10:
		return {"ok": false}
	var body := bytes.slice(0, 9)
	if _crc8(body) != bytes[9]:
		return {"ok": false}
	return {"ok": true, "public": _ip_text(bytes, 0), "local": _ip_text(bytes, 4), "port": BASE_PORT + bytes[8]}


## "a.b.c.d" または "a.b.c.d:ポート"(ポート省略時は BASE_PORT)。{ok, host, port}。
static func parse_address(text: String) -> Dictionary:
	var s := text.strip_edges()
	var port := BASE_PORT
	var host := s
	var colon := s.rfind(":")
	if colon >= 0:
		host = s.substr(0, colon)
		var ps := s.substr(colon + 1)
		if not ps.is_valid_int():
			return {"ok": false}
		port = int(ps)
	if not is_ipv4(host) or port < 1024 or port > 65535:
		return {"ok": false}
	return {"ok": true, "host": host, "port": port}


static func is_ipv4(s: String) -> bool:
	var parts := s.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if not p.is_valid_int() or p.length() > 3 or int(p) < 0 or int(p) > 255:
			return false
	return true


## プライベート(LAN)アドレスか(10.x / 172.16-31.x / 192.168.x)。
static func is_private(ip: String) -> bool:
	if not is_ipv4(ip):
		return false
	var p := ip.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)


## グローバルに到達できないアドレスか(プライベート・CGNAT の 100.64/10・ループバック・リンクローカル・0.0.0.0)。
static func is_non_routable(ip: String) -> bool:
	if not is_ipv4(ip):
		return true
	var p := ip.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return is_private(ip) or a == 0 or a == 127 or (a == 100 and b >= 64 and b <= 127) or (a == 169 and b == 254)


static func _ip_bytes(ip: String) -> PackedByteArray:
	var out := PackedByteArray([0, 0, 0, 0])
	if is_ipv4(ip):
		var p := ip.split(".")
		for i in range(4):
			out[i] = int(p[i])
	return out


static func _ip_text(bytes: PackedByteArray, o: int) -> String:
	if bytes[o] == 0 and bytes[o + 1] == 0 and bytes[o + 2] == 0 and bytes[o + 3] == 0:
		return ""
	return "%d.%d.%d.%d" % [bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]]


static func _crc8(bytes: PackedByteArray) -> int:
	var crc := 0
	for b in bytes:
		crc ^= b
		for _i in range(8):
			crc = ((crc << 1) ^ 0x07) & 255 if (crc & 0x80) != 0 else (crc << 1) & 255
	return crc
