# WTFONE API

## REST Endpoints

### Create Room
```
POST /api/rooms
Content-Type: application/json

Request:
{
  "password": "string"
}

Response (201):
{
  "room_id": "uuid"
}
```

### Upload Recording
```
POST /api/rooms/{room_id}/recording
Content-Type: multipart/form-data

Request:
- file: webm video blob

Response (200):
{
  "success": true
}
```

---

## WebSocket

### Connect
```
ws://localhost:3000/api/rooms/{room_id}/ws
```

### Client → Server Messages

**Join Room**
```json
{
  "type": "join",
  "room_id": "uuid",
  "password": "string"
}
```

**Offer (WebRTC)**
```json
{
  "type": "offer",
  "to": "peer_id",
  "sdp": { /* RTCSessionDescription */ }
}
```

**Answer (WebRTC)**
```json
{
  "type": "answer",
  "to": "peer_id",
  "sdp": { /* RTCSessionDescription */ }
}
```

**ICE Candidate**
```json
{
  "type": "ice",
  "to": "peer_id",
  "candidate": { /* RTCIceCandidate */ }
}
```

### Server → Client Messages

**Joined**
```json
{
  "type": "joined",
  "peer_id": "uuid"
}
```

**Peer Joined**
```json
{
  "type": "peer_joined",
  "peer_id": "uuid"
}
```

**Peer Left**
```json
{
  "type": "peer_left",
  "peer_id": "uuid"
}
```

**Offer (Relayed)**
```json
{
  "type": "offer",
  "from": "peer_id",
  "sdp": { /* RTCSessionDescription */ }
}
```

**Answer (Relayed)**
```json
{
  "type": "answer",
  "from": "peer_id",
  "sdp": { /* RTCSessionDescription */ }
}
```

**ICE Candidate (Relayed)**
```json
{
  "type": "ice",
  "from": "peer_id",
  "candidate": { /* RTCIceCandidate */ }
}
```

**Error**
```json
{
  "type": "error",
  "message": "string"
}
```

---

## Error Codes

| Status | Meaning |
|--------|---------|
| 400 | Bad request (invalid JSON, missing fields) |
| 401 | Unauthorized (wrong password) |
| 404 | Room not found |
| 500 | Server error |

---

## Notes

- All UUIDs are v4 format
- Passwords hashed with bcrypt (cost 12)
- WebRTC SDP/ICE objects passed as-is from browser RTCPeerConnection
- WebSocket closes on auth failure or room not found
