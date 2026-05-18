# Simple recording upload test
Write-Host "=== Phase 6: Recording Upload Test ===" -ForegroundColor Cyan

$baseUrl = "http://localhost:8443"

# Test 1: Create room
Write-Host "`nTest 1: Create room..." -ForegroundColor Yellow
$createResponse = Invoke-RestMethod -Method POST -Uri "$baseUrl/api/rooms" `
    -ContentType "application/json" `
    -Body '{"password":"test123"}'

$roomId = $createResponse.room_id
Write-Host "✓ Room created: $roomId" -ForegroundColor Green

# Test 2: Create test file and upload
Write-Host "`nTest 2: Upload recording..." -ForegroundColor Yellow

# Create test webm file
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$peerId = "test-peer-123"
$filename = "${timestamp}_${peerId}.webm"

# Create dummy data (small file)
$dummyData = [byte[]](0..255)
$tempFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllBytes($tempFile, $dummyData)

try {
    # Read file content
    $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
    $fileContent = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes)
    
    # Build multipart form data
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    
    $bodyLines = (
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$filename`"",
        "Content-Type: video/webm$LF",
        $fileContent,
        "--$boundary--$LF"
    ) -join $LF
    
    $response = Invoke-RestMethod -Uri "$baseUrl/api/rooms/$roomId/recording" `
        -Method POST `
        -ContentType "multipart/form-data; boundary=$boundary" `
        -Body $bodyLines
    
    Write-Host "✓ Upload successful: $($response | ConvertTo-Json -Compress)" -ForegroundColor Green
} catch {
    Write-Host "✗ Upload failed: $_" -ForegroundColor Red
    Write-Host "  Error details: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    exit 1
}

# Clean up test file
Remove-Item $tempFile -ErrorAction SilentlyContinue

# Test 3: Check recordings directory
Write-Host "`nTest 3: Check recordings directory..." -ForegroundColor Yellow
$recordingsDir = "recordings\$roomId"
if (Test-Path $recordingsDir) {
    $files = Get-ChildItem $recordingsDir
    if ($files.Count -gt 0) {
        Write-Host "✓ Recording saved: $($files[0].Name)" -ForegroundColor Green
        Write-Host "  File size: $($files[0].Length) bytes" -ForegroundColor Gray
    } else {
        Write-Host "✗ No files in recordings directory" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✗ Recordings directory not created" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All tests passed! ===" -ForegroundColor Green
exit 0
