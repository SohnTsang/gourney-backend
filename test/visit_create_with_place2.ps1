# test_apple_google_visit.ps1
# Test Apple + Google compliance

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$createVisitUrl = "https://$ProjectRef.supabase.co/functions/v1/visits-create-with-place"
$baseRest = "https://$ProjectRef.supabase.co/rest/v1"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   APPLE + GOOGLE COMPLIANCE TEST" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Authenticate
Write-Host "`n--- Authenticating ---" -ForegroundColor Cyan
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

$headers = @{
    "apikey" = $AnonKey
    "Authorization" = "Bearer $jwt"
    "Content-Type" = "application/json"
}

# ============================================
# TEST 1: APPLE MAPKIT (FULL STORAGE)
# ============================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "TEST 1: APPLE MAPKIT PLACE" -ForegroundColor Yellow
Write-Host "Expected: FULL data storage (compliant)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Yellow

$uniqueAppleId = "apple_test_" + (Get-Random -Minimum 10000 -Maximum 99999)

$appleAddress = "1-22-7 Jinnan, Shibuya-ku, Tokyo"

$visitBody = @{
    apple_place_data = @{
        apple_place_id = $uniqueAppleId
        name = "Ichiran Ramen Test"
        name_ja = "Ramen Test"
        address = $appleAddress
        city = "Tokyo"
        ward = "Shibuya"
        lat = 35.6595
        lng = 139.7004
        phone = "+81-3-1234-5678"
        website = "https://test.com"
        categories = @("ramen")
    }
    rating = 5
    comment = "Apple Maps test"
    visibility = "public"
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
    
    Write-Host "SUCCESS: Visit created" -ForegroundColor Green
    Write-Host "  Visit ID: $($response.visit_id)" -ForegroundColor Gray
    Write-Host "  Place ID: $($response.place_id)" -ForegroundColor Gray
    Write-Host "  Created New: $($response.created_new_place)" -ForegroundColor Gray
    Write-Host "  Points: $($response.points_earned)" -ForegroundColor Cyan
    
    if ($response.points_earned -eq 5) {
        Write-Host "  PASS: 5 points earned (2+3 bonus)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Expected 5 points, got $($response.points_earned)" -ForegroundColor Red
    }
    
    # Verify stored data
    Start-Sleep -Seconds 1
    $checkUrl = "$baseRest/places?select=provider,apple_place_id,name_en,name_ja,formatted_address,moderation_status&id=eq.$($response.place_id)"
    $place = Invoke-RestMethod -Uri $checkUrl -Headers $headers
    
    if ($place -and $place.Count -gt 0) {
        $p = $place[0]
        Write-Host "`nVerifying Apple place:" -ForegroundColor Cyan
        Write-Host "  Provider: $($p.provider)" -ForegroundColor Gray
        Write-Host "  Name EN: $($p.name_en)" -ForegroundColor Gray
        Write-Host "  Name JA: $($p.name_ja)" -ForegroundColor Gray
        Write-Host "  Address: $($p.formatted_address)" -ForegroundColor Gray
        Write-Host "  Status: $($p.moderation_status)" -ForegroundColor Gray
        
        $passCount = 0
        $failCount = 0
        
        if ($p.provider -eq 'apple') {
            Write-Host "  PASS: Provider is apple" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Provider should be apple" -ForegroundColor Red
            $failCount++
        }
        
        if ($p.name_en -and $p.formatted_address) {
            Write-Host "  PASS: FULL data stored (compliant)" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Data missing" -ForegroundColor Red
            $failCount++
        }
        
        if ($p.moderation_status -eq 'approved') {
            Write-Host "  PASS: Auto-approved" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Should be approved" -ForegroundColor Red
            $failCount++
        }
        
        Write-Host "`nApple Test: $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
    }
    
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================
# TEST 2: GOOGLE PLACES (STUB ONLY)
# ============================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "TEST 2: GOOGLE PLACES API STUB" -ForegroundColor Yellow
Write-Host "Expected: STUB only (place_id + lat/lng)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Yellow

$uniqueGoogleId = "ChIJTest_" + (Get-Random -Minimum 10000 -Maximum 99999)

$visitBody = @{
    google_place_data = @{
        google_place_id = $uniqueGoogleId
        lat = 35.6812
        lng = 139.7671
    }
    rating = 4
    comment = "Google test"
    visibility = "public"
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
    
    Write-Host "SUCCESS: Visit created" -ForegroundColor Green
    Write-Host "  Visit ID: $($response.visit_id)" -ForegroundColor Gray
    Write-Host "  Place ID: $($response.place_id)" -ForegroundColor Gray
    Write-Host "  Created New: $($response.created_new_place)" -ForegroundColor Gray
    Write-Host "  Points: $($response.points_earned)" -ForegroundColor Cyan
    
    if ($response.points_earned -eq 2) {
        Write-Host "  PASS: 2 points (pending approval)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: Expected 2 points, got $($response.points_earned)" -ForegroundColor Red
    }
    
    # Verify stored as stub
    Start-Sleep -Seconds 1
    $checkUrl = "$baseRest/places?select=provider,google_place_id,name_en,name_ja,formatted_address,lat,lng,moderation_status&id=eq.$($response.place_id)"
    $place = Invoke-RestMethod -Uri $checkUrl -Headers $headers
    
    if ($place -and $place.Count -gt 0) {
        $p = $place[0]
        Write-Host "`nVerifying Google stub:" -ForegroundColor Cyan
        Write-Host "  Provider: $($p.provider)" -ForegroundColor Gray
        Write-Host "  Name EN: $($p.name_en)" -ForegroundColor Gray
        Write-Host "  Name JA: $($p.name_ja)" -ForegroundColor Gray
        Write-Host "  Address: $($p.formatted_address)" -ForegroundColor Gray
        Write-Host "  Lat/Lng: $($p.lat), $($p.lng)" -ForegroundColor Gray
        Write-Host "  Status: $($p.moderation_status)" -ForegroundColor Gray
        
        $passCount = 0
        $failCount = 0
        
        if ($p.provider -eq 'google') {
            Write-Host "  PASS: Provider is google" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Provider should be google" -ForegroundColor Red
            $failCount++
        }
        
        if (-not $p.name_en -and -not $p.name_ja -and -not $p.formatted_address) {
            Write-Host "  PASS: STUB only (no name/address - COMPLIANT)" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: COMPLIANCE VIOLATION - Full data stored" -ForegroundColor Red
            $failCount++
        }
        
        if ($p.lat -and $p.lng) {
            Write-Host "  PASS: Lat/Lng stored (allowed)" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Lat/Lng missing" -ForegroundColor Red
            $failCount++
        }
        
        if ($p.moderation_status -eq 'pending') {
            Write-Host "  PASS: Status is pending" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "  FAIL: Should be pending" -ForegroundColor Red
            $failCount++
        }
        
        Write-Host "`nGoogle Test: $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
    }
    
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# ============================================
# SUMMARY
# ============================================
Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   COMPLIANCE TEST COMPLETE" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`nApple MapKit:" -ForegroundColor Yellow
Write-Host "  - Full data storage: ALLOWED" -ForegroundColor Green
Write-Host "  - Status: approved" -ForegroundColor Green
Write-Host "  - Points: 5 (immediate bonus)" -ForegroundColor Green

Write-Host "`nGoogle Places:" -ForegroundColor Yellow
Write-Host "  - Stub only (place_id + lat/lng): COMPLIANT" -ForegroundColor Green
Write-Host "  - Status: pending (admin review)" -ForegroundColor Green
Write-Host "  - Points: 2 (bonus after review)" -ForegroundColor Green

Write-Host "`nACTION REQUIRED:" -ForegroundColor Magenta
Write-Host "  Display 'Powered by Apple' in iOS UI" -ForegroundColor Yellow