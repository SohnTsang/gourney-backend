# Test Script: PATCH /v1/lists-update (Update List)
# Tests the EXISTING lists-update function with query parameter format

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

# Test user credentials
$testUser1Email = "testuser@example.com"
$testUser2Email = "testuser2@example.com"
$password = "TestPass123!"

$testsPassed = 0
$testsFailed = 0

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
Write-Host "Testing PATCH /v1/lists-update" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

# Get fresh tokens
Write-Host "`nGetting fresh tokens..." -ForegroundColor Cyan
try {
    $token1 = Get-FreshToken $testUser1Email
    $token2 = Get-FreshToken $testUser2Email
    
    if (-not $token1 -or -not $token2) {
        throw "Failed to obtain valid tokens"
    }
    
    Write-Host "Tokens obtained successfully" -ForegroundColor Green
} catch {
    Write-Host "`nFATAL ERROR: Could not authenticate users" -ForegroundColor Red
    exit 1
}

# Setup: Create a test list
Write-Host "`n--- SETUP: Creating test list ---" -ForegroundColor Magenta

try {
    $createBody = @{
        title = "Original Title"
        description = "Original description"
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

    # Handle both response formats
    if ($createResponse.list) {
        $testListId = $createResponse.list.id
    } else {
        $testListId = $createResponse.id
    }
    
    Write-Host "Created test list: $testListId" -ForegroundColor Green
} catch {
    Write-Host "`nFATAL ERROR: Could not create test list" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nSetup complete. Starting tests..." -ForegroundColor Magenta

# Test 1: Update title only
Test-Endpoint "Update title only" {
    $updateBody = @{
        title = "Updated Title"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
        -Method PATCH `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $updateBody

    if ($response.title -ne "Updated Title") { throw "Title not updated: got '$($response.title)'" }
    if ($response.description -ne "Original description") { throw "Description should not change" }
    if ($response.visibility -ne "public") { throw "Visibility should not change" }
    
    Write-Host "Title: '$($response.title)'" -ForegroundColor Gray
    Write-Host "Description: '$($response.description)'" -ForegroundColor Gray
}

# Test 2: Update description only
Test-Endpoint "Update description only" {
    $updateBody = @{
        description = "New description here"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
        -Method PATCH `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $updateBody

    if ($response.description -ne "New description here") { throw "Description not updated" }
    if ($response.title -ne "Updated Title") { throw "Title should not change" }
    
    Write-Host "Description updated successfully" -ForegroundColor Gray
}

# Test 3: Update visibility only
Test-Endpoint "Update visibility only" {
    $updateBody = @{
        visibility = "private"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
        -Method PATCH `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $updateBody

    if ($response.visibility -ne "private") { throw "Visibility not updated" }
    
    Write-Host "Visibility changed to: $($response.visibility)" -ForegroundColor Gray
}

# Test 4: Update multiple fields at once
Test-Endpoint "Update multiple fields at once" {
    $updateBody = @{
        title = "Multi-Update Title"
        description = "Multi-update description"
        visibility = "friends"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
        -Method PATCH `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $updateBody

    if ($response.title -ne "Multi-Update Title") { throw "Title not updated" }
    if ($response.description -ne "Multi-update description") { throw "Description not updated" }
    if ($response.visibility -ne "friends") { throw "Visibility not updated" }
    
    Write-Host "All fields updated successfully" -ForegroundColor Gray
}

# Test 5: Clear description (set to null)
Test-Endpoint "Clear description (set to null)" {
    $updateBody = @{
        description = $null
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
        -Method PATCH `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "Content-Type" = "application/json"
            "X-API-Version" = "v1"
        } `
        -Body $updateBody

    if ($response.description -ne $null) { throw "Description should be null" }
    
    Write-Host "Description cleared successfully" -ForegroundColor Gray
}

# Test 6: Title validation - empty string
Test-Endpoint "Title validation - empty string -> 400" {
    $updateBody = @{
        title = ""
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected empty title" -ForegroundColor Gray
    }
}

# Test 7: Title validation - too long (>100 chars)
Test-Endpoint "Title validation - too long -> 400" {
    $longTitle = "a" * 101
    $updateBody = @{
        title = $longTitle
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected title >100 chars" -ForegroundColor Gray
    }
}

# Test 8: Description validation - too long (>500 chars)
Test-Endpoint "Description validation - too long -> 400" {
    $longDesc = "a" * 501
    $updateBody = @{
        description = $longDesc
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected description >500 chars" -ForegroundColor Gray
    }
}

# Test 9: Visibility validation - invalid value
Test-Endpoint "Visibility validation - invalid value -> 400" {
    $updateBody = @{
        visibility = "invalid"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected invalid visibility" -ForegroundColor Gray
    }
}

# Test 10: Empty update body
Test-Endpoint "Empty update body -> 400" {
    $updateBody = @{} | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected empty update" -ForegroundColor Gray
    }
}

# Test 11: Update someone else's list
Test-Endpoint "Update someone else's list -> 403/404" {
    $updateBody = @{
        title = "Hacked Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token2"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 403 or 404"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 403 -and $statusCode -ne 404) {
            throw "Expected 403 or 404, got $statusCode"
        }
        Write-Host "Correctly prevented unauthorized update (status: $statusCode)" -ForegroundColor Gray
    }
}

# Test 12: Non-existent list ID
Test-Endpoint "Non-existent list ID -> 404" {
    $fakeListId = "00000000-0000-0000-0000-000000000000"
    $updateBody = @{
        title = "New Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$fakeListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 404"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 404) {
            throw "Expected 404, got $statusCode"
        }
        Write-Host "Correctly returned 404 for non-existent list" -ForegroundColor Gray
    }
}

# Test 13: Missing list_id parameter
Test-Endpoint "Missing list_id parameter -> 400" {
    $updateBody = @{
        title = "New Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected missing list_id parameter" -ForegroundColor Gray
    }
}

# Test 14: Missing API version header
Test-Endpoint "Missing API version header -> 400" {
    $updateBody = @{
        title = "New Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
            } `
            -Body $updateBody
        throw "Should have returned 400"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 400) {
            throw "Expected 400, got $statusCode"
        }
        Write-Host "Correctly rejected missing API version" -ForegroundColor Gray
    }
}

# Test 15: Missing authorization header
Test-Endpoint "Missing authorization -> 401" {
    $updateBody = @{
        title = "New Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method PATCH `
            -Headers @{
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 401"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 401) {
            throw "Expected 401, got $statusCode"
        }
        Write-Host "Correctly rejected missing auth" -ForegroundColor Gray
    }
}

# Test 16: Wrong HTTP method (POST instead of PATCH)
Test-Endpoint "Wrong HTTP method -> 405" {
    $updateBody = @{
        title = "New Title"
    } | ConvertTo-Json

    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-update?list_id=$testListId" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "Content-Type" = "application/json"
                "X-API-Version" = "v1"
            } `
            -Body $updateBody
        throw "Should have returned 405"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 405) {
            throw "Expected 405, got $statusCode"
        }
        Write-Host "Correctly rejected wrong method" -ForegroundColor Gray
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "Test Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

if ($testsFailed -eq 0) {
    Write-Host "`nALL TESTS PASSED!" -ForegroundColor Green
    Write-Host "PATCH /v1/lists-update is working correctly" -ForegroundColor Green
} else {
    Write-Host "`nSOME TESTS FAILED" -ForegroundColor Red
    exit 1
}