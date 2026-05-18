# WTFONE

Peer-to-peer video chat. Rust backend + WebRTC client.

## Quick Start

```bash
cargo build
cargo run
# http://localhost:3000
```

## HTTPS (Local Dev)

WebRTC requires HTTPS for camera/mic access (except localhost). For HTTPS testing:

```bash
mkcert localhost 127.0.0.1 ::1 192.168.29.76
# Creates: localhost+2.pem, localhost+2-key.pem
```

For production: use reverse proxy (nginx/cloudflared) or add tokio-rustls to main.rs

## Testing

```bash
cargo test
cd tests
powershell -ExecutionPolicy Bypass -File .\run_tests.ps1
npm test && npx playwright show-report
```

## Architecture

Browser (WebRTC) ←→ WebSocket ←→ Axum Server (signaling relay)

## Key Files

- `src/main.rs` - Server, routes
- `src/rooms.rs` - Room management
- `src/signaling.rs` - WebSocket handler
- `static/index.html` - Client UI + WebRTC
- `API.md` - Endpoint docs

## Deployment

Options: nginx, cloudflared, tokio-rustls.

## Progress

### Completed ✅

- Phase 0: Bootstrap
- Phase 0.5: Dev tooling (rust-analyzer, mkcert)
- Phase 1: Server + static files
- Phase 2: Room creation API
- Phase 3: WebSocket join flow
- Phase 4: WebRTC signaling relay
- Phase 5: WebRTC client (video, audio, recording UI)
- Phase 5.5: Branding (favicon, logo, meta tags)

### In Progress

- Phase 6: Recording upload
- Phase 7: UI polish
- Phase 8: Error handling
- Phase 9: Production readiness
- Phase 10: Future enhancements (OAuth, TURN, chat, screen share, etc.)
