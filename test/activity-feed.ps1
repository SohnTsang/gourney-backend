# test-social-on-other-user.ps1
# Test commenting/liking on another user's visit

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
$email = "testuser@example.com"
$password = "TestPass123!"

Write-Host "Authenticating as testuser..." -ForegroundColor Cyan
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

# Use testuser2's visit
$testuser2VisitId = "eee15584-a02f-4af1-bc1c-adaa176f92af"

Write-Host "`n=== Testing Social Features on testuser2's Visit ===" -ForegroundColor Yellow
Write-Host "Visit ID: $testuser2VisitId" -ForegroundColor Cyan

# 1. Comment on testuser2's visit
Write-Host "`n1. Adding comment to testuser2's visit..." -ForegroundColor Yellow
try {
    $body = @{ comment_text = "Great recommendation! I need to try this place." } | ConvertTo-Json
    $url = "$baseFn/comments-create?visit_id=$testuser2VisitId"
    Write-Host "POST $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $body
    $commentId = $r.id
    Write-Host "✓ Comment created: $commentId" -ForegroundColor Green
    $r | ConvertTo-Json
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

# 2. Like testuser2's visit
Write-Host "`n2. Liking testuser2's visit..." -ForegroundColor Yellow
try {
    $url = "$baseFn/likes-create?visit_id=$testuser2VisitId"
    Write-Host "POST $url"
    $r = Invoke-RestMethod -Uri $url -Headers $headers -Method POST
    Write-Host "✓ Like created, total likes: $($r.like_count)" -ForegroundColor Green
    $r | ConvertTo-Json
} catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

# 3. Wait for triggers to fire
Write-Host "`nWaiting 2 seconds for triggers to fire..." -ForegroundColor Cyan
Start-Sleep -Seconds 2

# 4. Check activity table for new entries
Write-Host "`n3. Checking activity table for new entries..." -ForegroundColor Yellow
try {
    $baseUrl = "https://$projectRef.supabase.co/rest/v1"
    $restHeaders = @{ 
        "apikey" = $anonKey
        "Authorization" = "Bearer $jwt"
        "Content-Type" = "application/json"
    }
    $url = "$baseUrl/activity?select=*&order=created_at.desc&limit=10"
    Write-Host "GET $url"
    $r = Invoke-RestMethod -Uri $url -Headers $restHeaders -Method GET
    
    $commentActivities = $r | Where-Object { $_.type -eq 'visit_comment' }
    $likeActivities = $r | Where-Object { $_.type -eq 'visit_like' }
    
    Write-Host "`nRecent activities:" -ForegroundColor Cyan
    $r | Select-Object -First 5 | ConvertTo-Json -Depth 3
    
    if ($commentActivities.Count -gt 0) {
        Write-Host "`n✓ Found $($commentActivities.Count) comment activities!" -ForegroundColor Green
        Write-Host "Comment activity details:" -ForegroundColor Cyan
        $commentActivities | Select-Object -First 1 | ConvertTo-Json -Depth 3
    } else {
        Write-Host "`n⚠ No comment activities found" -ForegroundColor Yellow
    }
    
    if ($likeActivities.Count -gt 0) {
        Write-Host "`n✓ Found $($likeActivities.Count) like activities!" -ForegroundColor Green
        Write-Host "Like activity details:" -ForegroundColor Cyan
        $likeActivities | Select-Object -First 1 | ConvertTo-Json -Depth 3
    } else {
        Write-Host "`n⚠ No like activities found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "✗ Failed to check activities: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Now check as testuser2 to see if they received the notifications
Write-Host "`n4. Switching to testuser2 to check their activity feed..." -ForegroundColor Yellow

$email2 = "testuser2@example.com"
$password2 = "TestPass123!"

try {
    $authBody2 = @{ email=$email2; password=$password2 } | ConvertTo-Json -Compress
    $auth2 = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody2
    $jwt2 = $auth2.access_token
    
    $headers2 = @{ 
        "apikey" = $anonKey
        "Authorization" = "Bearer $jwt2"
        "Content-Type" = "application/json"
    }
    
    # Call RPC function to get testuser2's activity feed
    $body = @{
        p_limit = 20
        p_cursor_created_at = $null
        p_cursor_id = $null
    } | ConvertTo-Json
    
    $url = "$baseUrl/rpc/get_activity_feed"
    Write-Host "POST $url (as testuser2)"
    $r = Invoke-RestMethod -Uri $url -Headers $headers2 -Method POST -Body $body
    
    $newActivities = $r | Where-Object { 
        $_.activity_type -eq 'visit_comment' -or $_.activity_type -eq 'visit_like' 
    }
    
    if ($newActivities.Count -gt 0) {
        Write-Host "`n✓✓✓ SUCCESS! testuser2 received $($newActivities.Count) new notifications!" -ForegroundColor Green
        Write-Host "`nNew activities in testuser2's feed:" -ForegroundColor Cyan
        $newActivities | ConvertTo-Json -Depth 5
    } else {
        Write-Host "`n⚠ No new activities in testuser2's feed" -ForegroundColor Yellow
        Write-Host "All activities:" -ForegroundColor Gray
        $r | Select-Object -First 3 | ConvertTo-Json -Depth 3
    }
    
} catch {
    Write-Host "✗ Failed to check testuser2's feed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan