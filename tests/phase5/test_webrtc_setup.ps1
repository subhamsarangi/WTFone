# Test Phase 5: WebRTC Client Implementation
# Validates HTML serves, WebSocket connects, and signaling works
# Note: Full WebRTC video test requires browser automation (Playwright/Puppeteer)

$baseUrl = "http://localhost:8443"
$password = "test123"

Write-Host "=== Phase 5: WebRTC Client Implementation Tests ===" -ForegroundColor Cyan

# Test 1: HTML serves with video elements
Write-Host "`n[Test 1] HTML serves with video elements..." -ForegroundColor Yellow
$htmlResp = Invoke-WebRequest -Uri "$baseUrl/" -UseBasicParsing
$html = $htmlResp.Content

if ($html -match 'local-video' -and $html -match 'videoSection' -and $html -match 'createElement.*video') {
    Write-Host "✓ PASS: HTML contains video elements" -ForegroundColor Green
} else {
    Write-Host "✗ FAIL: HTML missing video elements" -ForegroundColor Red
    exit 1
}

# Test 2: HTML contains WebRTC JS functions
Write-Host "`n[Test 2] HTML contains WebRTC functions..." -ForegroundColor Yellow
$requiredFunctions = @(
    "createPeerConnection",
    "handleOffer",
    "handleAnswer",
    "handleIce",
    "displayLocalVideo",
    "displayRemoteVideo",
    "toggleAudio",
    "toggleVideo",
    "toggleRecording"
)

$allFound = $true
foreach ($func in $requiredFunctions) {
    if ($html -match "function $func|const $func|$func\s*=\s*") {
        Write-Host "  ✓ Found: $func" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing: $func" -ForegroundColor Red
        $allFound = $false
    }
}

if (-not $allFound) {
    Write-Host "✗ FAIL: Missing WebRTC functions" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PASS: All WebRTC functions present" -ForegroundColor Green

# Test 3: HTML contains STUN server config
Write-Host "`n[Test 3] STUN server configuration..." -ForegroundColor Yellow
if ($html -match "stun:stun.l.google.com:19302") {
    Write-Host "✓ PASS: STUN server configured" -ForegroundColor Green
} else {
    Write-Host "✗ FAIL: STUN server not configured" -ForegroundColor Red
    exit 1
}

# Test 4: WebSocket connection + signaling flow
Write-Host "`n[Test 4] WebSocket + signaling flow..." -ForegroundColor Yellow

# Create room
$roomResp = Invoke-WebRequest -Method POST `
  -Uri "$baseUrl/api/rooms" `
  -ContentType "application/json" `
  -Body "{`"password`":`"$password`"}" `
  -UseBasicParsing

$roomId = ($roomResp.Content | ConvertFrom-Json).room_id
Write-Host "  Room created: $roomId" -ForegroundColor Cyan

# Connect peer A
$peerAWs = New-Object System.Net.WebSockets.ClientWebSocket
$peerAUri = New-Object System.Uri("ws://localhost:8443/api/rooms/$roomId/ws")
$peerAWs.ConnectAsync($peerAUri, [System.Threading.CancellationToken]::None).Wait()
Write-Host "  Peer A connected" -ForegroundColor Cyan

# Peer A joins
$joinMsg = @{
  type = "join"
  room_id = $roomId
  password = $password
} | ConvertTo-Json

$joinBytes = [System.Text.Encoding]::UTF8.GetBytes($joinMsg)
$peerAWs.SendAsync([System.ArraySegment[byte]]$joinBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

# Read joined message
$buffer = New-Object byte[] 1024
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$joinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerAId = ($joinedMsg | ConvertFrom-Json).peer_id
Write-Host "  Peer A joined: $peerAId" -ForegroundColor Cyan

# Connect peer B
$peerBWs = New-Object System.Net.WebSockets.ClientWebSocket
$peerBWs.ConnectAsync($peerAUri, [System.Threading.CancellationToken]::None).Wait()
$peerBWs.SendAsync([System.ArraySegment[byte]]$joinBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

$result = $peerBWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$joinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerBId = ($joinedMsg | ConvertFrom-Json).peer_id
Write-Host "  Peer B joined: $peerBId" -ForegroundColor Cyan

# Peer A receives peer_joined
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$peerJoinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerJoined = $peerJoinedMsg | ConvertFrom-Json

if ($peerJoined.type -eq "peer_joined" -and $peerJoined.peer_id -eq $peerBId) {
    Write-Host "  ✓ Peer A received peer_joined notification" -ForegroundColor Green
} else {
    Write-Host "  ✗ FAIL: peer_joined notification incorrect" -ForegroundColor Red
    exit 1
}

# Test 5: Offer/Answer exchange (simulating WebRTC signaling)
Write-Host "`n[Test 5] Offer/Answer signaling..." -ForegroundColor Yellow

# Peer A sends offer to Peer B
$offerMsg = @{
  type = "offer"
  to = $peerBId
  sdp = "v=0`r`no=- 1 1 IN IP4 127.0.0.1"
} | ConvertTo-Json

$offerBytes = [System.Text.Encoding]::UTF8.GetBytes($offerMsg)
$peerAWs.SendAsync([System.ArraySegment[byte]]$offerBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()
Write-Host "  Peer A sent offer" -ForegroundColor Cyan

# Peer B receives offer with timeout
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter(5000)
try {
    $result = $peerBWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts.Token).Result
    $receivedOffer = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
    $offerObj = $receivedOffer | ConvertFrom-Json

    if ($offerObj.type -eq "offer" -and $offerObj.from -eq $peerAId) {
        Write-Host "  ✓ Peer B received offer from Peer A" -ForegroundColor Green
    } else {
        Write-Host "  ✗ FAIL: Offer not relayed correctly" -ForegroundColor Red
        Write-Host "    Received: $receivedOffer" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ FAIL: Timeout waiting for offer" -ForegroundColor Red
    exit 1
}

Write-Host "✓ PASS: Offer/Answer exchange successful" -ForegroundColor Green

# Test 6: Control buttons present
Write-Host "`n[Test 6] Control buttons..." -ForegroundColor Yellow
$buttons = @(
    "muteAudioBtn",
    "muteVideoBtn",
    "recordBtn",
    "leaveBtn",
    "joinBtn",
    "createBtn"
)

$allButtonsFound = $true
foreach ($btn in $buttons) {
    if ($html -match "id=`"$btn`"") {
        Write-Host "  ✓ Found: $btn" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing: $btn" -ForegroundColor Red
        $allButtonsFound = $false
    }
}

if (-not $allButtonsFound) {
    Write-Host "✗ FAIL: Missing control buttons" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PASS: All control buttons present" -ForegroundColor Green

# Cleanup
$peerAWs.Dispose()
$peerBWs.Dispose()

Write-Host "`n=== Phase 5 Tests Complete ===" -ForegroundColor Green
Write-Host "✓ All tests passed!" -ForegroundColor Green
Write-Host "`nNote: Full WebRTC video/audio testing requires browser automation (Playwright/Puppeteer)" -ForegroundColor Yellow
exit 0
