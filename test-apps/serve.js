/**
 * ============================================================================
 * Church Digital Platform — Multi-Portal Local Static HTTP Server
 * ============================================================================
 */

import http from 'http';
import fs from 'fs';
import path from 'path';
import url, { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = parseInt(process.env.PORT || process.argv[2] || '3000', 10);
const ROOT_DIR = __dirname;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8'
};

export const server = http.createServer((req, res) => {
  // 1. CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS, PATCH');
  res.setHeader('Access-Control-Allow-Headers', '*');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // 2. Parse URL and resolve file path
  const parsedUrl = new URL(req.url, `http://${req.headers.host || '127.0.0.1'}`);
  let pathname = decodeURIComponent(parsedUrl.pathname);

  // Prevent path traversal attacks
  const safePath = path.normalize(pathname).replace(/^(\.\.[\/\\])+/, '');
  let filePath = path.join(ROOT_DIR, safePath);

  // 3. Directory index resolution
  if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  } else if (!fs.existsSync(filePath) && fs.existsSync(filePath + '.html')) {
    filePath = filePath + '.html';
  }

  // 4. Check existence
  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
          <meta charset="utf-8">
          <title>404 — الصفحة غير موجودة</title>
          <link rel="stylesheet" href="/shared/styles.css">
        </head>
        <body style="display:flex; align-items:center; justify-content:center; height:100vh;">
          <div class="card" style="text-align:center; max-width:480px;">
            <div style="font-size:3rem; margin-bottom:12px;">🔍</div>
            <h2 style="margin-bottom:8px;">الصفحة غير موجودة (404)</h2>
            <p style="margin-bottom:16px;">المسار المطلوب <code>${pathname}</code> غير متوفر في المنظومة.</p>
            <a href="/" class="btn btn-primary">العودة إلى البوابة الرئيسية</a>
          </div>
        </body>
        </html>
      `);
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stats.size,
      'Cache-Control': 'no-cache'
    });

    const stream = fs.createReadStream(filePath);
    stream.pipe(res);
  });
});

if (process.argv[1] === __filename || process.argv[1]?.endsWith('serve.js')) {
  server.listen(PORT, '0.0.0.0', () => {
    console.log('================================================================');
    console.log('  ✝ Church Digital Platform — Test Apps Local HTTP Server');
    console.log('================================================================');
    console.log(`  🌐 Navigation Hub:      http://127.0.0.1:${PORT}/`);
    console.log(`  👤 User Portal:          http://127.0.0.1:${PORT}/user/`);
    console.log(`  ⚙️  Admin Dashboard:      http://127.0.0.1:${PORT}/admin/`);
    console.log(`  ⚡ SuperAdmin Portal:    http://127.0.0.1:${PORT}/superadmin/`);
    console.log('----------------------------------------------------------------');
    console.log('  Press Ctrl+C to stop the server.');
    console.log('================================================================\n');
  });
}

export default server;
