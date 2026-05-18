$roomId = "01e6b5c0-b3e3-4197-b85f-85bb6905cbd5"
$password = "test123"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource

try {
    $uri = "ws://localhost:8443/api/rooms/$roomId/ws"
    Write-Host "Connecting to $uri"
    $ws.ConnectAsync($uri, $cts.Token).Wait()
    Write-Host "Connected!"
    
    # Send join message
    $joinMsg = @{
        type = "join"
        room_id = $roomId
        password = $password
    } | ConvertTo-Json
    
    Write-Host "Sending join message: $joinMsg"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joinMsg)
    $ws.SendAsync([System.ArraySegment[byte]]$bytes, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
    
    # Receive messages
    $buffer = New-Object byte[] 4096
    for ($i = 0; $i -lt 5; $i++) {
        $result = $ws.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts.Token).Result
        $msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
        Write-Host "Received: $msg"
        
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            break
        }
    }
    
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Done", $cts.Token).Wait()
    Write-Host "Closed"
}
finally {
    $ws.Dispose()
    $cts.Dispose()
}
exit 0
