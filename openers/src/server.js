// Red Doors opener — HTTP surface (ClusterIP only; NetworkPolicy admits the API).
//   POST /knock   perform this deployment's door method end to end
//   GET  /health  liveness/readiness + what this pod can (and cannot) present
import http from 'node:http';
import { knock, health, DOOR_ID } from './doors.js';

const PORT = Number(process.env.PORT ?? 8080);

function send(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(json) });
  res.end(json);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.setEncoding('utf8');
    req.on('data', (c) => {
      raw += c;
      if (raw.length > 64 * 1024) req.destroy(new Error('body too large'));
    });
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error('invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'POST' && req.url === '/knock') {
      const input = await readBody(req);
      const result = await knock(input);
      // never log released values — only the outcome
      console.log(JSON.stringify({ at: new Date().toISOString(), door: result.door, as: DOOR_ID, outcome: result.outcome }));
      return send(res, 200, result);
    }
    if (req.method === 'GET' && req.url === '/health') {
      const h = health();
      return send(res, h.status === 'ok' ? 200 : 503, h);
    }
    send(res, 404, { error: 'not found' });
  } catch (err) {
    send(res, 400, { error: err.message });
  }
});

server.listen(PORT, () => console.log(`red-doors opener ${DOOR_ID} listening on :${PORT}`));
for (const sig of ['SIGTERM', 'SIGINT']) process.on(sig, () => server.close(() => process.exit(0)));
