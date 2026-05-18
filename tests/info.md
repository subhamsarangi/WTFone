PS scripts test full system end-to-end:

- Start server
- Connect WebSocket
- Send messages
- Verify responses

---

## Commands
to run Phase 6 tests only:

**Both together:**
```bash
.\tests\phase6\test_recording_api.ps1 && npx playwright test tests/phase6/test_recording_upload.js
```

**With verbose output:**
```bash
npx playwright test tests/phase6/test_recording_upload.js --reporter=list
```

**Single test only:**
```bash
npx playwright test tests/phase6/test_recording_upload.js -g "Recording button exists"
```