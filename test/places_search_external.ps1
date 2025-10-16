# test_places_search_external.ps1
# Test Google Places API search with database fallback (NO APPLE API)

param(
    [string]$ProjectRef = "jelbrfbhwwcosmuckjqm",
    [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
)

$authUrl = "https://$ProjectRef.supabase.co/auth/v1/token?grant_type=password"
$searchUrl = "https://$ProjectRef.supabase.co/functions/v1/places-search-external"

Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "   GOOGLE PLACES SEARCH TEST (No Apple API)" -ForegroundColor Magenta
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

# Test 1: Search for popular place (should hit Google API)
Write-Host "`n--- Test 1: Search 'Ichiran Ramen' near Shibuya ---" -ForegroundColor Cyan
Write-Host "Expected: Google Places API returns 1-5 results" -ForegroundColor Gray

try {
    $body = @{
        query = "Ichiran Ramen"
        lat = 35.6595
        lng = 139.7004
        limit = 5
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "SUCCESS: Search completed" -ForegroundColor Green
    Write-Host "Source: $($response.source)" -ForegroundColor $(if ($response.source -eq 'google') { 'Green' } else { 'Yellow' })
    Write-Host "Count: $($response.count)" -ForegroundColor Gray
    Write-Host "Message: $($response.message)" -ForegroundColor Gray
    
    if ($response.results) {
        Write-Host "`nResults:" -ForegroundColor Cyan
        
        $resultNum = 1
        foreach ($place in $response.results) {
            Write-Host "`n  [$resultNum] $($place.name)" -ForegroundColor White
            Write-Host "      Source: $($place.source)" -ForegroundColor Gray
            Write-Host "      Address: $($place.address)" -ForegroundColor Gray
            Write-Host "      Coordinates: ($($place.lat), $($place.lng))" -ForegroundColor Gray
            
            if ($place.exists_in_db) {
                Write-Host "      In Database: YES (Blue pin)" -ForegroundColor Blue
            } else {
                Write-Host "      In Database: NO (Red pin)" -ForegroundColor Red
            }
            
            if ($place.photo_url) {
                Write-Host "      Photo: Available" -ForegroundColor Green
            } else {
                Write-Host "      Photo: None" -ForegroundColor DarkGray
            }
            
            $resultNum++
        }
    }
    
    # Validate required fields
    $validationErrors = @()
    if (-not $response.PSObject.Properties['results']) { $validationErrors += "Missing 'results'" }
    if (-not $response.PSObject.Properties['count']) { $validationErrors += "Missing 'count'" }
    if (-not $response.PSObject.Properties['source']) { $validationErrors += "Missing 'source'" }
    if (-not $response.PSObject.Properties['message']) { $validationErrors += "Missing 'message'" }
    
    if ($validationErrors.Count -eq 0) {
        Write-Host "`n✓ Response format valid" -ForegroundColor Green
    } else {
        Write-Host "`n✗ Response format errors:" -ForegroundColor Red
        $validationErrors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Search with limit=2
Write-Host "`n--- Test 2: Search 'ramen' with limit=2 ---" -ForegroundColor Cyan

try {
    $body = @{
        query = "ramen"
        lat = 35.6595
        lng = 139.7004
        limit = 2
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "SUCCESS: Got $($response.count) results" -ForegroundColor Green
    
    if ($response.count -le 2) {
        Write-Host "✓ Limit respected" -ForegroundColor Green
    } else {
        Write-Host "✗ Limit NOT respected (got $($response.count))" -ForegroundColor Red
    }
    
} catch {
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Invalid auth
Write-Host "`n--- Test 3: Search without authentication ---" -ForegroundColor Cyan

try {
    $noAuthHeaders = @{
        "apikey" = $AnonKey
        "Content-Type" = "application/json"
    }
    
    $body = @{ query = "ramen"; lat = 35.6595; lng = 139.7004 } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $noAuthHeaders -Body $body
    
    Write-Host "✗ Should have returned 401" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 401) {
        Write-Host "✓ Got expected 401 Unauthorized" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test 4: Invalid coordinates
Write-Host "`n--- Test 4: Invalid coordinates ---" -ForegroundColor Cyan

try {
    $body = @{ query = "ramen"; lat = 999; lng = 999 } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "✗ Should have returned 400" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "✓ Got expected 400 Bad Request" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# Test 5: Empty query
Write-Host "`n--- Test 5: Empty query ---" -ForegroundColor Cyan

try {
    $body = @{ query = ""; lat = 35.6595; lng = 139.7004 } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri $searchUrl -Method POST -Headers $headers -Body $body
    
    Write-Host "✗ Should have returned 400" -ForegroundColor Red
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "✓ Got expected 400 Bad Request" -ForegroundColor Green
    } else {
        Write-Host "✗ Wrong status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

Write-Host "`n============================================================" -ForegroundColor Magenta
Write-Host "   TEST SUMMARY" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Host "`nSearch Flow:" -ForegroundColor Yellow
Write-Host "  1. Try Google Places API" -ForegroundColor White
Write-Host "  2. If < limit results, fallback to Database" -ForegroundColor White
Write-Host "  3. Return up to 'limit' results total" -ForegroundColor White

Write-Host "`nExpected Behavior:" -ForegroundColor Yellow
Write-Host "  Test 1: Returns 1-5 Google results" -ForegroundColor White
Write-Host "  Test 2: Respects limit=2" -ForegroundColor White
Write-Host "  Test 3: Rejects unauthenticated (401)" -ForegroundColor White
Write-Host "  Test 4: Rejects invalid coords (400)" -ForegroundColor White
Write-Host "  Test 5: Rejects empty query (400)" -ForegroundColor White

Write-Host "`nPin Colors (for iOS):" -ForegroundColor Yellow
Write-Host "  exists_in_db: true  → Blue pin (in database)" -ForegroundColor Blue
Write-Host "  exists_in_db: false → Red pin (new from API)" -ForegroundColor Red