// SharedWorker script that forwards KDF messages to all connected ports and
// exposes a small control protocol for UI-side readiness/health checks.
/* eslint-disable no-restricted-globals */

const controlKey = '__kdf_event_stream_control';
const connections = new Set();
const uiConnections = new Set();

function post(port, data) {
  try {
    port.postMessage(data);
    return true;
  } catch (_) {
    connections.delete(port);
    uiConnections.delete(port);
    return false;
  }
}

function livePeerCount(source) {
  let count = 0;
  for (const port of Array.from(connections)) {
    if (port === source || uiConnections.has(port)) continue;
    if (post(port, { [controlKey]: 'probe' })) count += 1;
  }
  return count;
}

onconnect = function (event) {
  const port = event.ports[0];
  connections.add(port);
  port.start();

  port.onmessage = function (messageEvent) {
    try {
      const data = messageEvent.data;
      if (data && typeof data === 'object' && data[controlKey]) {
        uiConnections.add(port);
        if (data[controlKey] === 'ping') {
          post(port, { [controlKey]: 'pong', nonce: data.nonce });
        } else if (data[controlKey] === 'ready') {
          // KDF's WASM event task owns another port on this worker. Seeing a
          // live peer proves client 0 was created without waiting for the first
          // application event (which itself requires stream::enable).
          post(port, {
            [controlKey]: 'ready',
            ready: livePeerCount(port) > 0,
          });
        } else if (data[controlKey] === 'disconnect') {
          connections.delete(port);
          uiConnections.delete(port);
          port.close();
        }
        return;
      }

      for (const connection of Array.from(connections)) {
        if (connection !== port) post(connection, data);
      }
    } catch (_) {}
  };
};
