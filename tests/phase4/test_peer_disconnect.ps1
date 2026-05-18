# Test peer disconnect broadcast
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

# Step 7: Peer B disconnects
Write-Host "`nPeer B disconnecting..." -ForegroundColor Cyan
try {
  $peerBWs.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Goodbye", [System.Threading.CancellationToken]::None).Wait()
} catch {
  # Ignore close errors
}
$peerBWs.Dispose()
Write-Host "Peer B disconnected" -ForegroundColor Green

# Step 8: Peer A receives peer_left notification
Write-Host "`nWaiting for peer A to receive peer_left..." -ForegroundColor Cyan
$result = $peerAWs.ReceiveAsync([System.ArraySegment[byte]]$buffer, [System.Threading.CancellationToken]::None).Result
$peerLeftMsg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
$peerLeftObj = $peerLeftMsg | ConvertFrom-Json

if ($peerLeftObj.type -eq "peer_left" -and $peerLeftObj.peer_id -eq $peerBId) {
  Write-Host "✓ SUCCESS: Peer A received peer_left from peer B!" -ForegroundColor Green
  Write-Host "  Peer ID: $($peerLeftObj.peer_id)" -ForegroundColor Green
} else {
  Write-Host "✗ FAILED: Unexpected message" -ForegroundColor Red
  Write-Host "  Received: $peerLeftMsg" -ForegroundColor Red
  exit 1
}

# Cleanup
$peerAWs.Dispose()
Write-Host "`n✓ Peer disconnect test passed!" -ForegroundColor Green
