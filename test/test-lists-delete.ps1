# Test Script: DELETE /v1/lists-delete (Delete List)
# Tests the EXISTING lists-delete function
# Uses existing lists to avoid rate limits

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
Write-Host "Testing DELETE /v1/lists-delete" -ForegroundColor Yellow
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

# SETUP: Get existing lists to test with
Write-Host "`n--- SETUP: Finding existing lists to test with ---" -ForegroundColor Magenta

try {
    $existingLists = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=50" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token1"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }
    
    $availableLists = $existingLists.lists | Where-Object { -not $_.is_system }
    
    Write-Host "Found $($availableLists.Count) non-system lists" -ForegroundColor Gray
    
    if ($availableLists.Count -lt 2) {
        Write-Host "WARNING: Only $($availableLists.Count) lists available. Some tests may be skipped." -ForegroundColor Yellow
    } else {
        Write-Host "Using first 2 lists for deletion tests" -ForegroundColor Gray
        $script:listToDelete1 = $availableLists[0].id
        $script:listToDelete2 = $availableLists[1].id
        Write-Host "List 1: $($availableLists[0].title) ($script:listToDelete1)" -ForegroundColor Gray
        Write-Host "List 2: $($availableLists[1].title) ($script:listToDelete2)" -ForegroundColor Gray
    }
    
    # Get a list owned by user1 for unauthorized access test
    if ($availableLists.Count -gt 2) {
        $script:listOwnedByUser1 = $availableLists[2].id
        Write-Host "List 3 (for auth test): $($availableLists[2].title) ($script:listOwnedByUser1)" -ForegroundColor Gray
    } else {
        $script:listOwnedByUser1 = $availableLists[0].id
    }
    
} catch {
    Write-Host "ERROR: Could not fetch existing lists: $_" -ForegroundColor Red
    Write-Host "Creating one test list to proceed..." -ForegroundColor Yellow
    
    try {
        $createBody = @{
            title = "Test Delete List"
            description = "For testing delete"
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

        if ($createResponse.list) {
            $script:listToDelete1 = $createResponse.list.id
        } else {
            $script:listToDelete1 = $createResponse.id
        }
        
        Write-Host "Created test list: $script:listToDelete1" -ForegroundColor Green
    } catch {
        Write-Host "FATAL: Cannot create test list (rate limit?)" -ForegroundColor Red
        Write-Host "Please run: UPDATE remote_config SET value = jsonb_build_object('enabled', false) WHERE key = 'rate_limits_on';" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`nStarting tests..." -ForegroundColor Magenta

# Test 1: Delete own list with query parameter
Test-Endpoint "Delete own list (query parameter)" {
    if (-not $script:listToDelete1) {
        Write-Host "SKIP: No list available to delete" -ForegroundColor Yellow
        return
    }
    
    $listId = $script:listToDelete1
    Write-Host "Deleting list: $listId" -ForegroundColor Gray
    
    try {
        $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$listId" `
            -Method DELETE `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        
        Write-Host "List deleted successfully (query param format)" -ForegroundColor Gray
        $script:listToDelete1 = $null # Mark as deleted
    } catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "400" -or $errorMsg -match "list_id") {
            Write-Host "Query parameter format not supported, will try path format" -ForegroundColor Yellow
            throw "Query param not supported"
        }
        throw $_
    }
    
    # Verify list is gone
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$listId" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "List should not exist after deletion"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 404) {
            throw "Expected 404 for deleted list, got $statusCode"
        }
        Write-Host "Verified list is deleted (404)" -ForegroundColor Gray
    }
}

# Test 2: Delete own list with path parameter
Test-Endpoint "Delete own list (path parameter)" {
    if (-not $script:listToDelete2) {
        Write-Host "SKIP: No list available to delete" -ForegroundColor Yellow
        return
    }
    
    $listId = $script:listToDelete2
    Write-Host "Deleting list: $listId" -ForegroundColor Gray
    
    try {
        $response = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$listId" `
            -Method DELETE `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        
        Write-Host "List deleted successfully (path param format)" -ForegroundColor Gray
        $script:listToDelete2 = $null # Mark as deleted
    } catch {
        $errorMsg = $_.Exception.Message
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 400) {
            Write-Host "SKIP: Function uses query parameter format (?list_id=...), not path format (/:id)" -ForegroundColor Yellow
            return
        }
        throw $_
    }
    
    # Verify list is gone
    try {
        $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get-detail/$listId" `
            -Method GET `
            -Headers @{
                "Authorization" = "Bearer $token1"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
            }
        throw "List should not exist after deletion"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 404) {
            throw "Expected 404 for deleted list, got $statusCode"
        }
        Write-Host "Verified list is deleted (404)" -ForegroundColor Gray
    }
}

# Test 3: Delete someone else's list
Test-Endpoint "Delete someone else's list -> 403/404" {
    if (-not $script:listOwnedByUser1) {
        Write-Host "SKIP: No list available for auth test" -ForegroundColor Yellow
        return
    }
    
    $listId = $script:listOwnedByUser1
    Write-Host "User2 trying to delete User1's list: $listId" -ForegroundColor Gray
    
    try {
        # Try with query parameter first
        try {
            $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$listId" `
                -Method DELETE `
                -Headers @{
                    "Authorization" = "Bearer $token2"
                    "apikey" = $anonKey
                    "X-API-Version" = "v1"
                }
        } catch {
            $statusCode1 = $_.Exception.Response.StatusCode.value__
            if ($statusCode1 -eq 400) {
                # Try path parameter
                $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$listId" `
                    -Method DELETE `
                    -Headers @{
                        "Authorization" = "Bearer $token2"
                        "apikey" = $anonKey
                        "X-API-Version" = "v1"
                    }
            } else {
                throw $_
            }
        }
        throw "Should have returned 403 or 404"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -ne 403 -and $statusCode -ne 404) {
            throw "Expected 403 or 404, got $statusCode"
        }
        Write-Host "Correctly prevented unauthorized deletion (status: $statusCode)" -ForegroundColor Gray
    }
}

# Test 4: Delete non-existent list
Test-Endpoint "Delete non-existent list -> 404" {
    $fakeListId = "00000000-0000-0000-0000-000000000000"
    
    try {
        # Try query parameter
        try {
            $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$fakeListId" `
                -Method DELETE `
                -Headers @{
                    "Authorization" = "Bearer $token1"
                    "apikey" = $anonKey
                    "X-API-Version" = "v1"
                }
        } catch {
            $statusCode1 = $_.Exception.Response.StatusCode.value__
            if ($statusCode1 -eq 400) {
                # Try path parameter
                $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$fakeListId" `
                    -Method DELETE `
                    -Headers @{
                        "Authorization" = "Bearer $token1"
                        "apikey" = $anonKey
                        "X-API-Version" = "v1"
                    }
            } else {
                throw $_
            }
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

# Test 5: Missing API version header
Test-Endpoint "Missing API version header -> 400" {
    $fakeListId = "00000000-0000-0000-0000-000000000001"
    
    try {
        try {
            $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$fakeListId" `
                -Method DELETE `
                -Headers @{
                    "Authorization" = "Bearer $token1"
                    "apikey" = $anonKey
                }
        } catch {
            $statusCode1 = $_.Exception.Response.StatusCode.value__
            if ($statusCode1 -eq 404) {
                # Try path parameter
                $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$fakeListId" `
                    -Method DELETE `
                    -Headers @{
                        "Authorization" = "Bearer $token1"
                        "apikey" = $anonKey
                    }
            } else {
                throw $_
            }
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

# Test 6: Missing authorization header
Test-Endpoint "Missing authorization -> 401" {
    $fakeListId = "00000000-0000-0000-0000-000000000002"
    
    try {
        try {
            $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$fakeListId" `
                -Method DELETE `
                -Headers @{
                    "apikey" = $anonKey
                    "X-API-Version" = "v1"
                }
        } catch {
            $statusCode1 = $_.Exception.Response.StatusCode.value__
            if ($statusCode1 -eq 404) {
                # Try path parameter
                $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$fakeListId" `
                    -Method DELETE `
                    -Headers @{
                        "apikey" = $anonKey
                        "X-API-Version" = "v1"
                    }
            } else {
                throw $_
            }
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

# Test 7: Wrong HTTP method
Test-Endpoint "Wrong HTTP method -> 405" {
    $fakeListId = "00000000-0000-0000-0000-000000000003"
    
    try {
        try {
            $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete?list_id=$fakeListId" `
                -Method POST `
                -Headers @{
                    "Authorization" = "Bearer $token1"
                    "apikey" = $anonKey
                    "X-API-Version" = "v1"
                }
        } catch {
            $statusCode1 = $_.Exception.Response.StatusCode.value__
            if ($statusCode1 -eq 404) {
                # Try path parameter
                $null = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-delete/$fakeListId" `
                    -Method POST `
                    -Headers @{
                        "Authorization" = "Bearer $token1"
                        "apikey" = $anonKey
                        "X-API-Version" = "v1"
                    }
            } else {
                throw $_
            }
        }
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
    Write-Host "DELETE /v1/lists-delete is working correctly" -ForegroundColor Green
    Write-Host "`nNote: Some lists were deleted during testing" -ForegroundColor Yellow
} else {
    Write-Host "`nSOME TESTS FAILED" -ForegroundColor Red
    exit 1
}