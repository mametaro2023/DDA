// 開発用: GitHub のリリース API のふりをする手元のサーバー(アプリ内アップデートの確認用)。
//   node tests/fake_release_server.js <ポート> <zip のパス> [bad]   … bad をつけると、ハッシュが合わない zip を配る
const http = require('http'), fs = require('fs'), crypto = require('crypto');
const [port, zipPath, mode] = [process.argv[2] || 8765, process.argv[3], process.argv[4]];
const zip = fs.readFileSync(zipPath);
let digest = crypto.createHash('sha256').update(zip).digest('hex');
if (mode === 'bad') digest = 'deadbeef' + digest.slice(8);
const base = `http://127.0.0.1:${port}`;
const releases = [
  { tag_name: 'v9.9.9-beta', draft: false, prerelease: true, html_url: base + '/page', body: '## テスト用のリリース\n- 新機能 A\n- **修正** B',
    assets: [{ name: 'DDA_beta_v9.9.9.zip', size: zip.length, browser_download_url: base + '/asset.zip', digest: 'sha256:' + digest }] },
  { tag_name: 'v0.2.0-beta', draft: false, prerelease: true, html_url: base + '/old', body: 'old', assets: [{ name: 'DDA_beta_v0.2.0.zip', size: 1, browser_download_url: base + '/old.zip' }] },
  { tag_name: 'v10.0.0', draft: true, prerelease: false, html_url: base + '/draft', body: 'draft (無視される)', assets: [{ name: 'x.zip', size: 1, browser_download_url: base + '/x.zip' }] },
];
http.createServer((req, res) => {
  if (req.url.startsWith('/releases')) { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(releases)); }
  else if (req.url === '/asset.zip') { res.setHeader('Content-Type', 'application/zip'); res.setHeader('Content-Length', zip.length); res.end(zip); }
  else { res.statusCode = 404; res.end('not found'); }
}).listen(port, '127.0.0.1', () => console.log('listening ' + port));
