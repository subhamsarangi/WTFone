# Test offer relay between two peers
# Start server first: cargo run

$baseUrl = "http://localhost:3000"
$password = "test123"

# Step 1: Create room
Write-Host "Creating room..." -ForegroundColor Cyan
$roomResp = Invoke-WebRequest -Method POST `
  -Uri "$baseUrl/api/rooms" `
  -ContentType "application/json" `
  -Body "{`"password`":`"$password`"}" `
  -UseBasicParsing

$roomId = ($roomResp.Content | ConvertFrom-Json).room_id
Write-Host "Room created: $roomId" -ForegroundColor Green

# Step 2: Connect peer A
Write-Host "`nConnecting peer A..." -ForegroundColor Cyan
$peerAWs = New-Object System.Net.WebSockets.ClientWebSocket
$peerAUri = New-Object System.Uri("ws://localhost:3000/api/rooms/$roomId/ws")
$peerAWs.ConnectAsync($peerAUri, [System.Threading.CancellationToken]::None).Wait()
Write-Host "Peer A connected" -ForegroundColor Green

# Step 3: Peer A joins
$joinMsg = @{
  type = "join"
  room_id = $roomId
  password = $password
} | ConvertTo-Json

$joinBytes = [System.Text.Encoding]::UTF8.GetBytes($joinMsg)
$peerAWs.SendAsync([System.ArraySegment[byte]]$joinBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

# Read peer A's joined message
$buffer = New-Object byte[] 1024
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$joinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerAId = ($joinedMsg | ConvertFrom-Json).peer_id
Write-Host "Peer A joined with ID: $peerAId" -ForegroundColor Green

# Step 4: Connect peer B
Write-Host "`nConnecting peer B..." -ForegroundColor Cyan
$peerBWs = New-Object System.Net.WebSockets.ClientWebSocket
$peerBWs.ConnectAsync($peerAUri, [System.Threading.CancellationToken]::None).Wait()
Write-Host "Peer B connected" -ForegroundColor Green

# Step 5: Peer B joins
$peerBWs.SendAsync([System.ArraySegment[byte]]$joinBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

# Read peer B's joined message
$result = $peerBWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$joinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerBId = ($joinedMsg | ConvertFrom-Json).peer_id
Write-Host "Peer B joined with ID: $peerBId" -ForegroundColor Green

# Step 6: Peer A receives peer_joined notification
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$peerJoinedMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
Write-Host "Peer A received: $peerJoinedMsg" -ForegroundColor Yellow

# Step 7: Peer A sends offer to peer B
Write-Host "`nPeer A sending offer to peer B..." -ForegroundColor Cyan
$offerMsg = @{
  type = "offer"
  to = $peerBId
  sdp = "v=0`r`no=- 0 0 IN IP4 127.0.0.1`r`ns=-`r`nt=0 0`r`na=group:BUNDLE 0`r`na=extmap-allow-mixed`r`nm=application 9 UDP/TLS/RTP/SAVPF 120"
} | ConvertTo-Json

$offerBytes = [System.Text.Encoding]::UTF8.GetBytes($offerMsg)
$peerAWs.SendAsync([System.ArraySegment[byte]]$offerBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()
Write-Host "Offer sent" -ForegroundColor Green

# Step 8: Peer B receives offer
Write-Host "`nWaiting for peer B to receive offer..." -ForegroundColor Cyan
$result = $peerBWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$receivedOffer = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$offerObj = $receivedOffer | ConvertFrom-Json

if ($offerObj.type -eq "offer" -and $offerObj.from -eq $peerAId) {
  Write-Host "✓ SUCCESS: Peer B received offer from peer A!" -ForegroundColor Green
  Write-Host "  From: $($offerObj.from)" -ForegroundColor Green
  Write-Host "  SDP: $($offerObj.sdp)" -ForegroundColor Green
} else {
  Write-Host "✗ FAILED: Unexpected message" -ForegroundColor Red
  Write-Host "  Received: $receivedOffer" -ForegroundColor Red
  exit 1
}

# Step 9: Peer B sends answer to peer A
Write-Host "`nPeer B sending answer to peer A..." -ForegroundColor Cyan
$answerMsg = @{
  type = "answer"
  to = $peerAId
  sdp = "v=0`r`no=- 0 0 IN IP4 127.0.0.1`r`ns=-`r`nt=0 0`r`na=group:BUNDLE 0`r`na=extmap-allow-mixed`r`nm=application 9 UDP/TLS/RTP/SAVPF 120"
} | ConvertTo-Json

$answerBytes = [System.Text.Encoding]::UTF8.GetBytes($answerMsg)
$peerBWs.SendAsync([System.ArraySegment[byte]]$answerBytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()
Write-Host "Answer sent" -ForegroundColor Green

# Step 10: Peer A receives answer
Write-Host "`nWaiting for peer A to receive answer..." -ForegroundColor Cyan
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$receivedAnswer = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$answerObj = $receivedAnswer | ConvertFrom-Json

if ($answerObj.type -eq "answer" -and $answerObj.from -eq $peerBId) {
  Write-Host "✓ SUCCESS: Peer A received answer from peer B!" -ForegroundColor Green
  Write-Host "  From: $($answerObj.from)" -ForegroundColor Green
  Write-Host "  SDP: $($answerObj.sdp)" -ForegroundColor Green
} else {
  Write-Host "✗ FAILED: Unexpected message" -ForegroundColor Red
  Write-Host "  Received: $receivedAnswer" -ForegroundColor Red
  exit 1
}

# Cleanup
$peerAWs.Dispose()
$peerBWs.Dispose()
Write-Host "`n✓ All tests passed!" -ForegroundColor Green
