# Phase 8: Robust Error Handling & Edge Cases Test
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

Write-Host "=== Phase 8: Robust Error Handling & Edge Cases Test ===" -ForegroundColor Cyan

$baseUrl = "https://localhost:8443"

# Helper function to execute Web request and handle errors safely in older PowerShell versions
function Invoke-SafeRequest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$ContentType,
        [string]$Body
    )
    
    try {
        if ($Body) {
            $resp = Invoke-WebRequest -Method $Method -Uri $Uri -ContentType $ContentType -Body $Body -UseBasicParsing
        } else {
            $resp = Invoke-WebRequest -Method $Method -Uri $Uri -UseBasicParsing
        }
        return @{
            StatusCode = $resp.StatusCode
            Content = $resp.Content
        }
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -eq $null) {
            return @{
                StatusCode = 0
                Content = $_.Exception.Message
            }
        }
        $statusCode = [int]$resp.StatusCode
        $stream = $resp.GetResponseStream()
        $content = ""
        if ($stream) {
            $reader = New-Object System.IO.StreamReader($stream)
            $content = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
        }
        return @{
            StatusCode = $statusCode
            Content = $content
        }
    } catch {
        return @{
            StatusCode = 500
            Content = $_.Exception.Message
        }
    }
}

# Test 1: Invalid JSON / Empty password room creation
Write-Host "`nTest 1: Request room creation with empty password..." -ForegroundColor Yellow
$res1 = Invoke-SafeRequest -Method POST -Uri "$baseUrl/api/rooms" -ContentType "application/json" -Body '{"password":""}'
if ($res1.StatusCode -eq 400) {
    Write-Host "✓ Correctly rejected empty password with 400 Bad Request: $($res1.Content)" -ForegroundColor Green
} else {
    Write-Host "✗ Expected status 400, got: $($res1.StatusCode) | Content: $($res1.Content)" -ForegroundColor Red
    exit 1
}

# Test 2: Upload recording to a non-existent room
Write-Host "`nTest 2: Upload recording to non-existent room..." -ForegroundColor Yellow
$fakeRoomId = "00000000-0000-0000-0000-000000000000"
$boundary = [System.Guid]::NewGuid().ToString()
$LF = "`r`n"
$body = (
    "--$boundary",
    "Content-Disposition: form-data; name=`"file`"; filename=`"test.webm`"",
    "Content-Type: video/webm$LF",
    "dummy-webm-payload",
    "--$boundary--$LF"
) -join $LF

$res2 = Invoke-SafeRequest -Method POST -Uri "$baseUrl/api/rooms/$fakeRoomId/recording" -ContentType "multipart/form-data; boundary=$boundary" -Body $body
if ($res2.StatusCode -eq 404) {
    Write-Host "✓ Correctly rejected non-existent room with 404 Not Found: $($res2.Content)" -ForegroundColor Green
} else {
    Write-Host "✗ Expected status 404, got: $($res2.StatusCode) | Content: $($res2.Content)" -ForegroundColor Red
    exit 1
}

# Test 3: Upload recording to a malformed room ID
Write-Host "`nTest 3: Upload recording to malformed room ID..." -ForegroundColor Yellow
$res3 = Invoke-SafeRequest -Method POST -Uri "$baseUrl/api/rooms/not-a-valid-uuid/recording" -ContentType "multipart/form-data; boundary=$boundary" -Body $body
if ($res3.StatusCode -eq 400) {
    Write-Host "✓ Correctly rejected malformed UUID with 400 Bad Request: $($res3.Content)" -ForegroundColor Green
} else {
    Write-Host "✗ Expected status 400, got: $($res3.StatusCode) | Content: $($res3.Content)" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All Phase 8 error handling tests passed successfully! ===" -ForegroundColor Green
exit 0
