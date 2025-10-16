# test_ugc_utf8_fixed.ps1
# Properly encoded UTF-8 test for CJK characters

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$submitUrl = "https://$ProjectRef.supabase.co/functions/v1/ugc-places-submit"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   UTF-8 ENCODING TEST FOR CJK CHARACTERS" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Authenticate
Write-Host "`n--- Authenticating testuser ---" -ForegroundColor Cyan
$authBody = @{
    email = "testuser@example.com"
    password = "TestPass123!"
} | ConvertTo-Json

$auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers @{
    "apikey" = $AnonKey
    "Content-Type" = "application/json"
} -Body $authBody

$jwt = $auth.access_token
$userId = $auth.user.id
Write-Host "Authenticated as: $userId" -ForegroundColor Green

# Helper function to make API calls with proper UTF-8 encoding
function Invoke-UTF8Request {
    param(
        [string]$Url,
        [string]$JsonBody,
        [string]$Jwt
    )
    
    # Convert JSON string to UTF-8 bytes
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
    
    # Create the request
    $webRequest = [System.Net.HttpWebRequest]::Create($Url)
    $webRequest.Method = "POST"
    $webRequest.ContentType = "application/json; charset=utf-8"
    $webRequest.ContentLength = $bodyBytes.Length
    $webRequest.Headers.Add("apikey", $AnonKey)
    $webRequest.Headers.Add("Authorization", "Bearer $Jwt")
    $webRequest.Headers.Add("X-API-Version", "v1")
    
    # Write body
    $requestStream = $webRequest.GetRequestStream()
    $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $requestStream.Close()
    
    # Get response
    try {
        $response = $webRequest.GetResponse()
        $responseStream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8)
        $responseText = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()
        
        return @{
            Success = $true
            Data = ($responseText | ConvertFrom-Json)
            StatusCode = [int]$response.StatusCode
        }
    } catch {
        $errorResponse = $_.Exception.Response
        if ($errorResponse) {
            $errorStream = $errorResponse.GetResponseStream()
            $errorReader = New-Object System.IO.StreamReader($errorStream)
            $errorText = $errorReader.ReadToEnd()
            $errorReader.Close()
            
            return @{
                Success = $false
                Error = $errorText
                StatusCode = [int]$errorResponse.StatusCode
            }
        }
        return @{
            Success = $false
            Error = $_.Exception.Message
            StatusCode = 0
        }
    }
}

# Test 1: English name
Write-Host "`n--- Test 1: English name + GPS ---" -ForegroundColor Cyan
$json1 = '{"name_en":"Ichiran Ramen Shibuya","lat":35.6595,"lng":139.7004}'
$result1 = Invoke-UTF8Request -Url $submitUrl -JsonBody $json1 -Jwt $jwt

if ($result1.Success) {
    Write-Host "SUCCESS: $($result1.Data.message)" -ForegroundColor Green
    Write-Host "Place ID: $($result1.Data.place_id)" -ForegroundColor Gray
} else {
    Write-Host "FAILED: $($result1.Error)" -ForegroundColor Red
}

# Test 2: Japanese name (つじ田)
Write-Host "`n--- Test 2: Japanese name + GPS ---" -ForegroundColor Cyan
$json2 = '{"name_ja":"つじ田","lat":35.6595,"lng":139.7005}'
Write-Host "Sending JSON: $json2" -ForegroundColor Gray
Write-Host "UTF-8 bytes: $([System.BitConverter]::ToString([System.Text.Encoding]::UTF8.GetBytes($json2)))" -ForegroundColor DarkGray

$result2 = Invoke-UTF8Request -Url $submitUrl -JsonBody $json2 -Jwt $jwt

if ($result2.Success) {
    Write-Host "SUCCESS: $($result2.Data.message)" -ForegroundColor Green
    Write-Host "Place ID: $($result2.Data.place_id)" -ForegroundColor Gray
} else {
    Write-Host "FAILED: $($result2.Error)" -ForegroundColor Red
}

# Test 3: Chinese name (辻田)
Write-Host "`n--- Test 3: Chinese name + GPS ---" -ForegroundColor Cyan
$json3 = '{"name_zh":"辻田","lat":35.6596,"lng":139.7006}'
Write-Host "Sending JSON: $json3" -ForegroundColor Gray

$result3 = Invoke-UTF8Request -Url $submitUrl -JsonBody $json3 -Jwt $jwt

if ($result3.Success) {
    Write-Host "SUCCESS: $($result3.Data.message)" -ForegroundColor Green
    Write-Host "Place ID: $($result3.Data.place_id)" -ForegroundColor Gray
} else {
    Write-Host "FAILED: $($result3.Error)" -ForegroundColor Red
}

# Test 4: All three names
Write-Host "`n--- Test 4: Trilingual (EN + JA + ZH) ---" -ForegroundColor Cyan
$json4 = '{"name_en":"Tsujita LA Artisan Noodle","name_ja":"つじ田","name_zh":"辻田","city":"Tokyo","ward":"Shibuya","lat":35.6597,"lng":139.7007,"categories":["ramen","noodles"],"price_level":2}'

$result4 = Invoke-UTF8Request -Url $submitUrl -JsonBody $json4 -Jwt $jwt

if ($result4.Success) {
    Write-Host "SUCCESS: $($result4.Data.message)" -ForegroundColor Green
    Write-Host "Place ID: $($result4.Data.place_id)" -ForegroundColor Gray
} else {
    Write-Host "FAILED: $($result4.Error)" -ForegroundColor Red
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   VERIFICATION" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Start-Sleep -Seconds 2

# Fetch and verify the data
$baseRest = "https://$ProjectRef.supabase.co/rest/v1"
$restHeaders = @{
    "apikey" = $AnonKey
    "Authorization" = "Bearer $jwt"
}

$placesUrl = "$baseRest/places?select=id,name_en,name_ja,name_zh&created_by=eq.$userId&order=created_at.desc&limit=5"
$places = Invoke-RestMethod -Uri $placesUrl -Headers $restHeaders

Write-Host "`nRecent submissions:" -ForegroundColor Cyan
foreach ($place in $places) {
    Write-Host "`nPlace ID: $($place.id)" -ForegroundColor White
    
    if ($place.name_en) { 
        Write-Host "  EN: $($place.name_en)" -ForegroundColor Gray 
    }
    
    if ($place.name_ja) {
        $jaBytes = [System.Text.Encoding]::UTF8.GetBytes($place.name_ja)
        $jaHex = ($jaBytes | ForEach-Object { $_.ToString("X2") }) -join " "
        Write-Host "  JA: $($place.name_ja)" -ForegroundColor Gray
        Write-Host "      Bytes: $jaHex" -ForegroundColor DarkGray
        
        # Check if correct encoding
        $expectedBytes = "E3 81 A4 E3 81 98 E7 94 B0" # つじ田
        if ($jaHex -eq $expectedBytes) {
            Write-Host "      Status: CORRECT UTF-8 encoding!" -ForegroundColor Green
        } else {
            Write-Host "      Status: Wrong encoding (expected: $expectedBytes)" -ForegroundColor Red
        }
    }
    
    if ($place.name_zh) {
        $zhBytes = [System.Text.Encoding]::UTF8.GetBytes($place.name_zh)
        $zhHex = ($zhBytes | ForEach-Object { $_.ToString("X2") }) -join " "
        Write-Host "  ZH: $($place.name_zh)" -ForegroundColor Gray
        Write-Host "      Bytes: $zhHex" -ForegroundColor DarkGray
        
        # Check if correct encoding
        $expectedBytes = "E8 BE BB E7 94 B0" # 辻田
        if ($zhHex -eq $expectedBytes) {
            Write-Host "      Status: CORRECT UTF-8 encoding!" -ForegroundColor Green
        } else {
            Write-Host "      Status: Wrong encoding (expected: $expectedBytes)" -ForegroundColor Red
        }
    }
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   TEST COMPLETE" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta