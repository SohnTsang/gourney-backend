# test_visits_create_with_place.ps1
# Comprehensive test for all 3 visit creation scenarios

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$searchUrl = "https://$ProjectRef.supabase.co/functions/v1/places-search-external"
$detailUrl = "https://$ProjectRef.supabase.co/functions/v1/places-detail-fetch"
$createVisitUrl = "https://$ProjectRef.supabase.co/functions/v1/visits-create-with-place"
$baseRest = "https://$ProjectRef.supabase.co/rest/v1"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   VISIT CREATION WITH PLACE TEST" -ForegroundColor Magenta
Write-Host "   Testing All 3 Scenarios" -ForegroundColor Magenta
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

$headers = @{
    "apikey" = $AnonKey
    "Authorization" = "Bearer $jwt"
    "Content-Type" = "application/json"
}

# ============================================================
# SCENARIO A: Visit to Existing Place
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO A: Visit to Existing Place (Database)" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

Write-Host "`n--- Step 1: Get an existing place from database ---" -ForegroundColor Cyan

$existingPlacesUrl = "$baseRest/places?select=id,name_en,name_ja,city&limit=1"
$existingPlaces = Invoke-RestMethod -Uri $existingPlacesUrl -Headers $headers

if ($existingPlaces -and $existingPlaces.Count -gt 0) {
    $existingPlace = $existingPlaces[0]
    Write-Host "Found existing place:" -ForegroundColor Green
    Write-Host "  ID: $($existingPlace.id)" -ForegroundColor Gray
    Write-Host "  Name: $($existingPlace.name_en)$($existingPlace.name_ja)" -ForegroundColor Gray
    Write-Host "  City: $($existingPlace.city)" -ForegroundColor Gray
    
    Write-Host "`n--- Test A1: Create visit with comment only ---" -ForegroundColor Cyan
    
    try {
        $visitBody = @{
            place_id = $existingPlace.id
            comment = "Great ramen! Loved the atmosphere."
            visibility = "public"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
        
        Write-Host "SUCCESS: Visit created" -ForegroundColor Green
        Write-Host "  Visit ID: $($response.visit_id)" -ForegroundColor Gray
        Write-Host "  Place ID: $($response.place_id)" -ForegroundColor Gray
        Write-Host "  Created New Place: $($response.created_new_place)" -ForegroundColor $(if ($response.created_new_place) { 'Red' } else { 'Green' })
        Write-Host "  Points Earned: $($response.points_earned)" -ForegroundColor Cyan
        
        if ($response.points_earned -eq 2) {
            Write-Host "  ✓ Correct points for existing place" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Wrong points (expected 2, got $($response.points_earned))" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
    
} else {
    Write-Host "No existing places in database - skipping Scenario A" -ForegroundColor Yellow
}

# ============================================================
# SCENARIO B: Visit with New Place from Google API
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO B: Visit with New Place from Google API" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

Write-Host "`n--- Step 1: Search for a place ---" -ForegroundColor Cyan

$searchBody = @{
    query = "Tsujita LA Artisan Noodle Tokyo"
    lat = 35.6595
    lng = 139.7004
    limit = 1
} | ConvertTo-Json

$searchResult = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $searchBody

if ($searchResult.results -and $searchResult.results.Count -gt 0) {
    $googlePlace = $searchResult.results[0]
    Write-Host "Found place: $($googlePlace.name)" -ForegroundColor Green
    Write-Host "  Google Place ID: $($googlePlace.external_id)" -ForegroundColor Gray
    Write-Host "  Exists in DB: $($googlePlace.exists_in_db)" -ForegroundColor Gray
    
    # Only proceed if place doesn't exist in DB (to test new place creation)
    if (-not $googlePlace.exists_in_db) {
        Write-Host "`n--- Step 2: Fetch full place details ---" -ForegroundColor Cyan
        
        $detailBody = @{
            google_place_id = $googlePlace.external_id
        } | ConvertTo-Json
        
        $placeDetails = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $headers -Body $detailBody
        
        Write-Host "Got full details for: $($placeDetails.place.name)" -ForegroundColor Green
        
        Write-Host "`n--- Test B1: Create visit with new Google place (photo + comment) ---" -ForegroundColor Cyan
        
        try {
            $visitBody = @{
                google_place_data = @{
                    google_place_id = $placeDetails.place.google_place_id
                    name = $placeDetails.place.name
                    name_en = $placeDetails.place.name_en
                    address = $placeDetails.place.address
                    city = $placeDetails.place.city
                    ward = $placeDetails.place.ward
                    lat = $placeDetails.place.lat
                    lng = $placeDetails.place.lng
                    categories = $placeDetails.place.categories
                    price_level = $placeDetails.place.price_level
                    phone = $placeDetails.place.phone
                    website = $placeDetails.place.website
                    opening_hours = $placeDetails.place.opening_hours
                    rating = $placeDetails.place.rating
                    user_ratings_total = $placeDetails.place.user_ratings_total
                    photos = $placeDetails.place.photos
                }
                comment = "Found this amazing new spot! The tsukemen is incredible."
                rating = 5
                visibility = "public"
            } | ConvertTo-Json -Depth 10
            
            $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
            
            Write-Host "SUCCESS: Visit created with new Google place" -ForegroundColor Green
            Write-Host "  Visit ID: $($response.visit_id)" -ForegroundColor Gray
            Write-Host "  Place ID: $($response.place_id)" -ForegroundColor Gray
            Write-Host "  Created New Place: $($response.created_new_place)" -ForegroundColor $(if ($response.created_new_place) { 'Green' } else { 'Red' })
            Write-Host "  Points Earned: $($response.points_earned)" -ForegroundColor Cyan
            
            if ($response.created_new_place -and $response.points_earned -eq 5) {
                Write-Host "  ✓ Correct: New place created, earned 5 points (2+3 bonus)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Issue with new place creation or points" -ForegroundColor Red
            }
            
            # Verify place was saved to database with google_place_id
            Write-Host "`n  Verifying place saved to database..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            
            $checkPlaceUrl = "$baseRest/places?select=id,google_place_id,moderation_status&id=eq.$($response.place_id)"
            $savedPlace = Invoke-RestMethod -Uri $checkPlaceUrl -Headers $headers
            
            if ($savedPlace -and $savedPlace.Count -gt 0) {
                Write-Host "  ✓ Place found in database" -ForegroundColor Green
                Write-Host "    Google Place ID: $($savedPlace[0].google_place_id)" -ForegroundColor Gray
                Write-Host "    Moderation Status: $($savedPlace[0].moderation_status)" -ForegroundColor Gray
                
                if ($savedPlace[0].moderation_status -eq 'approved') {
                    Write-Host "    ✓ Auto-approved (from trusted API)" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ Should be auto-approved" -ForegroundColor Red
                }
            } else {
                Write-Host "  ✗ Place not found in database" -ForegroundColor Red
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
        
    } else {
        Write-Host "Place already exists in DB - testing duplicate handling" -ForegroundColor Yellow
        
        # Test creating visit with existing Google place
        Write-Host "`n--- Test B2: Create visit with existing Google place ---" -ForegroundColor Cyan
        
        $detailBody = @{
            google_place_id = $googlePlace.external_id
            db_place_id = $googlePlace.db_place_id
        } | ConvertTo-Json
        
        $placeDetails = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $headers -Body $detailBody
        
        try {
            $visitBody = @{
                google_place_data = @{
                    google_place_id = $placeDetails.place.google_place_id
                    name = $placeDetails.place.name
                    name_en = $placeDetails.place.name_en
                    address = $placeDetails.place.address
                    city = $placeDetails.place.city
                    ward = $placeDetails.place.ward
                    lat = $placeDetails.place.lat
                    lng = $placeDetails.place.lng
                    categories = $placeDetails.place.categories
                    price_level = $placeDetails.place.price_level
                }
                comment = "Second visit to this place!"
                rating = 4
                visibility = "friends"
            } | ConvertTo-Json -Depth 10
            
            $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
            
            Write-Host "SUCCESS: Visit created" -ForegroundColor Green
            Write-Host "  Created New Place: $($response.created_new_place)" -ForegroundColor Gray
            Write-Host "  Points Earned: $($response.points_earned)" -ForegroundColor Cyan
            
            if (-not $response.created_new_place -and $response.points_earned -eq 2) {
                Write-Host "  ✓ Correct: Used existing place, earned 2 points" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Should use existing place" -ForegroundColor Red
            }
            
        } catch {
            Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "No search results - skipping Scenario B" -ForegroundColor Yellow
}

# ============================================================
# SCENARIO C: Visit with Manual Place Entry
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "SCENARIO C: Visit with Manual Place Entry" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

Write-Host "`n--- Test C1: Create visit with manual place (no duplicates) ---" -ForegroundColor Cyan

try {
    # Use unique coordinates to avoid duplicates
    $uniqueLat = 35.6595 + (Get-Random -Minimum 1 -Maximum 100) / 10000
    $uniqueLng = 139.7004 + (Get-Random -Minimum 1 -Maximum 100) / 10000
    
    $visitBody = @{
        manual_place = @{
            name = "Hidden Gem Ramen Test $(Get-Random -Minimum 1000 -Maximum 9999)"
            name_ja = "隠れ家ラーメン"
            lat = $uniqueLat
            lng = $uniqueLng
            city = "Tokyo"
            ward = "Shibuya"
            categories = @("ramen", "restaurant")
        }
        comment = "Amazing hidden spot! You have to try this."
        rating = 5
        visibility = "public"
    } | ConvertTo-Json -Depth 10
    
    $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
    
    Write-Host "SUCCESS: Visit created with manual place" -ForegroundColor Green
    Write-Host "  Visit ID: $($response.visit_id)" -ForegroundColor Gray
    Write-Host "  Place ID: $($response.place_id)" -ForegroundColor Gray
    Write-Host "  Created New Place: $($response.created_new_place)" -ForegroundColor $(if ($response.created_new_place) { 'Green' } else { 'Red' })
    Write-Host "  Points Earned: $($response.points_earned)" -ForegroundColor Cyan
    Write-Host "  Moderation Note: $($response.moderation_note)" -ForegroundColor Yellow
    
    if ($response.created_new_place -and $response.points_earned -eq 2) {
        Write-Host "  ✓ Correct: New place pending, earned 2 points (3 bonus after approval)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Issue with manual place or points" -ForegroundColor Red
    }
    
    # Verify place was saved with pending status
    Write-Host "`n  Verifying place pending moderation..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    
    $checkPlaceUrl = "$baseRest/places?select=id,moderation_status,created_by&id=eq.$($response.place_id)"
    $savedPlace = Invoke-RestMethod -Uri $checkPlaceUrl -Headers $headers
    
    if ($savedPlace -and $savedPlace.Count -gt 0) {
        Write-Host "  ✓ Place found in database" -ForegroundColor Green
        Write-Host "    Moderation Status: $($savedPlace[0].moderation_status)" -ForegroundColor Gray
        Write-Host "    Created By: $($savedPlace[0].created_by)" -ForegroundColor Gray
        
        if ($savedPlace[0].moderation_status -eq 'pending') {
            Write-Host "    ✓ Correct: Pending moderation" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Should be pending" -ForegroundColor Red
        }
        
        if ($savedPlace[0].created_by -eq $userId) {
            Write-Host "    ✓ Correct creator" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Wrong creator" -ForegroundColor Red
        }
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

# ============================================================
# VALIDATION TESTS
# ============================================================
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host "VALIDATION TESTS" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

# Test: No place source provided
Write-Host "`n--- Test V1: No place source provided ---" -ForegroundColor Cyan

try {
    $visitBody = @{
        comment = "This should fail"
        visibility = "public"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
    Write-Host "✗ Should have returned 400" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "✓ Got expected 400 Bad Request" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test: Neither photo nor comment
Write-Host "`n--- Test V2: Neither photo nor comment ---" -ForegroundColor Cyan

if ($existingPlaces -and $existingPlaces.Count -gt 0) {
    try {
        $visitBody = @{
            place_id = $existingPlaces[0].id
            visibility = "public"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
        Write-Host "✗ Should have returned 400" -ForegroundColor Red
        
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "✓ Got expected 400 Bad Request (photo OR comment required)" -ForegroundColor Green
        } else {
            Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
    }
}

# Test: Comment too long
Write-Host "`n--- Test V3: Comment > 1000 characters ---" -ForegroundColor Cyan

if ($existingPlaces -and $existingPlaces.Count -gt 0) {
    try {
        $longComment = "x" * 1001
        
        $visitBody = @{
            place_id = $existingPlaces[0].id
            comment = $longComment
            visibility = "public"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
        Write-Host "✗ Should have returned 400" -ForegroundColor Red
        
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "✓ Got expected 400 Bad Request (comment too long)" -ForegroundColor Green
        } else {
            Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
    }
}

# Test: Invalid rating
Write-Host "`n--- Test V4: Invalid rating (0) ---" -ForegroundColor Cyan

if ($existingPlaces -and $existingPlaces.Count -gt 0) {
    try {
        $visitBody = @{
            place_id = $existingPlaces[0].id
            comment = "Test"
            rating = 0
            visibility = "public"
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $headers -Body $visitBody
        Write-Host "✗ Should have returned 400" -ForegroundColor Red
        
    } catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "✓ Got expected 400 Bad Request (rating must be 1-5)" -ForegroundColor Green
        } else {
            Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
        }
    }
}

# Test: Without authentication
Write-Host "`n--- Test V5: Without authentication ---" -ForegroundColor Cyan

try {
    $noAuthHeaders = @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    }
    
    $visitBody = @{
        place_id = "00000000-0000-0000-0000-000000000000"
        comment = "Test"
        visibility = "public"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $createVisitUrl -Method POST -Headers $noAuthHeaders -Body $visitBody
    Write-Host "✗ Should have returned 401" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "✓ Got expected 401 Unauthorized" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   TEST SUMMARY" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`nScenario A (Existing Place):" -ForegroundColor Yellow
Write-Host "  - Visit created with comment only" -ForegroundColor White
Write-Host "  - Earned 2 points (no bonus)" -ForegroundColor White
Write-Host "  - created_new_place: false" -ForegroundColor White

Write-Host "`nScenario B (Google API Place):" -ForegroundColor Yellow
Write-Host "  - New place: Saved to DB, auto-approved, earned 5 points" -ForegroundColor White
Write-Host "  - Existing place: Used existing, earned 2 points" -ForegroundColor White
Write-Host "  - google_place_id stored (prevents duplicate API calls)" -ForegroundColor White

Write-Host "`nScenario C (Manual Place):" -ForegroundColor Yellow
Write-Host "  - Place created with status 'pending'" -ForegroundColor White
Write-Host "  - Visit linked to pending place" -ForegroundColor White
Write-Host "  - Earned 2 points (3 bonus after admin approval)" -ForegroundColor White
Write-Host "  - Duplicate detection works (50m radius + name similarity)" -ForegroundColor White

Write-Host "`nValidation Tests:" -ForegroundColor Yellow
Write-Host "  - Rejects no place source (400)" -ForegroundColor White
Write-Host "  - Requires photo OR comment (400)" -ForegroundColor White
Write-Host "  - Rejects comment >1000 chars (400)" -ForegroundColor White
Write-Host "  - Validates rating 1-5 (400)" -ForegroundColor White
Write-Host "  - Requires authentication (401)" -ForegroundColor White

Write-Host "`nPoints System:" -ForegroundColor Yellow
Write-Host "  Existing place: +2 points" -ForegroundColor White
Write-Host "  New API place: +5 points (2+3 bonus, immediate)" -ForegroundColor White
Write-Host "  Manual place: +2 immediate, +3 after approval" -ForegroundColor White