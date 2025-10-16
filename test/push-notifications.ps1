# push-notifications-debug.ps1
# Debug version to find the auth issue

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

$authUrl = "https://$projectRef.supabase.co/auth/v1/token?grant_type=password"
$baseUrl = "https://$projectRef.supabase.co/rest/v1"

Write-Host "=== Debug Authentication ===" -ForegroundColor Cyan

# Authenticate as testuser2
$email2 = "testuser2@example.com"
$password2 = "TestPass123!"

Write-Host "`n1. Authenticating as testuser2..." -ForegroundColor Yellow
$authHeaders = @{ 
    "apikey" = $anonKey
    "Content-Type" = "application/json" 
}
$authBody = @{ 
    email = $email2
    password = $password2 
} | ConvertTo-Json

try {
    Write-Host "POST $authUrl" -ForegroundColor Gray
    Write-Host "Body: $authBody" -ForegroundColor Gray
    
    $auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody
    $jwt = $auth.access_token
    
    Write-Host "✓ Auth successful" -ForegroundColor Green
    Write-Host "  Access Token: $($jwt.Substring(0, 50))..." -ForegroundColor Gray
    Write-Host "  User ID: $($auth.user.id)" -ForegroundColor Gray
    Write-Host "  Email: $($auth.user.email)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Auth failed: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# Test 1: Can we query the database with this token?
Write-Host "`n2. Testing database access with JWT..." -ForegroundColor Yellow

$restHeaders = @{ 
    "apikey" = $anonKey
    "Authorization" = "Bearer $jwt"
    "Content-Type" = "application/json"
}

try {
    $url = "$baseUrl/users?select=id,handle&limit=1"
    Write-Host "GET $url" -ForegroundColor Gray
    $result = Invoke-RestMethod -Uri $url -Headers $restHeaders -Method GET
    Write-Host "✓ Database access works" -ForegroundColor Green
    $result | ConvertTo-Json
} catch {
    Write-Host "✗ Database access failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Can we call a working Edge Function?
Write-Host "`n3. Testing Edge Function with JWT (comments-list)..." -ForegroundColor Yellow

$baseFn = "https://$projectRef.supabase.co/functions/v1"
$fnHeaders = @{ 
    "apikey" = $anonKey
    "Authorization" = "Bearer $jwt"
    "X-API-Version" = "v1"
    "Content-Type" = "application/json"
}

try {
    $testVisitId = "eee15584-a02f-4af1-bc1c-adaa176f92af"
    $url = "$baseFn/comments-list?visit_id=$testVisitId&limit=1"
    Write-Host "GET $url" -ForegroundColor Gray
    Write-Host "Headers:" -ForegroundColor Gray
    Write-Host "  apikey: $($anonKey.Substring(0, 20))..." -ForegroundColor Gray
    Write-Host "  Authorization: Bearer $($jwt.Substring(0, 20))..." -ForegroundColor Gray
    Write-Host "  X-API-Version: v1" -ForegroundColor Gray
    
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "✓ Edge Function works!" -ForegroundColor Green
    $result | ConvertTo-Json
} catch {
    Write-Host "✗ Edge Function failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

# Test 3: Try device-register with same headers
Write-Host "`n4. Testing device-register with same auth..." -ForegroundColor Yellow

$testApnsToken = -join ((0..63) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })

try {
    $deviceBody = @{
        apns_token = $testApnsToken
        locale = "ja-JP"
        timezone = "Asia/Tokyo"
        environment = "dev"
    } | ConvertTo-Json

    $url = "$baseFn/device-register"
    Write-Host "POST $url" -ForegroundColor Gray
    Write-Host "Body: $deviceBody" -ForegroundColor Gray
    Write-Host "Headers:" -ForegroundColor Gray
    Write-Host "  apikey: $($anonKey.Substring(0, 20))..." -ForegroundColor Gray
    Write-Host "  Authorization: Bearer $($jwt.Substring(0, 20))..." -ForegroundColor Gray
    Write-Host "  X-API-Version: v1" -ForegroundColor Gray
    
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method POST -Body $deviceBody
    Write-Host "✓ device-register works!" -ForegroundColor Green
    $result | ConvertTo-Json -Depth 3
} catch {
    Write-Host "✗ device-register failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

Write-Host "`n=== Debug Complete ===" -ForegroundColor Cyan