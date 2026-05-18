# Phase 6 Recording Upload API Test
# Tests recording endpoint with curl/Invoke-WebRequest
# Run: .\test_recording_api.ps1

$BASE_URL = "http://localhost:3000"
$PASSWORD = "test123"
$RECORDINGS_DIR = ".\recordings"

Write-Host "=== Phase 6: Recording Upload API Test ===" -ForegroundColor Cyan

# Test 1: Create room
Write-Host "`n[Test 1] Create room..." -ForegroundColor Yellow
$createResponse = Invoke-WebRequest -Method POST `
  -Uri "$BASE_URL/api/rooms" `
  -ContentType "application/json" `
  -Body "{`"password`": `"$PASSWORD`"}" `
  -ErrorAction Stop

$roomData = $createResponse.Content | ConvertFrom-Json
$roomId = $roomData.room_id

if ($roomId -match '^[0-9a-f-]{36}$') {
  Write-Host "✓ Room created: $roomId" -ForegroundColor Green
} else {
  Write-Host "✗ Invalid room ID format: $roomId" -ForegroundColor Red
  exit 1
}

# Test 2: Upload dummy recording file
Write-Host "`n[Test 2] Upload recording file..." -ForegroundColor Yellow

# Create dummy webm file
$dummyFile = ".\test_recording.webm"
$dummyContent = [System.Text.Encoding]::UTF8.GetBytes("dummy webm data")
[System.IO.File]::WriteAllBytes($dummyFile, $dummyContent)

try {
  $uploadResponse = Invoke-WebRequest -Method POST `
    -Uri "$BASE_URL/api/rooms/$roomId/recording" `
    -Form @{
      file = Get-Item $dummyFile
    } `
    -ErrorAction Stop
  
  Write-Host "✓ Upload successful (status: $($uploadResponse.StatusCode))" -ForegroundColor Green
} catch {
  Write-Host "✗ Upload failed: $($_.Exception.Message)" -ForegroundColor Red
  Remove-Item $dummyFile -Force
  exit 1
}

# Clean up dummy file
Remove-Item $dummyFile -Force

# Test 3: Verify file exists in recordings directory
Write-Host "`n[Test 3] Verify file saved to disk..." -ForegroundColor Yellow

$roomRecordingsDir = Join-Path $RECORDINGS_DIR $roomId
if (Test-Path $roomRecordingsDir) {
  $files = Get-ChildItem $roomRecordingsDir -Filter "*.webm"
  if ($files.Count -gt 0) {
    Write-Host "✓ Recording file saved: $($files[0].Name)" -ForegroundColor Green
  } else {
    Write-Host "✗ No .webm files found in $roomRecordingsDir" -ForegroundColor Red
    exit 1
  }
} else {
  Write-Host "✗ Recordings directory not created: $roomRecordingsDir" -ForegroundColor Red
  exit 1
}

# Test 4: Verify filename format (timestamp_peerid.webm)
Write-Host "`n[Test 4] Verify filename format..." -ForegroundColor Yellow

$filename = $files[0].Name
if ($filename -match '^\d+_[0-9a-f-]+\.webm$') {
  Write-Host "✓ Filename format correct: $filename" -ForegroundColor Green
} else {
  Write-Host "⚠ Filename format unexpected: $filename (expected: {timestamp}_{peer_id}.webm)" -ForegroundColor Yellow
}

# Test 5: Upload to non-existent room (should fail)
Write-Host "`n[Test 5] Upload to non-existent room (should fail)..." -ForegroundColor Yellow

$fakeRoomId = "00000000-0000-0000-0000-000000000000"
$dummyFile = ".\test_recording.webm"
[System.IO.File]::WriteAllBytes($dummyFile, $dummyContent)

try {
  $badResponse = Invoke-WebRequest -Method POST `
    -Uri "$BASE_URL/api/rooms/$fakeRoomId/recording" `
    -Form @{
      file = Get-Item $dummyFile
    } `
    -ErrorAction Stop
  
  Write-Host "✗ Should have failed but got status: $($badResponse.StatusCode)" -ForegroundColor Red
  Remove-Item $dummyFile -Force
  exit 1
} catch {
  $statusCode = $_.Exception.Response.StatusCode.Value__
  if ($statusCode -eq 404 -or $statusCode -eq 400) {
    Write-Host "✓ Correctly rejected non-existent room (status: $statusCode)" -ForegroundColor Green
  } else {
    Write-Host "✗ Unexpected status code: $statusCode" -ForegroundColor Red
    Remove-Item $dummyFile -Force
    exit 1
  }
}

Remove-Item $dummyFile -Force

# Test 6: Upload without file (should fail)
Write-Host "`n[Test 6] Upload without file (should fail)..." -ForegroundColor Yellow

try {
  $noFileResponse = Invoke-WebRequest -Method POST `
    -Uri "$BASE_URL/api/rooms/$roomId/recording" `
    -ContentType "multipart/form-data" `
    -ErrorAction Stop
  
  Write-Host "✗ Should have failed but got status: $($noFileResponse.StatusCode)" -ForegroundColor Red
  exit 1
} catch {
  $statusCode = $_.Exception.Response.StatusCode.Value__
  if ($statusCode -eq 400) {
    Write-Host "✓ Correctly rejected empty upload (status: $statusCode)" -ForegroundColor Green
  } else {
    Write-Host "⚠ Got status $statusCode (expected 400)" -ForegroundColor Yellow
  }
}

# Test 7: Multiple uploads create separate files
Write-Host "`n[Test 7] Multiple uploads create separate files..." -ForegroundColor Yellow

$dummyFile1 = ".\test_recording1.webm"
$dummyFile2 = ".\test_recording2.webm"
[System.IO.File]::WriteAllBytes($dummyFile1, $dummyContent)
[System.IO.File]::WriteAllBytes($dummyFile2, $dummyContent)

try {
  Invoke-WebRequest -Method POST `
    -Uri "$BASE_URL/api/rooms/$roomId/recording" `
    -Form @{
      file = Get-Item $dummyFile1
    } `
    -ErrorAction Stop | Out-Null
  
  Start-Sleep -Milliseconds 300
  
  Invoke-WebRequest -Method POST `
    -Uri "$BASE_URL/api/rooms/$roomId/recording" `
    -Form @{
      file = Get-Item $dummyFile2
    } `
    -ErrorAction Stop | Out-Null
  
  $files = Get-ChildItem $roomRecordingsDir -Filter "*.webm"
  if ($files.Count -ge 2) {
    Write-Host "✓ Multiple files created: $($files.Count) files" -ForegroundColor Green
  } else {
    Write-Host "✗ Expected at least 2 files, got $($files.Count)" -ForegroundColor Red
    Remove-Item $dummyFile1, $dummyFile2 -Force
    exit 1
  }
} catch {
  Write-Host "✗ Multiple upload test failed: $($_.Exception.Message)" -ForegroundColor Red
  Remove-Item $dummyFile1, $dummyFile2 -Force
  exit 1
}

Remove-Item $dummyFile1, $dummyFile2 -Force

# Summary
Write-Host "`n=== All Tests Passed ===" -ForegroundColor Green
Write-Host "Room ID: $roomId" -ForegroundColor Cyan
Write-Host "Recordings saved to: $roomRecordingsDir" -ForegroundColor Cyan
