# Phase 6: Recording Upload Test
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

Write-Host "=== Phase 6: Recording Upload Test ===" -ForegroundColor Cyan

$baseUrl = "https://localhost:8443"
$testPassed = $true

# Test 1: Create room
Write-Host "`nTest 1: Create room..." -ForegroundColor Yellow
try {
    $createResponse = Invoke-RestMethod -Method POST -Uri "$baseUrl/api/rooms" `
        -ContentType "application/json" `
        -Body '{"password":"test123"}'
    
    $roomId = $createResponse.room_id
    Write-Host "✓ Room created: $roomId" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to create room: $_" -ForegroundColor Red
    $testPassed = $false
    exit 1
}

# Test 2: Upload recording
Write-Host "`nTest 2: Upload recording..." -ForegroundColor Yellow
try {
    # Create dummy webm file with valid byte range (0-255)
    $dummyData = [byte[]](0..255) * 4  # 1024 bytes total
    $tempFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllBytes($tempFile, $dummyData)
    
    # Read file and build multipart
    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
    $fileContent = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes)
    
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $peerId = "test-peer-api"
    $fileName = "${timestamp}_${peerId}.webm"
    
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    
    $bodyLines = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
        "Content-Type: video/webm$LF",
        $fileContent,
        "--$boundary--$LF"
    ) -join $LF
    
    $uploadResponse = Invoke-RestMethod -Method POST `
        -Uri "$baseUrl/api/rooms/$roomId/recording" `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $bodyLines
    
    Write-Host "✓ Recording uploaded successfully" -ForegroundColor Green
    Write-Host "  Response: $($uploadResponse | ConvertTo-Json -Compress)" -ForegroundColor Gray
    
    # Clean up temp file
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
} catch {
    Write-Host "✗ Failed to upload recording: $_" -ForegroundColor Red
    Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
    $testPassed = $false
}

# Test 3: Check recordings directory
Write-Host "`nTest 3: Check recordings directory..." -ForegroundColor Yellow
$recordingsDir = "recordings\$roomId"
if (-not (Test-Path $recordingsDir)) {
    $recordingsDir = "..\recordings\$roomId"
}
if (Test-Path $recordingsDir) {
    $files = Get-ChildItem $recordingsDir
    if ($files.Count -gt 0) {
        Write-Host "✓ Recording file saved: $($files[0].Name)" -ForegroundColor Green
        Write-Host "  File size: $($files[0].Length) bytes" -ForegroundColor Gray
    } else {
        Write-Host "✗ No files in recordings directory" -ForegroundColor Red
        $testPassed = $false
    }
} else {
    Write-Host "✗ Recordings directory not created" -ForegroundColor Red
    $testPassed = $false
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
if ($testPassed) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
