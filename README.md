# WTFONE

Peer-to-peer video chat. WebRTC + Rust backend.

## Build

```bash
cargo build
```

## Run

```bash
cargo run
```

Server: `http://localhost:3000`


## TEST
```
cd tests
./run_tests.ps1
```

```
npm test
npx playwright show-report
```
## API

**Create room:**
```bash
POST /api/rooms
Content-Type: application/json

{"password": "secret"}
```

Response: `{"room_id": "uuid"}`

**Join room:**
```
WebSocket: ws://localhost:3000/api/rooms/{room_id}/ws

Join message:
{"type": "join", "room_id": "uuid", "password": "secret"}

Server responds:
{"type": "joined", "peer_id": "uuid"}
```

## Messages

**Client → Server:**
- `join`: room_id, password
- `offer`: to (peer_id), sdp
- `answer`: to (peer_id), sdp
- `ice`: to (peer_id), candidate

**Server → Client:**
- `joined`: peer_id
- `peer_joined`: peer_id
- `peer_left`: peer_id
- `offer`: from (peer_id), sdp
- `answer`: from (peer_id), sdp
- `ice`: from (peer_id), candidate
- `error`: message

## Status

- Phase 0-1: Server + static files ✅
- Phase 2: Room creation API ✅
- Phase 3: WebSocket join flow ✅
- Phase 4-10: In progress
```
