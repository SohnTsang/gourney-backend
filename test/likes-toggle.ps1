# test-likes-toggle.ps1
# Test the likes toggle endpoint

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
$email = "testuser@example.com"
$password = "TestPass123!"

Write-Host "Authenticating..." -ForegroundColor Cyan
$authHeaders = @{ "apikey"=$anonKey; "Content-Type"="application/json" }
$authBody = @{ email=$email; password=$password } | ConvertTo-Json -Compress
$authUrl = "https://$projectRef.supabase.co/auth/v1/token?grant_type=password"
$auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody
$jwt = $auth.access_token

$baseFn = "https://$projectRef.supabase.co/functions/v1"
$headers = @{ 
    "apikey" = $anonKey
    "Authorization" = "Bearer $jwt"
    "X-API-Version" = "v1"
    "Content-Type" = "application/json"
}

$testVisitId = "eee15584-a02f-4af1-bc1c-adaa176f92af"

Write-Host "`n=== Testing Like Toggle ===" -ForegroundColor Yellow

# First toggle: Should LIKE
Write-Host "`n1. First toggle (should like)..." -ForegroundColor Cyan
try {
    $url = "$baseFn/likes-toggle?visit_id=$testVisitId"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST
    $r | ConvertTo-Json
    if ($r.liked -eq $true) {
        Write-Host "✓ Liked! Count: $($r.like_count)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Unexpected: unliked on first toggle" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Second toggle: Should UNLIKE
Write-Host "`n2. Second toggle (should unlike)..." -ForegroundColor Cyan
try {
    $url = "$baseFn/likes-toggle?visit_id=$testVisitId"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST
    $r | ConvertTo-Json
    if ($r.liked -eq $false) {
        Write-Host "✓ Unliked! Count: $($r.like_count)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Unexpected: liked on second toggle" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Third toggle: Should LIKE again
Write-Host "`n3. Third toggle (should like again)..." -ForegroundColor Cyan
try {
    $url = "$baseFn/likes-toggle?visit_id=$testVisitId"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST
    $r | ConvertTo-Json
    if ($r.liked -eq $true) {
        Write-Host "✓ Liked again! Count: $($r.like_count)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Unexpected: unliked on third toggle" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan