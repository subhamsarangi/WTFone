# Phase 5 Tests: WebRTC Client Implementation

Two test suites for Phase 5:

## 1. PowerShell Tests (Signaling + API)
**File:** `test_webrtc_setup.ps1`

Tests server-side signaling and API without browser automation:
- HTML serves with video elements
- WebRTC functions present
- STUN server configured
- WebSocket + signaling flow
- Offer/Answer relay
- Control buttons

**Run:**
```powershell
# Start server first
cargo run

# In another terminal
.\tests\phase5\test_webrtc_setup.ps1
```

**Result:** All 6 tests pass ✓

---

## 2. Playwright Tests (Browser Automation)
**File:** `test_webrtc_browser.js`

Tests actual browser behavior and UI:
- HTML loads with video elements
- Room creation API
- Two-peer join flow (simulated)
- Console logging
- Status messages
- WebSocket connection attempt
- Control button state
- CSS/styling applied
- JavaScript functions exist
- STUN config in page
- Error handling

**Setup:**
```bash
# Install Node.js if not present
# Then install Playwright
npm install

# Or use npx directly (auto-installs)
npx playwright install
```

**Run:**
```bash
# Start server first
cargo run

# In another terminal
npm run test:phase5

# Or with UI
npm run test:ui

# Or debug mode
npm run test:debug
```

**Browsers tested:** Chromium, Firefox

---

## Notes

- **PowerShell tests:** Fast, no browser needed, tests signaling protocol
- **Playwright tests:** Slower, requires browser, tests UI/UX
- **Camera/Mic:** Headless browsers can't access camera, so full WebRTC video test requires manual browser testing
- **Manual testing:** Open two browser tabs, join same room, verify video/audio works

---

## Full Manual Test (Required for Video/Audio)

1. Start server: `cargo run`
2. Open `http://localhost:3000` in two browser tabs
3. Tab 1: Enter password, click "Create Room"
4. Tab 2: Copy room ID from Tab 1, enter password, click "Join Room"
5. Grant camera/mic permissions when prompted
6. Verify: See each other's video streams, audio works both ways
7. Test controls: Mute audio/video, start/stop recording
8. Click "Leave Room" to disconnect

---

## CI/CD Integration

For GitHub Actions or similar:

```yaml
- name: Run Playwright tests
  run: npm run test:phase5
  
- name: Upload test results
  if: always()
  uses: actions/upload-artifact@v3
  with:
    name: playwright-report
    path: playwright-report/
```
