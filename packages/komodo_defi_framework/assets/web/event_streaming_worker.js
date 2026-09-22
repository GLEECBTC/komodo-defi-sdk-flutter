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

// Counts non-UI ports - the ports KDF's own WASM event task owns, since only
// UI clients ever send a control message.
//
// KNOWN GAP: a successful `postMessage` is not proof of liveness. A port whose
// peer has gone away is disentangled, not broken, so `post()` returns true for
// it just the same, and a KDF port is only ever removed from `connections` if
// it throws. KDF never speaks this control protocol, so it never sends
// `disconnect` either. A KDF instance that stops while the page and this
// worker stay alive therefore leaves a port behind that still counts here, and
// a `ready` asked in the gap before the replacement KDF connects is answered
// yes too early.
//
// The obvious hardening is unavailable: no MessagePort API distinguishes a
// dead peer from a silent one, and KDF will not answer an acknowledgment or
// renew a lease. Narrowing this needs a signal from the Dart side at KDF
// shutdown, marking the ports of the outgoing instance stale. Note that the
// naive alternatives are worse than the gap: requiring a port to have sent
// something reinstates a deadlock, because no KDF event arrives before
// `stream::enable`, which itself waits on this readiness answer; and treating
// an older non-UI port as stale when a newer one connects breaks the
// two-tab case, where one SharedWorker is shared by two live KDF instances.
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
          // KDF's WASM event task owns another port on this worker, so a
          // non-UI peer standing here means client 0 was created - without
          // waiting for the first application event, which itself requires
          // stream::enable. See livePeerCount for what this does and does not
          // establish.
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
