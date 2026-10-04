extends Node
## アプリが 1 つだけ動いているようにして、あとから .osz を開いたときは、動いているほうへ渡す。
## 動いているアプリは、ローカル(127.0.0.1)の UDP ポートで待ち受ける。.osz をつけて起動した新しいアプリは、まずそこへパスを送り、
## 返事(OK)があれば自分は終了する(なければ、自分が待ち受け側になる)。ローカルの同じ PC の中でしか通じない。

signal file_received(path: String)

const PORT := 24660
const MAGIC := "Danmaku-OPEN|"

var _udp: PacketPeerUDP


## 待ち受けを始める。すでに別のアプリが使っていたら false。
func start() -> bool:
	var u := PacketPeerUDP.new()
	if u.bind(PORT, "127.0.0.1") != OK:
		return false
	_udp = u
	return true


func _process(_delta: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		var text := pkt.get_string_from_utf8()
		if not text.begins_with(MAGIC) or text.length() > 1200:
			continue
		var path := text.substr(MAGIC.length())
		if path.to_lower().ends_with(".osz"):
			_udp.set_dest_address(ip, port)
			_udp.put_packet("OK".to_utf8_buffer())
			file_received.emit(path)


func _exit_tree() -> void:
	if _udp != null:
		_udp.close()


## 動いているアプリへ .osz のパスを渡す。受け取ってもらえたら true(timeout_ms 待つ)。
static func forward(path: String, timeout_ms := 700) -> bool:
	var u := PacketPeerUDP.new()
	u.set_dest_address("127.0.0.1", PORT)
	if u.put_packet((MAGIC + path).to_utf8_buffer()) != OK:
		return false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if u.get_available_packet_count() > 0:
			var ok := u.get_packet().get_string_from_utf8() == "OK"
			u.close()
			return ok
		OS.delay_msec(10)
	u.close()
	return false
