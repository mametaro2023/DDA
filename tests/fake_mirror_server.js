// 開発用: 曲のミラーサイトのふりをする手元のサーバー(曲のダウンロード機能の確認用)。
//   node tests/fake_mirror_server.js <ポート> <配る .osz のパス>
//   /d/<id>     … .osz を配る       /bad/<id>  … 404       /html/<id> … HTML(曲ではないもの)を 200 で返す
const http = require('http'), fs = require('fs');
const [port, oszPath] = [process.argv[2] || 8766, process.argv[3]];
const osz = fs.readFileSync(oszPath);
http.createServer((req, res) => {
  if (req.url.startsWith('/d/')) { res.setHeader('Content-Type', 'application/x-osu-beatmap-archive'); res.setHeader('Content-Length', osz.length); res.end(osz); }
  else if (req.url.startsWith('/html/')) { res.setHeader('Content-Type', 'text/html'); res.end('<html>' + 'x'.repeat(4000) + '</html>'); }
  else { res.statusCode = 404; res.end('not found'); }
}).listen(port, '127.0.0.1', () => console.log('listening ' + port));
