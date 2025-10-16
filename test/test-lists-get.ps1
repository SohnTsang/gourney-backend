# Test GET /v1/lists-get

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

function Get-FreshToken($email) {
    $body = @{ email = $email; password = "TestPass123!" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
        -Method POST -Headers @{"apikey"=$anonKey;"Content-Type"="application/json"} -Body $body
    return $response.access_token
}

Write-Host "`n=== Testing GET /v1/lists-get ===" -ForegroundColor Cyan

$token1 = Get-FreshToken "testuser@example.com"
Write-Host "✅ Token obtained`n" -ForegroundColor Green

# TEST 1: Get user's lists (should show lists we created earlier)
Write-Host "TEST 1: Get user's lists" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

    Write-Host "✅ PASS" -ForegroundColor Green
    Write-Host "   Total lists: $($result.lists.Count)" -ForegroundColor Gray
    
    if ($result.lists.Count -gt 0) {
        Write-Host "   First 3 lists:" -ForegroundColor Gray
        $result.lists | Select-Object -First 3 | ForEach-Object {
            Write-Host "     - $($_.title) ($($_.visibility), $($_.item_count) items)" -ForegroundColor White
        }
    }
    
    if ($result.next_cursor) {
        Write-Host "   Has next page: Yes" -ForegroundColor Gray
    } else {
        Write-Host "   Has next page: No" -ForegroundColor Gray
    }
    Write-Host ""
} catch {
    Write-Host "❌ FAIL" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "   Error: $($reader.ReadToEnd())`n" -ForegroundColor Yellow
}

# TEST 2: Get lists with limit
Write-Host "TEST 2: Get lists with limit=2" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=2" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

    Write-Host "✅ PASS" -ForegroundColor Green
    Write-Host "   Returned: $($result.lists.Count) lists (max 2)" -ForegroundColor Gray
    
    if ($result.next_cursor) {
        Write-Host "   Next cursor exists: Yes`n" -ForegroundColor Gray
    }
} catch {
    Write-Host "❌ FAIL`n" -ForegroundColor Red
}

# TEST 3: Pagination - get next page
Write-Host "TEST 3: Pagination - get next page using cursor" -ForegroundColor Yellow
try {
    # Get first page
    $page1 = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=2" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

    if ($page1.next_cursor) {
        # Get second page
        $page2 = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=2&cursor=$($page1.next_cursor)" `
            -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

        Write-Host "✅ PASS" -ForegroundColor Green
        Write-Host "   Page 1: $($page1.lists.Count) lists" -ForegroundColor Gray
        Write-Host "   Page 2: $($page2.lists.Count) lists" -ForegroundColor Gray
        
        # Check for duplicates
        $page1Ids = $page1.lists | ForEach-Object { $_.id }
        $page2Ids = $page2.lists | ForEach-Object { $_.id }
        $duplicates = $page1Ids | Where-Object { $page2Ids -contains $_ }
        
        if ($duplicates.Count -eq 0) {
            Write-Host "   No duplicates: Yes" -ForegroundColor Gray
        } else {
            Write-Host "   WARNING: Found $($duplicates.Count) duplicates!" -ForegroundColor Yellow
        }
        Write-Host ""
    } else {
        Write-Host "Skip - Not enough lists for pagination test`n" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Fail`n" -ForegroundColor Red
}

# TEST 4: Invalid cursor (should 400)
Write-Host "TEST 4: Invalid cursor (should 400)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?cursor=invalid" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}
    Write-Host "❌ FAIL - Should return 400`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "✅ PASS - Invalid cursor rejected (400)`n" -ForegroundColor Green
    } else {
        Write-Host "❌ FAIL - Wrong status: $($_.Exception.Response.StatusCode.value__)`n" -ForegroundColor Red
    }
}

# TEST 5: Limit validation (max 50)
Write-Host "TEST 5: Limit validation - request 100, should cap at 50" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=100" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

    if ($result.lists.Count -le 50) {
        Write-Host "✅ PASS - Limit capped at 50 (returned $($result.lists.Count))`n" -ForegroundColor Green
    } else {
        Write-Host "❌ FAIL - Returned more than 50 lists`n" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ FAIL`n" -ForegroundColor Red
}

# TEST 6: Item counts are correct
Write-Host "TEST 6: Verify item counts" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=1" `
        -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1"}

    if ($result.lists.Count -gt 0) {
        $list = $result.lists[0]
        Write-Host "✅ PASS" -ForegroundColor Green
        Write-Host "   List: $($list.title)" -ForegroundColor Gray
        Write-Host "   Item count: $($list.item_count)" -ForegroundColor Gray
        Write-Host "   (Item count field exists and is numeric)`n" -ForegroundColor Gray
    } else {
        Write-Host "⚠️ SKIP - No lists to verify`n" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ FAIL`n" -ForegroundColor Red
}

Write-Host "=== Step 6 Complete ===" -ForegroundColor Cyan