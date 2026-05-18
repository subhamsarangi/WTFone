# Chunk recording upload test
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

Write-Host "=== Phase 6.5: Chunk Recording Upload Test ===" -ForegroundColor Cyan

$baseUrl = "https://localhost:8443"

# Test 1: Create room
Write-Host "`nTest 1: Create room..." -ForegroundColor Yellow
$createResponse = Invoke-RestMethod -Method POST -Uri "$baseUrl/api/rooms" `
    -ContentType "application/json" `
    -Body '{"password":"test123"}'

$roomId = $createResponse.room_id
Write-Host "✓ Room created: $roomId" -ForegroundColor Green

# Test 2: Upload multiple chunks to the same filename
Write-Host "`nTest 2: Uploading 3 chunks to the same filename..." -ForegroundColor Yellow

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$peerId = "chunk-test-peer-123"
$filename = "${timestamp}_${peerId}.webm"

# Create dummy chunks (different sizes)
$chunk1 = [byte[]](1..100) # 100 bytes
$chunk2 = [byte[]](1..200) # 200 bytes
$chunk3 = [byte[]](1..50)  # 50 bytes

$chunks = @($chunk1, $chunk2, $chunk3)
$expectedTotalSize = 100 + 200 + 50

for ($i = 0; $i -lt $chunks.Count; $i++) {
    $chunkData = $chunks[$i]
    $tempFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($tempFile, $chunkData)
    
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
        $fileContent = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes)
        
        $boundary = [System.Guid]::NewGuid().ToString()
        $LF = "`r`n"
        
        $bodyLines = (
            "--$boundary",
            "Content-Disposition: form-data; name=`"file`"; filename=`"$filename`"",
            "Content-Type: video/webm$LF",
            $fileContent,
            "--$boundary--$LF"
        ) -join $LF
        
        Write-Host "Uploading chunk $($i + 1) ($($chunkData.Count) bytes)..."
        $response = Invoke-RestMethod -Uri "$baseUrl/api/rooms/$roomId/recording" `
            -Method POST `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $bodyLines
        
        Write-Host "✓ Chunk $($i + 1) uploaded: $($response | ConvertTo-Json -Compress)" -ForegroundColor Green
    } catch {
        Write-Host "✗ Chunk $($i + 1) upload failed: $_" -ForegroundColor Red
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        exit 1
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# Test 3: Check recordings directory and total file size
Write-Host "`nTest 3: Check total file size of appended chunks..." -ForegroundColor Yellow
$recordingsDir = "recordings\$roomId"
if (-not (Test-Path $recordingsDir)) {
    $recordingsDir = "..\recordings\$roomId"
}
if (Test-Path $recordingsDir) {
    $filePath = Join-Path $recordingsDir $filename
    if (Test-Path $filePath) {
        $file = Get-Item $filePath
        Write-Host "✓ Recording saved: $($file.Name)" -ForegroundColor Green
        Write-Host "✓ Total File Size: $($file.Length) bytes (Expected: $expectedTotalSize bytes)" -ForegroundColor Green
        
        if ($file.Length -eq $expectedTotalSize) {
            Write-Host "`n=== Phase 6.5 chunk appending successfully verified! ===" -ForegroundColor Green
            exit 0
        } else {
            Write-Host "✗ File size mismatch!" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "✗ Recording file not found" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✗ Recordings directory not created" -ForegroundColor Red
    exit 1
}
