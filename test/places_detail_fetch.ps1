# test_places_detail_fetch.ps1
# Test fetching full place details from Google Places API

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$searchUrl = "https://$ProjectRef.supabase.co/functions/v1/places-search-external"
$detailUrl = "https://$ProjectRef.supabase.co/functions/v1/places-detail-fetch"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   PLACE DETAILS FETCH TEST" -ForegroundColor Magenta
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

# Step 1: Search to get a google_place_id
Write-Host "`n--- Step 1: Search for 'Ichiran Ramen' to get place ID ---" -ForegroundColor Cyan

$searchBody = @{
    query = "Ichiran Ramen"
    lat = 35.6595
    lng = 139.7004
    limit = 1
} | ConvertTo-Json

$searchResult = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $searchBody

if ($searchResult.results -and $searchResult.results.Count -gt 0) {
    $testPlace = $searchResult.results[0]
    Write-Host "Found place: $($testPlace.name)" -ForegroundColor Green
    Write-Host "Google Place ID: $($testPlace.external_id)" -ForegroundColor Gray
    Write-Host "Exists in DB: $($testPlace.exists_in_db)" -ForegroundColor Gray
} else {
    Write-Host "No search results - cannot proceed with test" -ForegroundColor Red
    exit
}

# Test 1: Fetch full details from Google API
Write-Host "`n--- Test 1: Fetch full details from Google API ---" -ForegroundColor Cyan
Write-Host "Expected: Returns comprehensive place data" -ForegroundColor Gray

try {
    $detailBody = @{
        google_place_id = $testPlace.external_id
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $headers -Body $detailBody
    
    Write-Host "SUCCESS: Details fetched" -ForegroundColor Green
    Write-Host "Source: $($response.source)" -ForegroundColor Cyan
    Write-Host "Cached: $($response.cached)" -ForegroundColor Gray
    
    $place = $response.place
    
    Write-Host "`nPlace Details:" -ForegroundColor Cyan
    Write-Host "  Name: $($place.name)" -ForegroundColor White
    Write-Host "  Address: $($place.address)" -ForegroundColor Gray
    Write-Host "  City: $($place.city)" -ForegroundColor Gray
    Write-Host "  Ward: $($place.ward)" -ForegroundColor Gray
    Write-Host "  Coordinates: ($($place.lat), $($place.lng))" -ForegroundColor Gray
    Write-Host "  Price Level: $($place.price_level)" -ForegroundColor Gray
    Write-Host "  Rating: $($place.rating)" -ForegroundColor Gray
    Write-Host "  User Ratings: $($place.user_ratings_total)" -ForegroundColor Gray
    
    if ($place.phone) {
        Write-Host "  Phone: $($place.phone)" -ForegroundColor Green
    } else {
        Write-Host "  Phone: Not available" -ForegroundColor DarkGray
    }
    
    if ($place.website) {
        Write-Host "  Website: $($place.website)" -ForegroundColor Green
    } else {
        Write-Host "  Website: Not available" -ForegroundColor DarkGray
    }
    
    if ($place.opening_hours) {
        Write-Host "  Opening Hours: Available" -ForegroundColor Green
        if ($place.opening_hours.open_now -ne $null) {
            Write-Host "    Currently: $(if ($place.opening_hours.open_now) { 'OPEN' } else { 'CLOSED' })" -ForegroundColor $(if ($place.opening_hours.open_now) { 'Green' } else { 'Red' })
        }
    } else {
        Write-Host "  Opening Hours: Not available" -ForegroundColor DarkGray
    }
    
    if ($place.categories -and $place.categories.Count -gt 0) {
        Write-Host "  Categories: $($place.categories -join ', ')" -ForegroundColor Gray
    }
    
    if ($place.photos -and $place.photos.Count -gt 0) {
        Write-Host "  Photos: $($place.photos.Count) available" -ForegroundColor Green
        Write-Host "    First photo: $($place.photos[0].Substring(0, 80))..." -ForegroundColor DarkGray
    } else {
        Write-Host "  Photos: None" -ForegroundColor DarkGray
    }
    
    # Validate required fields
    Write-Host "`nField Validation:" -ForegroundColor Yellow
    $validationErrors = @()
    
    if (-not $place.google_place_id) { $validationErrors += "Missing google_place_id" }
    if (-not $place.name) { $validationErrors += "Missing name" }
    if (-not $place.lat) { $validationErrors += "Missing lat" }
    if (-not $place.lng) { $validationErrors += "Missing lng" }
    
    if ($validationErrors.Count -eq 0) {
        Write-Host "  ✓ All required fields present" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Missing fields:" -ForegroundColor Red
        $validationErrors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
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

# Test 2: Missing google_place_id (validation)
Write-Host "`n--- Test 2: Missing google_place_id ---" -ForegroundColor Cyan

try {
    $detailBody = @{} | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $headers -Body $detailBody
    
    Write-Host "✗ Should have returned 400" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "✓ Got expected 400 Bad Request" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test 3: Invalid google_place_id
Write-Host "`n--- Test 3: Invalid google_place_id ---" -ForegroundColor Cyan

try {
    $detailBody = @{
        google_place_id = "INVALID_ID_12345"
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $headers -Body $detailBody
    
    Write-Host "✗ Should have returned 404" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 404) {
        Write-Host "✓ Got expected 404 Not Found" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test 4: Without authentication
Write-Host "`n--- Test 4: Without authentication ---" -ForegroundColor Cyan

try {
    $noAuthHeaders = @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    }
    
    $detailBody = @{
        google_place_id = $testPlace.external_id
    } | ConvertTo-Json
    
    $response = Invoke-RestMethod -Uri $detailUrl -Method POST -Headers $noAuthHeaders -Body $detailBody
    
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

Write-Host "`nData Flow:" -ForegroundColor Yellow
Write-Host "  1. User searches → Gets basic info + google_place_id" -ForegroundColor White
Write-Host "  2. User taps result → Fetches full details from Google" -ForegroundColor White
Write-Host "  3. Details cached in DB on visit creation" -ForegroundColor White
Write-Host "  4. Subsequent fetches use cached data (no API call)" -ForegroundColor White

Write-Host "`nExpected Behavior:" -ForegroundColor Yellow
Write-Host "  Test 1: Returns full place data from Google" -ForegroundColor White
Write-Host "  Test 2: Rejects missing google_place_id (400)" -ForegroundColor White
Write-Host "  Test 3: Rejects invalid place ID (404)" -ForegroundColor White
Write-Host "  Test 4: Requires authentication (401)" -ForegroundColor White

Write-Host "`nPlace Data Included:" -ForegroundColor Yellow
Write-Host "  - Basic: name, address, coordinates" -ForegroundColor White
Write-Host "  - Contact: phone, website" -ForegroundColor White
Write-Host "  - Info: rating, reviews count, price level" -ForegroundColor White
Write-Host "  - Hours: opening hours, currently open/closed" -ForegroundColor White
Write-Host "  - Media: up to 5 photos (high-res URLs)" -ForegroundColor White
Write-Host "  - Categories: place types/categories" -ForegroundColor White