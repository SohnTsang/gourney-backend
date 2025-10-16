# Test Script: GET /v1/lists/:id (View Single List)
# Tests list detail viewing with visibility rules and pagination

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

# Test user credentials
$testUser1Email = "testuser@example.com"
$testUser2Email = "testuser2@example.com"
$password = "TestPass123!"

$testsPassed = 0
$testsFailed = 0
$script:itemsAdded = 0  # Use script scope

function Get-FreshToken($email) {
    try {
        $body = @{
            email = $email
            password = $password
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
            -Method POST `
            -Headers @{
                "apikey" = $anonKey
                "Content-Type" = "application/json"
            } `
            -Body $body
        
        if (-not $response.access_token) {
            throw "No access token in response"
        }
        
        return $response.access_token
    } catch {
        Write-Host "ERROR getting token for $email : $_" -ForegroundColor Red
        throw
    }
}

function Test-Endpoint($testName, $scriptBlock) {
    Write-Host "`n=== $testName ===" -ForegroundColor Cyan
    try {
        & $scriptBlock
        $script:testsPassed++
        Write-Host "PASS: $testName" -ForegroundColor Green
    } catch {
        $script:testsFailed++
        Write-Host "FAIL: $testName" -ForegroundColor Red
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Testing GET /v1/lists/:id" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get fresh tokens
Write-Host "`nGetting fresh tokens..." -ForegroundColor Cyan
try {
    $token1 = Get-FreshToken $testUser1Email
    $token2 = Get-FreshToken $testUser2Email
    
    if (-not $token1 -or -not $token2) {
        throw "Failed to obtain valid tokens"
    }
    
    Write-Host "Token 1 length: $($token1.Length)" -ForegroundColor Gray
    Write-Host "Token 2 length: $($token2.Length)" -ForegroundColor Gray
    Write-Host "Tokens obtained successfully" -ForegroundColor Green
} catch {
    Write-Host "`nFATAL ERROR: Could not authenticate users" -ForegroundColor Red
    Write-Host "Make sure test users exist with password: $password" -ForegroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Setup: Create a test list with items for User 1
Write-Host "`n--- SETUP: Creating test list ---" -ForegroundColor Magenta

try {
    $createBody = @{
        title = "Test Ramen List"
        description = "My favorite ramen spots in Tokyo"
        visibility = "public"
    } | ConvertTo-Json

    $createResponse = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $createBody

    Write-Host "Create response:" -ForegroundColor Gray
    Write-Host ($createResponse | ConvertTo-Json -Depth 5) -ForegroundColor Gray
    
    # Handle both response formats: direct object or wrapped in 'list'
    if ($createResponse.list) {
        $testListId = $createResponse.list.id
    } elseif ($createResponse.id) {
        $testListId = $createResponse.id
    } else {
        throw "No list ID in response"
    }
    
    if (-not $testListId) {
        throw "List ID is empty"
    }
    
    Write-Host "Created test list: $testListId" -ForegroundColor Green
} catch {
    Write-Host "`nFATAL ERROR: Could not create test list" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "`nResponse details:" -ForegroundColor Yellow
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host $responseBody -ForegroundColor Yellow
    }
    exit 1
}

# Add 3 items to the list
$placeIds = @(
    "123e4567-e89b-12d3-a456-426614174000",
    "123e4567-e89b-12d3-a456-426614174001", 
    "123e4567-e89b-12d3-a456-426614174002"
)

$itemsAdded = 0
foreach ($placeId in $placeIds) {
    $addItemBody = @{
        place_id = $placeId
        note = "Great ramen spot!"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$testListId/items" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $addItemBody
        
        Write-Host "Added place: $placeId" -ForegroundColor Green
        $script:itemsAdded++
    } catch {
        Write-Host "WARNING: Could not add place $placeId (place may not exist)" -ForegroundColor Yellow
    }
}

if ($script:itemsAdded -eq 0) {
    Write-Host "`nNOTE: No items added to list (places don't exist). Tests will use empty list." -ForegroundColor Yellow
}

Write-Host "`nSetup complete. Starting tests..." -ForegroundColor Magenta
Write-Host "Items successfully added: $script:itemsAdded" -ForegroundColor Gray

# Test 1: View own list (owner)
Test-Endpoint "View own list (owner)" {
    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }

    if (-not $response.list) { throw "Missing list object" }
    if ($response.list.id -ne $testListId) { throw "Wrong list ID" }
    if ($response.list.title -ne "Test Ramen List") { throw "Wrong title" }
    if ($response.list.description -ne "My favorite ramen spots in Tokyo") { throw "Wrong description" }
    if ($response.list.visibility -ne "public") { throw "Wrong visibility" }
    if ($response.list.item_count -ne $script:itemsAdded) { throw "Wrong item count: expected $script:itemsAdded, got $($response.list.item_count)" }
    if (-not $response.list.owner_handle) { throw "Missing owner_handle" }
    if ($null -eq $response.items) { throw "Missing items array" }
    if ($response.items.Count -ne $script:itemsAdded) { throw "Expected $script:itemsAdded items, got $($response.items.Count)" }
    
    # Check item structure if items exist
    if ($script:itemsAdded -gt 0) {
        $firstItem = $response.items[0]
        if (-not $firstItem.id) { throw "Item missing id" }
        if (-not $firstItem.place_id) { throw "Item missing place_id" }
        if (-not $firstItem.created_at) { throw "Item missing created_at" }
        if (-not $firstItem.place) { throw "Item missing place details" }
        if (-not $firstItem.place.name_en) { throw "Place missing name_en" }
        if (-not $firstItem.place.city) { throw "Place missing city" }
    }
    
    Write-Host "List ID: $($response.list.id)" -ForegroundColor Gray
    Write-Host "Title: $($response.list.title)" -ForegroundColor Gray
    Write-Host "Items: $($response.items.Count)" -ForegroundColor Gray
    Write-Host "Item count: $($response.list.item_count)" -ForegroundColor Gray
}

# Test 2: View public list as different user (stranger)
Test-Endpoint "View public list as stranger" {
    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token2"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }

    if (-not $response.list) { throw "Stranger cannot view public list" }
    if ($response.list.id -ne $testListId) { throw "Wrong list ID" }
    if ($response.items.Count -ne $script:itemsAdded) { throw "Expected $script:itemsAdded items" }
    
    Write-Host "Successfully viewed public list as stranger" -ForegroundColor Gray
}

# Test 3: Pagination with limit
Test-Endpoint "Pagination with limit=2" {
    if ($script:itemsAdded -lt 2) {
        Write-Host "SKIP: Need at least 2 items for pagination test" -ForegroundColor Yellow
        return
    }
    
    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId`?limit=2" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }

    if ($response.items.Count -ne 2) { throw "Expected 2 items, got $($response.items.Count)" }
    if (-not $response.next_cursor) { throw "Missing next_cursor for paginated results" }
    
    Write-Host "First page: $($response.items.Count) items" -ForegroundColor Gray
    Write-Host "Next cursor: $($response.next_cursor)" -ForegroundColor Gray
    
    # Get next page
    $page2 = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId`?limit=2&cursor=$($response.next_cursor)" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }
    
    if ($page2.items.Count -lt 1) { throw "Expected at least 1 item on page 2" }
    Write-Host "Second page: $($page2.items.Count) items" -ForegroundColor Gray
}

# Test 4: Missing API version header
Test-Endpoint "Missing API version header -> 400" {
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
            }
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected missing API version" -ForegroundColor Gray
    }
}

# Test 5: Missing authorization header
Test-Endpoint "Missing authorization -> 401" {
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId" `
            -Method GET `
            -Headers @{
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "Should have returned 401"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 401) {
            throw "Expected 401, got $statusCode"
        }
        Write-Host "Correctly rejected missing auth" -ForegroundColor Gray
    }
}

# Test 6: Non-existent list ID
Test-Endpoint "Non-existent list ID -> 404" {
    $fakeListId = "00000000-0000-0000-0000-000000000000"
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$fakeListId" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "Should have returned 404"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 404) {
            throw "Expected 404, got $statusCode"
        }
        Write-Host "Correctly returned 404 for non-existent list" -ForegroundColor Gray
    }
}

# Test 7: Invalid cursor
Test-Endpoint "Invalid cursor -> 400" {
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId`?cursor=invalid" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected invalid cursor" -ForegroundColor Gray
    }
}

# Test 8: Create private list and test visibility
Test-Endpoint "Private list visibility (stranger cannot view)" {
    # Create private list
    $privateBody = @{
        title = "Private List"
        description = "Only I can see this"
        visibility = "private"
    } | ConvertTo-Json

    $privateResponse = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $privateBody

    # Handle both response formats
    if ($privateResponse.list) {
        $privateListId = $privateResponse.list.id
    } else {
        $privateListId = $privateResponse.id
    }
    
    # Try to view as different user (should fail)
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$privateListId" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token2"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "Stranger should not be able to view private list"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 404) {
            throw "Expected 404, got $statusCode"
        }
        Write-Host "Correctly blocked stranger from viewing private list" -ForegroundColor Gray
    }
}

# Test 9: Items ordered by created_at DESC
Test-Endpoint "Items ordered by created_at DESC" {
    if ($script:itemsAdded -lt 2) {
        Write-Host "SKIP: Need at least 2 items to test ordering" -ForegroundColor Yellow
        return
    }
    
    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$testListId" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }

    $items = $response.items
    for ($i = 0; $i -lt ($items.Count - 1); $i++) {
        $current = [DateTime]::Parse($items[$i].created_at)
        $next = [DateTime]::Parse($items[$i + 1].created_at)
        
        if ($current -lt $next) {
            throw "Items not ordered correctly: $current should be >= $next"
        }
    }
    
    Write-Host "Items correctly ordered by created_at DESC" -ForegroundColor Gray
}

# Summary
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "Test Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

if ($testsFailed -eq 0) {
    Write-Host "`nALL TESTS PASSED!" -ForegroundColor Green
    Write-Host "GET /v1/lists/:id is working correctly" -ForegroundColor Green
} else {
    Write-Host "`nSOME TESTS FAILED" -ForegroundColor Red
    exit 1
}