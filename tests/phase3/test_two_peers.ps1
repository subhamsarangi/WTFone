# Create room
$body = @{ password = "test123" } | ConvertTo-Json
$response = Invoke-WebRequest -Method POST -Uri http://localhost:8443/api/rooms -ContentType "application/json" -Body $body
$roomId = ($response.Content | ConvertFrom-Json).room_id
Write-Host "Created room: $roomId"

# Connect peer 1
$ws1 = New-Object System.Net.WebSockets.ClientWebSocket
$cts1 = New-Object System.Threading.CancellationTokenSource
$uri = "ws://localhost:8443/api/rooms/$roomId/ws"
$ws1.ConnectAsync($uri, $cts1.Token).Wait()
Write-Host "Peer 1 connected"

# Send join from peer 1
$joinMsg = @{
    type = "join"
    room_id = $roomId
    password = "test123"
} | ConvertTo-Json
$bytes = [System.Text.Encoding]::UTF8.GetBytes($joinMsg)
$ws1.SendAsync([System.ArraySegment[byte]]$bytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts1.Token).Wait()
Write-Host "Peer 1 sent join"

# Receive joined message from peer 1
$buffer = New-Object byte[] 4096
$result = $ws1.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts1.Token).Result
$msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
Write-Host "Peer 1 received: $msg"

# Connect peer 2
Start-Sleep -Milliseconds 500
$ws2 = New-Object System.Net.WebSockets.ClientWebSocket
$cts2 = New-Object System.Threading.CancellationTokenSource
$ws2.ConnectAsync($uri, $cts2.Token).Wait()
Write-Host "Peer 2 connected"

# Send join from peer 2
$ws2.SendAsync([System.ArraySegment[byte]]$bytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts2.Token).Wait()
Write-Host "Peer 2 sent join"

# Receive joined message from peer 2
$result = $ws2.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts2.Token).Result
$msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
Write-Host "Peer 2 received: $msg"

# Peer 1 should receive peer_joined notification
Start-Sleep -Milliseconds 100
$result = $ws1.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts1.Token).Result
$msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
Write-Host "Peer 1 received notification: $msg"

Write-Host "Test complete!"
$ws1.Dispose()
$ws2.Dispose()
exit 0
