# Test WebSocket connection with certificate bypass and room pre-creation
$csharpCode = @"
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public class SSLBypass {
    public static void Bypass() {
        ServicePointManager.ServerCertificateValidationCallback = ValidateCertificate;
    }
    
    private static bool ValidateCertificate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) {
        return true;
    }
}
"@

try {
    Add-Type -TypeDefinition $csharpCode -ErrorAction SilentlyContinue
} catch {}

[SSLBypass]::Bypass()

$baseUrl = "https://localhost:8443"
$password = "test123"

# Step 1: Create room first so it exists in memory
Write-Host "Creating room..." -ForegroundColor Cyan
$roomResp = Invoke-WebRequest -Method POST `
  -Uri "$baseUrl/api/rooms" `
  -ContentType "application/json" `
  -Body "{`"password`":`"$password`"}" `
  -UseBasicParsing

$roomId = ($roomResp.Content | ConvertFrom-Json).room_id
Write-Host "Room created: $roomId" -ForegroundColor Green

# Step 2: Connect WebSocket using secure wss:// protocol
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource

try {
    $uri = "wss://localhost:8443/api/rooms/$roomId/ws"
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
    
    # Receive joined message
    $buffer = New-Object byte[] 4096
    $result = $ws.ReceiveAsync([System.ArraySegment[byte]]$buffer, $cts.Token).Result
    $msg = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
    Write-Host "Received: $msg"
    
    # Clean up via finally block
}
finally {
    $ws.Dispose()
    $cts.Dispose()
}
exit 0
