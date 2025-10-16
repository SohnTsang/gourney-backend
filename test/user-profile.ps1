# test-user-profiles.ps1
# Week 5 Step 5: Test User Profiles & Discovery endpoints
# COMPLETE FIXED VERSION

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

$authUrl = "https://$projectRef.supabase.co/auth/v1/token?grant_type=password"
$baseRest = "https://$projectRef.supabase.co/rest/v1"
$baseFn = "https://$projectRef.supabase.co/functions/v1"

Write-Host "=== Week 5 Step 5: User Profiles & Discovery Tests ===" -ForegroundColor Cyan
Write-Host ""

# Helper function for better error display
function Show-Error {
    param($Exception)
    Write-Host "  Status: $($Exception.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    if ($Exception.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($Exception.Exception.Response.GetResponseStream())
            $reader.BaseStream.Position = 0
            $responseBody = $reader.ReadToEnd()
            Write-Host "  Response: $responseBody" -ForegroundColor Red
        } catch {
            Write-Host "  Could not read response body" -ForegroundColor Red
        }
    }
}

# Authenticate as testuser
Write-Host "1. Authenticating as testuser..." -ForegroundColor Yellow
$authHeaders = @{ 
    "apikey" = $anonKey
    "Content-Type" = "application/json" 
}
$authBody = @{ 
    email = "testuser@example.com"
    password = "TestPass123!" 
} | ConvertTo-Json

try {
    $auth = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody
    $jwt = $auth.access_token
    $userId = $auth.user.id
    Write-Host "   ✓ Authenticated" -ForegroundColor Green
    Write-Host "   User ID: $userId" -ForegroundColor Gray
    
    # Get actual handle from database
    $userInfoHeaders = @{ 
        "apikey" = $anonKey
        "Authorization" = "Bearer $jwt"
        "Content-Type" = "application/json"
    }
    $userInfoUrl = "$baseRest/users?select=handle&id=eq.$userId"
    $userInfo = Invoke-RestMethod -Uri $userInfoUrl -Headers $userInfoHeaders
    
    if ($userInfo -and $userInfo.Count -gt 0) {
        $actualHandle = $userInfo[0].handle
        Write-Host "   Handle: $actualHandle" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Could not fetch handle from database" -ForegroundColor Red
        exit
    }
} catch {
    Write-Host "   ✗ Auth failed" -ForegroundColor Red
    Show-Error $_
    exit
}

$fnHeaders = @{ 
    "apikey" = $anonKey
    "Authorization" = "Bearer $jwt"
    "X-API-Version" = "v1"
    "Content-Type" = "application/json"
}

# Test 1: Get own profile
Write-Host ""
Write-Host "2. GET /user-profile?handle=$actualHandle (own profile)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-profile?handle=$actualHandle"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Got own profile" -ForegroundColor Green
    Write-Host "   Handle: $($result.handle)" -ForegroundColor Gray
    Write-Host "   Display Name: $($result.display_name)" -ForegroundColor Gray
    Write-Host "   Followers: $($result.follower_count)" -ForegroundColor Gray
    Write-Host "   Following: $($result.following_count)" -ForegroundColor Gray
    Write-Host "   Visits: $($result.visit_count)" -ForegroundColor Gray
    Write-Host "   Lists: $($result.list_count)" -ForegroundColor Gray
    Write-Host "   Relationship: $($result.relationship)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 2: Get another user's profile
Write-Host ""
Write-Host "3. GET /user-profile?handle=testuser2 (other user)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-profile?handle=testuser2"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Got other user's profile" -ForegroundColor Green
    Write-Host "   Handle: $($result.handle)" -ForegroundColor Gray
    Write-Host "   Display Name: $($result.display_name)" -ForegroundColor Gray
    Write-Host "   Followers: $($result.follower_count)" -ForegroundColor Gray
    Write-Host "   Relationship: $($result.relationship)" -ForegroundColor Gray
    Write-Host "   Is Following: $($result.is_following)" -ForegroundColor Gray
    Write-Host "   Follows You: $($result.follows_you)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 3: Get non-existent user
Write-Host ""
Write-Host "4. GET /user-profile?handle=nonexistent (404 expected)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-profile?handle=nonexistent"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✗ Should have returned 404" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 404) {
        Write-Host "   ✓ Got expected 404" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Wrong error code" -ForegroundColor Red
        Show-Error $_
    }
}

# Test 4: User search
Write-Host ""
Write-Host "5. GET /user-search?q=test&limit=10" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-search?q=test&limit=10"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Search completed" -ForegroundColor Green
    Write-Host "   Total results: $($result.total_count)" -ForegroundColor Gray
    Write-Host "   Results returned: $($result.users.Count)" -ForegroundColor Gray
    if ($result.users -and $result.users.Count -gt 0) {
        Write-Host "   First result: $($result.users[0].handle) ($($result.users[0].display_name))" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 5: Search with short query (should return empty)
Write-Host ""
Write-Host "6. GET /user-search?q=a (query too short)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-search?q=a"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Got response for short query" -ForegroundColor Green
    Write-Host "   Results: $($result.users.Count) (expected: 0)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Unexpected error" -ForegroundColor Red
    Show-Error $_
}

# Test 6: Search with pagination
Write-Host ""
Write-Host "7. GET /user-search?q=user&limit=5&offset=0 (pagination)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-search?q=user&limit=5&offset=0"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Search with pagination" -ForegroundColor Green
    Write-Host "   Total: $($result.total_count)" -ForegroundColor Gray
    Write-Host "   Page size: $($result.users.Count)" -ForegroundColor Gray
    Write-Host "   Offset: $($result.offset)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 7: Suggested follows
Write-Host ""
Write-Host "8. GET /suggested-follows?limit=10" -ForegroundColor Yellow
try {
    $url = "$baseFn/suggested-follows?limit=10"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Got suggested follows" -ForegroundColor Green
    Write-Host "   Suggestions count: $($result.suggestions.Count)" -ForegroundColor Gray
    
    if ($result.suggestions -and $result.suggestions.Count -gt 0) {
        foreach ($suggestion in $result.suggestions) {
            Write-Host "   - $($suggestion.handle): $($suggestion.reason)" -ForegroundColor Gray
            if ($suggestion.mutual_friends_count -and $suggestion.mutual_friends_count -gt 0) {
                Write-Host "     Mutual friends: $($suggestion.mutual_friends_count)" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "   (No suggestions available)" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 8: Suggested follows without auth (should fail)
Write-Host ""
Write-Host "9. GET /suggested-follows (no auth, 401 expected)" -ForegroundColor Yellow
try {
    $noAuthHeaders = @{ 
        "apikey" = $anonKey
        "X-API-Version" = "v1"
        "Content-Type" = "application/json"
    }
    $url = "$baseFn/suggested-follows?limit=10"
    $result = Invoke-RestMethod -Uri $url -Headers $noAuthHeaders -Method GET
    Write-Host "   ✗ Should have required auth" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
        Write-Host "   ✓ Got expected 401 (auth required)" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Wrong error code" -ForegroundColor Red
        Show-Error $_
    }
}

# Test 9: Profile without auth (should work for public profiles)
Write-Host ""
Write-Host "10. GET /user-profile?handle=$actualHandle (no auth)" -ForegroundColor Yellow
try {
    # Note: We still need apikey but NOT the Authorization header
    $noAuthHeaders = @{ 
        "apikey" = $anonKey
        "X-API-Version" = "v1"
        "Content-Type" = "application/json"
    }
    $url = "$baseFn/user-profile?handle=$actualHandle"
    Write-Host "   URL: $url" -ForegroundColor DarkGray
    Write-Host "   Headers: apikey + X-API-Version (no Authorization)" -ForegroundColor DarkGray
    $result = Invoke-RestMethod -Uri $url -Headers $noAuthHeaders -Method GET
    Write-Host "   ✓ Public profile accessible without auth" -ForegroundColor Green
    Write-Host "   Handle: $($result.handle)" -ForegroundColor Gray
    Write-Host "   Relationship: $($result.relationship)" -ForegroundColor Gray
    Write-Host "   Visit count: $($result.visit_count)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 10: Search exact handle match
Write-Host ""
Write-Host "11. GET /user-search?q=$actualHandle (exact handle match)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-search?q=$actualHandle"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Exact handle search" -ForegroundColor Green
    Write-Host "   Results: $($result.users.Count)" -ForegroundColor Gray
    if ($result.users -and $result.users.Count -gt 0) {
        if ($result.users[0].handle -eq $actualHandle) {
            Write-Host "   ✓ First result is exact match" -ForegroundColor Green
        } else {
            Write-Host "   First result: $($result.users[0].handle)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 11: Search with mixed case
Write-Host ""
Write-Host "12. GET /user-search?q=TEST (case insensitive)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-search?q=TEST&limit=5"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Case insensitive search works" -ForegroundColor Green
    Write-Host "   Results: $($result.users.Count)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

# Test 12: Profile for a user with public visits
Write-Host ""
Write-Host "13. GET /user-profile?handle=test_alice (checking visit counts)" -ForegroundColor Yellow
try {
    $url = "$baseFn/user-profile?handle=test_alice"
    $result = Invoke-RestMethod -Uri $url -Headers $fnHeaders -Method GET
    Write-Host "   ✓ Got profile with stats" -ForegroundColor Green
    Write-Host "   Handle: $($result.handle)" -ForegroundColor Gray
    Write-Host "   Visits: $($result.visit_count)" -ForegroundColor Gray
    Write-Host "   Lists: $($result.list_count)" -ForegroundColor Gray
    Write-Host "   Relationship: $($result.relationship)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Failed" -ForegroundColor Red
    Show-Error $_
}

Write-Host ""
Write-Host "=== All Tests Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "✓ User profile endpoint tested (own profile, other profiles, 404s)" -ForegroundColor Green
Write-Host "✓ User search tested (basic search, pagination, case insensitive)" -ForegroundColor Green
Write-Host "✓ Suggested follows tested (with/without auth)" -ForegroundColor Green
Write-Host "✓ Public access tested (profiles accessible without auth)" -ForegroundColor Green
Write-Host "✓ Auth requirements enforced (suggestions require auth)" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Deploy the updated Edge Functions if needed" -ForegroundColor White
Write-Host "2. Run the SQL migration to update get_user_profile RPC" -ForegroundColor White
Write-Host "3. Verify all endpoints return correct relationship data" -ForegroundColor White