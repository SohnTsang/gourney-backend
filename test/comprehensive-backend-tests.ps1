# comprehensive-backend-tests.ps1
# Complete real-world user journey testing for the entire backend

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$baseRest = "https://$ProjectRef.supabase.co/rest/v1"
$baseFn = "https://$ProjectRef.supabase.co/functions/v1"

$testResults = @{
    Passed = 0
    Failed = 0
    Skipped = 0
}

function Test-Endpoint {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    Write-Host "`n--- $Name ---" -ForegroundColor Cyan
    try {
        & $Test
        $script:testResults.Passed++
        Write-Host "PASSED" -ForegroundColor Green
        return $true
    } catch {
        $script:testResults.Failed++
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $reader.BaseStream.Position = 0
                $responseBody = $reader.ReadToEnd()
                Write-Host "Response: $responseBody" -ForegroundColor Red
            } catch {}
        }
        return $false
    }
}

function Get-AuthHeaders {
    param([string]$JWT)
    return @{
        "apikey" = $AnonKey
        "Authorization" = "Bearer $JWT"
        "X-API-Version" = "v1"
        "Content-Type" = "application/json"
    }
}

function Get-AnonHeaders {
    return @{
        "apikey" = $AnonKey
        "X-API-Version" = "v1"
        "Content-Type" = "application/json"
    }
}

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   COMPREHENSIVE BACKEND TEST SUITE" -ForegroundColor Magenta
Write-Host "   Real-World User Journey Testing" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO 1: New User Onboarding Journey" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$user1JWT = $null
$user1Handle = $null
$user1Id = $null

Test-Endpoint "1.1: User Authentication (testuser)" {
    $authBody = @{
        email = "testuser@example.com"
        password = "TestPass123!"
    } | ConvertTo-Json
    
    $auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    } -Body $authBody
    
    $script:user1JWT = $auth.access_token
    $script:user1Id = $auth.user.id
    
    $userInfoUrl = "$baseRest/users?select=handle&id=eq.$($script:user1Id)"
    $userInfo = Invoke-RestMethod -Uri $userInfoUrl -Headers @{
        "apikey" = $AnonKey
        "Authorization" = "Bearer $($script:user1JWT)"
    }
    $script:user1Handle = $userInfo[0].handle
    
    Write-Host "  User ID: $($script:user1Id)" -ForegroundColor Gray
    Write-Host "  Handle: $($script:user1Handle)" -ForegroundColor Gray
    
    if (-not $script:user1JWT) { throw "No JWT token received" }
}

Test-Endpoint "1.2: View Own Profile" {
    $headers = Get-AuthHeaders $user1JWT
    $profile = Invoke-RestMethod -Uri "$baseFn/user-profile?handle=$user1Handle" -Headers $headers
    
    Write-Host "  Display Name: $($profile.display_name)" -ForegroundColor Gray
    Write-Host "  Visits: $($profile.visit_count)" -ForegroundColor Gray
    Write-Host "  Lists: $($profile.list_count)" -ForegroundColor Gray
    Write-Host "  Relationship: $($profile.relationship)" -ForegroundColor Gray
    
    if ($profile.relationship -ne "self") { throw "Expected relationship 'self'" }
}

Test-Endpoint "1.3: Search for Users" {
    $headers = Get-AuthHeaders $user1JWT
    $searchUrl = "$baseFn/user-search?q=test&limit=10"
    $results = Invoke-RestMethod -Uri $searchUrl -Headers $headers
    
    Write-Host "  Found $($results.total_count) users" -ForegroundColor Gray
    if ($results.total_count -gt 0) {
        Write-Host "  First result: $($results.users[0].handle)" -ForegroundColor Gray
    }
    
    if ($results.total_count -eq 0) { throw "Expected some search results" }
}

Test-Endpoint "1.4: Get Suggested Follows" {
    $headers = Get-AuthHeaders $user1JWT
    $suggestions = Invoke-RestMethod -Uri "$baseFn/suggested-follows?limit=10" -Headers $headers
    
    Write-Host "  Got $($suggestions.suggestions.Count) suggestions" -ForegroundColor Gray
}

Test-Endpoint "1.5: Anonymous User Can View Public Profiles" {
    $headers = Get-AnonHeaders
    $profile = Invoke-RestMethod -Uri "$baseFn/user-profile?handle=$user1Handle" -Headers $headers
    
    Write-Host "  Viewing $($profile.handle) as anonymous" -ForegroundColor Gray
    Write-Host "  Relationship: $($profile.relationship)" -ForegroundColor Gray
    
    if ($profile.relationship -ne "stranger") { throw "Expected 'stranger' for anonymous viewer" }
}

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO 2: Discovering Places to Visit" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$testPlaceId = $null

Test-Endpoint "2.1: Search Places by Name" {
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        q = "ramen"
        limit = 10
    } | ConvertTo-Json
    
    $results = Invoke-RestMethod -Uri "$baseFn/places-search" -Method POST -Headers $headers -Body $body
    
    Write-Host "  Found $($results.places.Count) places" -ForegroundColor Gray
    if ($results.places.Count -gt 0) {
        $script:testPlaceId = $results.places[0].id
        Write-Host "  First: $($results.places[0].name_en)" -ForegroundColor Gray
    }
    
    if ($results.places.Count -eq 0) { throw "Expected at least 1 ramen place" }
}

Test-Endpoint "2.2: Search Places with Filters (open_now)" {
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        q = ""
        open_now = $true
        limit = 10
    } | ConvertTo-Json
    
    $results = Invoke-RestMethod -Uri "$baseFn/places-search" -Method POST -Headers $headers -Body $body
    
    Write-Host "  Found $($results.places.Count) open places" -ForegroundColor Gray
}

Test-Endpoint "2.3: Get Place Details" {
    if (-not $testPlaceId) {
        Write-Host "  Skipped: No place ID from search" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $place = Invoke-RestMethod -Uri "$baseFn/places-get?id=$testPlaceId" -Headers $headers
    
    Write-Host "  Place: $($place.place.name_en)" -ForegroundColor Gray
    Write-Host "  City: $($place.place.city)" -ForegroundColor Gray
}

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO 3: Adding a Visit with Photos and Rating" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$newVisitId = $null

Test-Endpoint "3.1: Create Visit with Rating and Comment" {
    if (-not $testPlaceId) {
        Write-Host "  Skipped: No place ID" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        place_id = $testPlaceId
        rating = 5
        comment = "Amazing food! Highly recommend the spicy ramen."
        photo_urls = @()
        visibility = "public"
        visited_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    } | ConvertTo-Json
    
    $visit = Invoke-RestMethod -Uri "$baseFn/visits-create" -Method POST -Headers $headers -Body $body
    
    $script:newVisitId = $visit.id
    Write-Host "  Created visit: $($visit.id)" -ForegroundColor Gray
    Write-Host "  Rating: $($visit.rating)/5" -ForegroundColor Gray
    
    if (-not $visit.id) { throw "No visit ID returned" }
}

Test-Endpoint "3.2: Update Visit" {
    if (-not $newVisitId) {
        Write-Host "  Skipped: No visit created" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        rating = 4
        comment = "Actually, 4 stars is more accurate. Still great!"
    } | ConvertTo-Json
    
    $updateUrl = "$baseFn/visits-update?visit_id=$newVisitId"
    $updated = Invoke-RestMethod -Uri $updateUrl -Method PATCH -Headers $headers -Body $body
    
    Write-Host "  Updated rating to: $($updated.rating)/5" -ForegroundColor Gray
    
    if ($updated.rating -ne 4) { throw "Rating not updated" }
}

Test-Endpoint "3.3: View Own Visits" {
    $headers = Get-AuthHeaders $user1JWT
    $visitsUrl = "$baseFn/visits-history?handle=$user1Handle&limit=10"
    $visits = Invoke-RestMethod -Uri $visitsUrl -Headers $headers
    
    Write-Host "  Found $($visits.visits.Count) visits" -ForegroundColor Gray
    
    if ($visits.visits.Count -eq 0) { throw "Expected at least 1 visit" }
}

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO 4: Organizing Places into Lists" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$newListId = $null

Test-Endpoint "4.1: Create Custom List" {
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        title = "Best Ramen in Tokyo"
        description = "My personal favorite ramen spots"
        visibility = "public"
    } | ConvertTo-Json
    
    $list = Invoke-RestMethod -Uri "$baseFn/lists-create" -Method POST -Headers $headers -Body $body
    
    $script:newListId = $list.id
    Write-Host "  Created list: $($list.title)" -ForegroundColor Gray
    
    if (-not $list.id) { throw "No list ID returned" }
}

Test-Endpoint "4.2: Add Place to List" {
    if (-not $newListId -or -not $testPlaceId) {
        Write-Host "  Skipped: Missing list or place ID" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $body = @{
        place_id = $testPlaceId
        note = "Must try the tonkotsu!"
    } | ConvertTo-Json
    
    # FIXED: Use query parameter instead of path
    $addUrl = "$baseFn/lists-add-item?list_id=$newListId"
    $item = Invoke-RestMethod -Uri $addUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "  Added place to list" -ForegroundColor Gray
}

Test-Endpoint "4.3: View List with Items" {
    if (-not $newListId) {
        Write-Host "  Skipped: No list created" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    # FIXED: Use lists-detail to view a single list with items
    $listUrl = "$baseFn/lists-detail/$newListId"
    $list = Invoke-RestMethod -Uri $listUrl -Headers $headers
    
    Write-Host "  List: $($list.list.title)" -ForegroundColor Gray
    Write-Host "  Items: $($list.items.Count)" -ForegroundColor Gray
    
    if ($list.items.Count -eq 0) { throw "Expected at least 1 item in list" }
}

Test-Endpoint "4.4: Get All User Lists" {
    $headers = Get-AuthHeaders $user1JWT
    $lists = Invoke-RestMethod -Uri "$baseFn/lists-list?limit=20" -Headers $headers
    
    Write-Host "  Total lists: $($lists.lists.Count)" -ForegroundColor Gray
}

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO 5: Social Engagement" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

$user2JWT = $null

Test-Endpoint "5.1: Authenticate Second User (testuser2)" {
    $authBody = @{
        email = "testuser2@example.com"
        password = "TestPass123!"
    } | ConvertTo-Json
    
    $auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    } -Body $authBody
    
    $script:user2JWT = $auth.access_token
    Write-Host "  User 2 authenticated" -ForegroundColor Gray
}

Test-Endpoint "5.2: User 2 Likes User 1 Visit" {
    if (-not $newVisitId -or -not $user2JWT) {
        Write-Host "  Skipped: Missing visit or user 2" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user2JWT
    $toggleUrl = "$baseFn/likes-toggle?visit_id=$newVisitId"
    $result = Invoke-RestMethod -Uri $toggleUrl -Method POST -Headers $headers
    
    Write-Host "  Like toggled" -ForegroundColor Gray
}

Test-Endpoint "5.3: User 2 Comments on User 1 Visit" {
    if (-not $newVisitId -or -not $user2JWT) {
        Write-Host "  Skipped: Missing visit or user 2" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user2JWT
    $body = @{
        comment_text = "I love this place too! Their broth is incredible."
    } | ConvertTo-Json
    
    $commentUrl = "$baseFn/comments-create?visit_id=$newVisitId"
    $comment = Invoke-RestMethod -Uri $commentUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "  Comment posted" -ForegroundColor Gray
}

Test-Endpoint "5.4: View Comments on Visit" {
    if (-not $newVisitId) {
        Write-Host "  Skipped: No visit" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $commentsUrl = "$baseFn/comments-list?visit_id=$newVisitId&limit=20"
    $comments = Invoke-RestMethod -Uri $commentsUrl -Headers $headers
    
    Write-Host "  Comments: $($comments.comments.Count)" -ForegroundColor Gray
}

Test-Endpoint "5.5: View Likes on Visit" {
    if (-not $newVisitId) {
        Write-Host "  Skipped: No visit" -ForegroundColor Yellow
        $script:testResults.Skipped++
        return
    }
    
    $headers = Get-AuthHeaders $user1JWT
    $likesUrl = "$baseFn/likes-list?visit_id=$newVisitId&limit=20"
    $likes = Invoke-RestMethod -Uri $likesUrl -Headers $headers
    
    Write-Host "  Likes: $($likes.likes.Count)" -ForegroundColor Gray
    Write-Host "  Total: $($likes.like_count)" -ForegroundColor Gray
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "TEST RESULTS SUMMARY" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

$total = $testResults.Passed + $testResults.Failed + $testResults.Skipped
$passRate = if ($total -gt 0) { [math]::Round(($testResults.Passed / $total) * 100, 1) } else { 0 }

Write-Host "`nTotal Tests: $total" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($testResults.Skipped)" -ForegroundColor Yellow
Write-Host "`nPass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })

if ($testResults.Failed -eq 0) {
    Write-Host "`nALL TESTS PASSED! Backend is ready!" -ForegroundColor Green
} else {
    Write-Host "`nSome tests failed. Review errors above." -ForegroundColor Yellow
}

Write-Host "`n============================================================" -ForegroundColor Magenta