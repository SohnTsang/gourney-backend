# test-social-functions.ps1
# Test all social engagement endpoints

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
$email = "testuser@example.com"
$password = "TestPass123!"

# Auth
Write-Host "Authenticating..." -ForegroundColor Cyan
$authHeaders = @{ "apikey"=$anonKey; "Content-Type"="application/json" }
$authBody = @{ email=$email; password=$password } | ConvertTo-Json -Compress
$authUrl = "https://$projectRef.supabase.co/auth/v1/token?grant_type=password"
$auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody
$jwt = $auth.access_token

$baseFn = "https://$projectRef.supabase.co/functions/v1"
$headers = @{ "apikey"=$anonKey; "Authorization"="Bearer $jwt"; "X-API-Version"="v1"; "Content-Type"="application/json" }

Add-Type -AssemblyName System.Web
function Encode([string]$s) { [System.Web.HttpUtility]::UrlEncode($s) }

# === TEST 1: Create a comment ===
Write-Host "`n=== TEST 1: Create Comment ===" -ForegroundColor Yellow

# You need to replace this with a real visit_id from your database
$testVisitId = "eee15584-a02f-4af1-bc1c-adaa176f92af"

$commentBody = @{
    comment_text = "This place looks amazing! Can't wait to try it."
} | ConvertTo-Json

try {
    $url = "$baseFn/comments-create?visit_id=$testVisitId"
    Write-Host "POST $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $commentBody
    $r | ConvertTo-Json
    $commentId = $r.id
    Write-Host "✓ Comment created: $commentId" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# === TEST 2: List comments ===
Write-Host "`n=== TEST 2: List Comments ===" -ForegroundColor Yellow

try {
    $url = "$baseFn/comments-list?visit_id=$testVisitId&limit=10"
    Write-Host "GET $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
    $r | ConvertTo-Json
    Write-Host "✓ Found $($r.comment_count) comments" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# === TEST 3: Create a like ===
Write-Host "`n=== TEST 3: Create Like ===" -ForegroundColor Yellow

try {
    $url = "$baseFn/likes-create?visit_id=$testVisitId"
    Write-Host "POST $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST
    $r | ConvertTo-Json
    Write-Host "✓ Like created, total: $($r.like_count)" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# === TEST 4: List likes ===
Write-Host "`n=== TEST 4: List Likes ===" -ForegroundColor Yellow

try {
    $url = "$baseFn/likes-list?visit_id=$testVisitId&limit=10"
    Write-Host "GET $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method GET
    $r | ConvertTo-Json
    Write-Host "✓ Found $($r.like_count) likes, has_liked: $($r.has_liked)" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# === TEST 5: Delete like ===
Write-Host "`n=== TEST 5: Delete Like ===" -ForegroundColor Yellow

try {
    $url = "$baseFn/likes-delete?visit_id=$testVisitId"
    Write-Host "DELETE $url"
    Invoke-RestMethod -Uri $url -Headers $headers -Method DELETE
    Write-Host "✓ Like deleted" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# === TEST 6: Delete comment ===
Write-Host "`n=== TEST 6: Delete Comment ===" -ForegroundColor Yellow

if ($commentId) {
    try {
        $url = "$baseFn/comments-delete?comment_id=$commentId"
        Write-Host "DELETE $url"
        Invoke-RestMethod -Uri $url -Headers $headers -Method DELETE
        Write-Host "✓ Comment deleted" -ForegroundColor Green
    } catch {
        Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "⊘ Skipped (no comment_id)" -ForegroundColor Gray
}

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Cyan