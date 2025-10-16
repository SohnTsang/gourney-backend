# Test POST /v1/lists-create

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

function Get-FreshToken($email) {
    $body = @{ email = $email; password = "TestPass123!" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
        -Method POST -Headers @{"apikey"=$anonKey;"Content-Type"="application/json"} -Body $body
    return $response.access_token
}

Write-Host "`n=== Testing POST /v1/lists-create ===" -ForegroundColor Cyan

$token1 = Get-FreshToken "testuser@example.com"
Write-Host "✓ Token obtained`n" -ForegroundColor Green

# TEST 1: Create public list
Write-Host "TEST 1: Create public list" -ForegroundColor Yellow
try {
    $body = @{
        title = "My Favorite Cafes"
        description = "Cozy cafes in Tokyo"
        visibility = "public"
    } | ConvertTo-Json

    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body

    Write-Host "✅ PASS - List created (201)" -ForegroundColor Green
    Write-Host "   List ID: $($result.id)" -ForegroundColor Gray
    Write-Host "   Title: '$($result.title)'" -ForegroundColor Gray
    Write-Host "   Visibility: $($result.visibility)" -ForegroundColor Gray
    Write-Host "   is_system: $($result.is_system)`n" -ForegroundColor Gray
} catch {
    Write-Host "❌ FAIL`n" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "   Error: $($reader.ReadToEnd())`n" -ForegroundColor Yellow
}

# TEST 2: Create private list
Write-Host "TEST 2: Create private list" -ForegroundColor Yellow
try {
    $body = @{
        title = "Secret Spots"
        visibility = "private"
    } | ConvertTo-Json

    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body

    Write-Host "✅ PASS" -ForegroundColor Green
    Write-Host "   Title: '$($result.title)'" -ForegroundColor Gray
    Write-Host "   Visibility: $($result.visibility)" -ForegroundColor Gray
    Write-Host "   Description: $($result.description) (null - not provided)`n" -ForegroundColor Gray
} catch {
    Write-Host "❌ FAIL`n" -ForegroundColor Red
}

# TEST 3: Missing title (should 400)
Write-Host "TEST 3: Missing title (should 400)" -ForegroundColor Yellow
try {
    $body = @{ visibility = "public" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL - Should return 400`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "✅ PASS - Validation error (400)`n" -ForegroundColor Green
    }
}

# TEST 4: Title too long (should 400)
Write-Host "TEST 4: Title too long (should 400)" -ForegroundColor Yellow
try {
    $longTitle = "A" * 101
    $body = @{ title = $longTitle; visibility = "public" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "✅ PASS - Validation error (400)`n" -ForegroundColor Green
    }
}

Write-Host "=== Step 4 Complete ===" -ForegroundColor Cyan
Write-Host "Press any key..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")