#!/usr/bin/env node
// proxy.js - Minimal reverse proxy for DeepSeek Harness (dsh).
// dsh binds to 127.0.0.1 only (it refuses 0.0.0.0 for safety). This proxy
// listens on 0.0.0.0 so the UI is reachable from the LAN.
//
// Two dsh security mechanisms must be satisfied for /api calls to work:
//  1. The browser-trust fence requires Origin.host === Host.host exactly, and
//     privileged RPCs additionally require a loopback Host authority. So every
//     client-supplied authority header is rewritten to the internal target.
//  2. crypto.randomUUID() only exists in browser "secure contexts", so this
//     proxy serves HTTPS (plain HTTP on a LAN IP is not a secure context).
// Handles both HTTP and WebSocket upgrades.

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const LISTEN_HOST = '0.0.0.0';
const LISTEN_PORT = Number(process.env.PROXY_PORT || 3080);
const TARGET_HOST = '127.0.0.1';
const TARGET_PORT = Number(process.env.DSH_PORT || 3081);
const TARGET_AUTHORITY = `${TARGET_HOST}:${TARGET_PORT}`;

function trustedHeaders(headers) {
  return {
    ...headers,
    host: TARGET_AUTHORITY,
    origin: `http://${TARGET_AUTHORITY}`,
    referer: `http://${TARGET_AUTHORITY}/`,
  };
}

const CERT_DIR = path.join(__dirname, 'cert');
const server = https.createServer(
  {
    key: fs.readFileSync(path.join(CERT_DIR, 'key.pem')),
    cert: fs.readFileSync(path.join(CERT_DIR, 'cert.pem')),
  },
  (req, res) => {
    const options = {
      host: TARGET_HOST,
      port: TARGET_PORT,
      method: req.method,
      path: req.url,
      headers: {
        ...trustedHeaders(req.headers),
        'x-forwarded-for': req.socket.remoteAddress || '',
        'x-forwarded-host': req.headers.host || '',
      },
    };
    const proxyReq = http.request(options, (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res);
    });
    proxyReq.on('error', (e) => {
      if (!res.headersSent) res.writeHead(502);
      res.end('Proxy error: ' + e.message);
    });
    req.pipe(proxyReq);
  }
);

server.on('upgrade', (req, clientSocket, head) => {
  const options = {
    host: TARGET_HOST,
    port: TARGET_PORT,
    method: req.method,
    path: req.url,
    headers: trustedHeaders(req.headers),
  };
  const proxyReq = http.request(options);
  proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
    clientSocket.write(
      `HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage}\r\n` +
        Object.entries(proxyRes.headers)
          .map(([k, v]) => `${k}: ${v}`)
          .join('\r\n') +
        '\r\n\r\n'
    );
    if (proxyHead && proxyHead.length) proxySocket.unshift(proxyHead);
    if (head && head.length) clientSocket.unshift(head);
    proxySocket.pipe(clientSocket);
    clientSocket.pipe(proxySocket);
    proxySocket.on('error', () => clientSocket.destroy());
    clientSocket.on('error', () => proxySocket.destroy());
  });
  proxyReq.on('error', () => clientSocket.destroy());
  proxyReq.end();
});

server.listen(LISTEN_PORT, LISTEN_HOST, () => {
  console.log(
    `[proxy] listening on ${LISTEN_HOST}:${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}`
  );
});
