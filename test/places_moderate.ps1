# test_places_moderate.ps1
# Test admin moderation endpoint for user-submitted places

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$moderateUrl = "https://$ProjectRef.supabase.co/functions/v1/places-moderate"
$baseRest = "https://$ProjectRef.supabase.co/rest/v1"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   ADMIN MODERATION TEST" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Authenticate as admin
Write-Host "`n--- Authenticating admin ---" -ForegroundColor Cyan
$authBody = @{
    email = "admin@example.com"
    password = "admin123"  # Update this to your admin password
} | ConvertTo-Json

try {
    $auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    } -Body $authBody

    $jwt = $auth.access_token
    $adminId = $auth.user.id
    Write-Host "Authenticated as admin: $adminId" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Could not authenticate admin" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Please ensure admin@example.com exists with correct password" -ForegroundColor Yellow
    exit
}

$headers = @{
    "apikey" = $AnonKey
    "Authorization" = "Bearer $jwt"
    "Content-Type" = "application/json"
}

# Test 1: Get pending places
Write-Host "`n--- Test 1: Get pending places ---" -ForegroundColor Cyan

try {
    $getPendingUrl = "$moderateUrl`?status=pending&limit=10"
    Write-Host "Calling: $getPendingUrl" -ForegroundColor DarkGray
    
    $response = Invoke-RestMethod -Uri $getPendingUrl -Method GET -Headers $headers
    
    Write-Host "SUCCESS: Retrieved pending places" -ForegroundColor Green
    Write-Host "Count: $($response.count)" -ForegroundColor Gray
    
    if ($response.places -and $response.places.Count -gt 0) {
        Write-Host "`nPending Places:" -ForegroundColor Cyan
        
        $placeNum = 1
        foreach ($place in $response.places) {
            Write-Host "`n  [$placeNum] $($place.name_en)$($place.name_ja)" -ForegroundColor White
            Write-Host "      ID: $($place.id)" -ForegroundColor Gray
            Write-Host "      Location: $($place.city), $($place.ward)" -ForegroundColor Gray
            Write-Host "      Submitted by: $($place.created_by)" -ForegroundColor Gray
            Write-Host "      Submitted at: $($place.created_at)" -ForegroundColor Gray
            Write-Host "      Notes: $($place.submission_notes)" -ForegroundColor DarkGray
            $placeNum++
        }
        
        # Save first place for approval test
        $testPlace = $response.places[0]
    } else {
        Write-Host "No pending places found" -ForegroundColor Yellow
        Write-Host "Create a manual place first using visits-create-with-place" -ForegroundColor Yellow
        $testPlace = $null
    }
    
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

# Test 2: Approve a place (if one exists)
if ($testPlace) {
    Write-Host "`n--- Test 2: Approve place ---" -ForegroundColor Cyan
    Write-Host "Approving: $($testPlace.name_en)$($testPlace.name_ja)" -ForegroundColor Gray
    
    # Get user's points before approval
    $userId = $testPlace.created_by
    $getPointsUrl = "$baseRest/city_scores?select=lifetime_points&user_id=eq.$userId"

    try {
        $pointsBefore = Invoke-RestMethod -Uri $getPointsUrl -Headers $headers
        # Sum all cities' lifetime points
        $beforePoints = ($pointsBefore | Measure-Object -Property lifetime_points -Sum).Sum
        if ($beforePoints -eq $null) { $beforePoints = 0 }
    } catch {
        $beforePoints = 0
    }
    
    Write-Host "User points BEFORE: $beforePoints" -ForegroundColor Gray
    
    try {
        $approveBody = @{
            place_id = $testPlace.id
            action = "approve"
            admin_notes = "Looks good! Approved."
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $moderateUrl -Method POST -Headers $headers -Body $approveBody
        
        Write-Host "SUCCESS: Place approved" -ForegroundColor Green
        Write-Host "  Message: $($response.message)" -ForegroundColor Gray
        Write-Host "  New Status: $($response.new_status)" -ForegroundColor Gray
        Write-Host "  Points Awarded: $($response.points_awarded)" -ForegroundColor Cyan
        
        # Verify place status updated
        Start-Sleep -Seconds 1
        $checkPlaceUrl = "$baseRest/places?select=moderation_status,reviewed_by,reviewed_at&id=eq.$($testPlace.id)"
        $checkPlace = Invoke-RestMethod -Uri $checkPlaceUrl -Headers $headers
        
        if ($checkPlace.Count -gt 0) {
            Write-Host "`n  Verification:" -ForegroundColor Cyan
            Write-Host "    Status: $($checkPlace[0].moderation_status)" -ForegroundColor $(if ($checkPlace[0].moderation_status -eq 'approved') { 'Green' } else { 'Red' })
            Write-Host "    Reviewed by: $($checkPlace[0].reviewed_by)" -ForegroundColor Gray
            Write-Host "    Reviewed at: $($checkPlace[0].reviewed_at)" -ForegroundColor Gray
        }
        
        # Verify points updated
        Start-Sleep -Seconds 2  # Increased wait time for trigger
        try {
            $pointsAfter = Invoke-RestMethod -Uri $getPointsUrl -Headers $headers
            # Sum all cities' lifetime points
            $afterPoints = ($pointsAfter | Measure-Object -Property lifetime_points -Sum).Sum
            if ($afterPoints -eq $null) { $afterPoints = 0 }
        } catch {
            $afterPoints = $beforePoints
        }
        
        Write-Host "`n  Points Update:" -ForegroundColor Cyan
        Write-Host "    Before: $beforePoints" -ForegroundColor Gray
        Write-Host "    After: $afterPoints" -ForegroundColor Gray
        Write-Host "    Difference: +$(($afterPoints - $beforePoints))" -ForegroundColor $(if (($afterPoints - $beforePoints) -eq 3) { 'Green' } else { 'Red' })
        
        if (($afterPoints - $beforePoints) -eq 3) {
            Write-Host "    ✓ Correct: +3 bonus points awarded" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Expected +3 points" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response: $responseBody" -ForegroundColor Red
        }
    }
}

# Test 3: Try to approve already-approved place (should fail)
if ($testPlace) {
    Write-Host "`n--- Test 3: Try approving already-approved place ---" -ForegroundColor Cyan
    
    try {
        $approveBody = @{
            place_id = $testPlace.id
            action = "approve"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $moderateUrl -Method POST -Headers $headers -Body $approveBody
        Write-Host "✗ Should have returned 400" -ForegroundColor Red
        
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "✓ Got expected 400 Bad Request (already moderated)" -ForegroundColor Green
        } else {
            Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
    }
}

# Test 4: Non-admin access
Write-Host "`n--- Test 4: Non-admin access ---" -ForegroundColor Cyan

try {
    # Authenticate as regular user
    $userAuthBody = @{
        email = "testuser2@example.com"
        password = "TestPass123!"
    } | ConvertTo-Json
    
    $userAuth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    } -Body $userAuthBody
    
    $userHeaders = @{
        "apikey" = $AnonKey
        "Authorization" = "Bearer $($userAuth.access_token)"
        "Content-Type" = "application/json"
    }
    
    $testUrl = "$moderateUrl`?status=pending"
    $response = Invoke-RestMethod -Uri $testUrl -Method GET -Headers $userHeaders
    Write-Host "✗ Should have returned 403" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 403) {
        Write-Host "✓ Got expected 403 Forbidden (admin only)" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   TEST SUMMARY" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`nModeration Flow:" -ForegroundColor Yellow
Write-Host "  1. User submits manual place → status='pending'" -ForegroundColor White
Write-Host "  2. Admin views pending places" -ForegroundColor White
Write-Host "  3. Admin approves → status='approved' + user gets +3 points" -ForegroundColor White
Write-Host "  4. Admin rejects → status='rejected' (no points)" -ForegroundColor White

Write-Host "`nExpected Behavior:" -ForegroundColor Yellow
Write-Host "  Test 1: Lists pending places" -ForegroundColor White
Write-Host "  Test 2: Approves place + awards +3 points" -ForegroundColor White
Write-Host "  Test 3: Rejects double-approval (400)" -ForegroundColor White
Write-Host "  Test 4: Blocks non-admin access (403)" -ForegroundColor White

Write-Host "`nPoints System:" -ForegroundColor Yellow
Write-Host "  Manual place submission: +2 immediate" -ForegroundColor White
Write-Host "  Admin approval: +3 bonus (total +5)" -ForegroundColor White
Write-Host "  Trigger: award_ugc_place_points (automatic)" -ForegroundColor White