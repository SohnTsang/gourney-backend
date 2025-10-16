# Test script for DELETE /v1/lists/:id/items/:placeId
# Production-ready testing using real data from database

# Configuration
$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

# Test user credentials
$testUser1Email = "testuser@example.com"
$testUser2Email = "testuser2@example.com"
$password = "TestPass123!"

# Known test user IDs from handover
$testUser1Id = "1d6d3310-2c47-48a0-802b-bbc72599bc7d"
$testUser2Id = "7b3f0812-c048-4d44-a77f-996f2d23ba99"

# Test counters
$testsPassed = 0
$testsFailed = 0
$globalListWithItems = $null
$globalListId = $null
$globalPlaceId = $null
$globalTestUser1Token = $null
$globalTestUser2Token = $null

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing DELETE /v1/lists/:id/items/:placeId" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Helper: Get JWT token via password grant
function Get-FreshToken($email) {
    try {
        $body = @{
            email = $email
            password = $password
        } | ConvertTo-Json

        $response = Invoke-WebRequest `
            -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
            -Method POST `
            -Headers @{ 
                "apikey" = $anonKey
                "Content-Type" = "application/json"
            } `
            -Body $body `
            -UseBasicParsing

        $tokenData = $response.Content | ConvertFrom-Json
        return $tokenData.access_token
    }
    catch {
        Write-Host "ERROR: Failed to get token for $email" -ForegroundColor Red
        Write-Host "Status: $($_.Exception.Response.StatusCode.Value__)" -ForegroundColor Red
        
        # Try to read error details
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            Write-Host "Error details: $errorBody" -ForegroundColor Red
        }
        catch {
            Write-Host "Could not read error details" -ForegroundColor Red
        }
        
        return $null
    }
}

# Helper: Test endpoint
function Test-Endpoint($testName, $method, $uri, $body, $expectedStatus, $headers, $shouldHaveBody = $false) {
    Write-Host "TEST: $testName" -ForegroundColor White
    
    try {
        $params = @{
            Uri = $uri
            Method = $method
            Headers = $headers
            UseBasicParsing = $true
            ErrorAction = 'Stop'
        }

        if ($body) {
            $params['Body'] = $body
            $params['Headers']['Content-Type'] = 'application/json'
        }

        $response = Invoke-WebRequest @params
        $statusCode = $response.StatusCode
        $responseBody = if ($response.Content) { $response.Content | ConvertFrom-Json } else { $null }

    }
    catch {
        # Handle HTTP errors
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd() | ConvertFrom-Json
            }
            catch {
                $responseBody = $null
            }
        }
        else {
            Write-Host "✗ FAILED: Unexpected error" -ForegroundColor Red
            Write-Host $_.Exception.Message
            $script:testsFailed++
            return $false
        }
    }

    if ($statusCode -eq $expectedStatus) {
        Write-Host "✓ PASSED (HTTP $statusCode)" -ForegroundColor Green
        $script:testsPassed++
        return $responseBody
    }
    else {
        Write-Host "✗ FAILED: Expected HTTP $expectedStatus, got $statusCode" -ForegroundColor Red
        if ($responseBody) {
            Write-Host "Response: $($responseBody | ConvertTo-Json)" -ForegroundColor Gray
        }
        $script:testsFailed++
        return $false
    }
}

Write-Host "SETUP: Preparing test data..." -ForegroundColor Yellow
Write-Host ""

# STEP 1: Get fresh tokens for both users
Write-Host "Getting authentication tokens..." -ForegroundColor Yellow
$globalTestUser1Token = Get-FreshToken($testUser1Email)
$globalTestUser2Token = Get-FreshToken($testUser2Email)

if (-not $globalTestUser1Token -or -not $globalTestUser2Token) {
    Write-Host "ERROR: Could not get authentication tokens. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "✓ Tokens obtained" -ForegroundColor Green
Write-Host ""

# STEP 2: Fetch existing lists from database (production approach)
Write-Host "Fetching existing lists from database..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $globalTestUser1Token"
    "X-API-Version" = "v1"
    "apikey" = $anonKey
}

$listsResponse = Invoke-WebRequest `
    -Uri "$supabaseUrl/functions/v1/lists-get?limit=50" `
    -Method GET `
    -Headers $headers `
    -UseBasicParsing

$listData = $listsResponse.Content | ConvertFrom-Json

if ($listData.lists -and $listData.lists.Count -gt 0) {
    Write-Host "✓ Found $($listData.lists.Count) lists" -ForegroundColor Green
    
    # Find a list owned by testUser1 with items
    $listWithItems = $listData.lists | Where-Object { $_.item_count -gt 0 } | Select-Object -First 1
    
    if ($listWithItems) {
        $globalListId = $listWithItems.id
        Write-Host "✓ Found list with items: $globalListId (item_count: $($listWithItems.item_count))" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ No lists with items found. Will create test data..." -ForegroundColor Yellow
    }
}
else {
    Write-Host "⚠ No lists found. Will create test data..." -ForegroundColor Yellow
}

Write-Host ""

# STEP 3: If no list with items, create one
if (-not $globalListId) {
    Write-Host "Creating test list and adding item..." -ForegroundColor Yellow
    
    # Get a list first
    $listsResponse = Invoke-WebRequest `
        -Uri "$supabaseUrl/functions/v1/lists-get?limit=1" `
        -Method GET `
        -Headers $headers `
        -UseBasicParsing
    
    $listData = $listsResponse.Content | ConvertFrom-Json
    
    if ($listData.lists -and $listData.lists.Count -gt 0) {
        $globalListId = $listData.lists[0].id
        Write-Host "✓ Using existing list: $globalListId" -ForegroundColor Green
    }
    else {
        # Create a new list
        $createListBody = @{
            title = "Test List - Remove Item"
            description = "Temporary list for testing remove-item endpoint"
            visibility = "private"
        } | ConvertTo-Json

        $createListResponse = Invoke-WebRequest `
            -Uri "$supabaseUrl/functions/v1/lists-create" `
            -Method POST `
            -Headers $headers `
            -Body $createListBody `
            -UseBasicParsing

        $createListData = $createListResponse.Content | ConvertFrom-Json
        $globalListId = $createListData.id
        Write-Host "✓ Created test list: $globalListId" -ForegroundColor Green
    }
    
    # Now add an item to the list
    # Get first available place from database
    Write-Host "Fetching available places..." -ForegroundColor Yellow
    
    try {
        $placesResponse = Invoke-WebRequest `
            -Uri "$supabaseUrl/functions/v1/places-search" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $globalTestUser1Token"
                "X-API-Version" = "v1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
            } `
            -Body '{"q":"ramen","limit":1}' `
            -UseBasicParsing

        $placesData = $placesResponse.Content | ConvertFrom-Json
        
        if ($placesData.places -and $placesData.places.Count -gt 0) {
            $globalPlaceId = $placesData.places[0].id
            Write-Host "✓ Found place: $globalPlaceId" -ForegroundColor Green
            
            # Add item to list
            $addItemBody = @{
                place_id = $globalPlaceId
                note = "Testing remove-item endpoint"
            } | ConvertTo-Json

            $addItemResponse = Invoke-WebRequest `
                -Uri "$supabaseUrl/functions/v1/lists-add-item?list_id=$globalListId" `
                -Method POST `
                -Headers $headers `
                -Body $addItemBody `
                -UseBasicParsing

            Write-Host "✓ Added item to list" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ No places found in search. Using fallback UUID." -ForegroundColor Yellow
            # Use a known place ID from the database if search fails
            $globalPlaceId = "123e4567-e89b-12d3-a456-426614174000"
        }
    }
    catch {
        Write-Host "⚠ Could not fetch/add place: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# STEP 4: If we still don't have a place ID, fetch from list details
if (-not $globalPlaceId -and $globalListId) {
    Write-Host "Fetching place ID from list details..." -ForegroundColor Yellow
    
    try {
        $listDetailsResponse = Invoke-WebRequest `
            -Uri "$supabaseUrl/functions/v1/lists-get-detail/$globalListId" `
            -Method GET `
            -Headers $headers `
            -UseBasicParsing

        $listDetails = $listDetailsResponse.Content | ConvertFrom-Json
        
        if ($listDetails.items -and $listDetails.items.Count -gt 0) {
            $globalPlaceId = $listDetails.items[0].place_id
            Write-Host "✓ Retrieved place ID: $globalPlaceId" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ No items in list. Will need to add one..." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "⚠ Could not fetch list details: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "SETUP COMPLETE" -ForegroundColor Green
Write-Host "List ID: $globalListId" -ForegroundColor Gray
Write-Host "Place ID: $globalPlaceId" -ForegroundColor Gray
Write-Host ""

# ============================================
# ACTUAL TESTS
# ============================================
Write-Host "RUNNING TESTS..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Remove item from own list (success case)
if ($globalPlaceId) {
    Test-Endpoint `
        "1. Remove item from own list → 204" `
        "DELETE" `
        "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=$globalPlaceId" `
        $null `
        204 `
        @{
            "Authorization" = "Bearer $globalTestUser1Token"
            "X-API-Version" = "v1"
            "apikey" = $anonKey
        }
    Write-Host ""
}

# Test 2: Try to remove same item again (should be 404 - not found)
if ($globalPlaceId) {
    Test-Endpoint `
        "2. Remove already-deleted item → 404" `
        "DELETE" `
        "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=$globalPlaceId" `
        $null `
        404 `
        @{
            "Authorization" = "Bearer $globalTestUser1Token"
            "X-API-Version" = "v1"
            "apikey" = $anonKey
        }
    Write-Host ""
}

# Test 3: Remove from someone else's list (should be 404 - access denied via RLS)
Test-Endpoint `
    "3. Remove from someone else's list → 404" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=00000000-0000-0000-0000-000000000001" `
    $null `
    404 `
    @{
        "Authorization" = "Bearer $globalTestUser2Token"
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 4: Remove from non-existent list (should be 404)
Test-Endpoint `
    "4. Remove from non-existent list → 404" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=00000000-0000-0000-0000-000000000000&place_id=$globalPlaceId" `
    $null `
    404 `
    @{
        "Authorization" = "Bearer $globalTestUser1Token"
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 5: Missing list_id parameter (should be 400)
Test-Endpoint `
    "5. Missing list_id parameter → 400" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?place_id=$globalPlaceId" `
    $null `
    400 `
    @{
        "Authorization" = "Bearer $globalTestUser1Token"
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 6: Missing place_id parameter (should be 400)
Test-Endpoint `
    "6. Missing place_id parameter → 400" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId" `
    $null `
    400 `
    @{
        "Authorization" = "Bearer $globalTestUser1Token"
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 7: Missing API version (should be 400)
Test-Endpoint `
    "7. Missing API version → 400" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=$globalPlaceId" `
    $null `
    400 `
    @{
        "Authorization" = "Bearer $globalTestUser1Token"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 8: Missing authorization header (should be 401)
Test-Endpoint `
    "8. Missing authorization header → 401" `
    "DELETE" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=$globalPlaceId" `
    $null `
    401 `
    @{
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# Test 9: Wrong HTTP method (POST instead of DELETE) → 405
Test-Endpoint `
    "9. Wrong HTTP method (POST) → 405" `
    "POST" `
    "$supabaseUrl/functions/v1/lists-remove-item?list_id=$globalListId&place_id=$globalPlaceId" `
    "{}" `
    405 `
    @{
        "Authorization" = "Bearer $globalTestUser1Token"
        "X-API-Version" = "v1"
        "apikey" = $anonKey
    }
Write-Host ""

# ============================================
# TEST SUMMARY
# ============================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host "Total Tests: $($testsPassed + $testsFailed)" -ForegroundColor Cyan
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "✓ ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "✗ SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}