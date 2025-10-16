# Test POST /v1/lists/:id/items

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

function Get-FreshToken($email) {
    $body = @{ email = $email; password = "TestPass123!" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
        -Method POST -Headers @{"apikey"=$anonKey;"Content-Type"="application/json"} -Body $body
    return $response.access_token
}

Write-Host "`n=== Testing POST /v1/lists/:id/items ===" -ForegroundColor Cyan

$token1 = Get-FreshToken "testuser@example.com"
$token2 = Get-FreshToken "testuser2@example.com"
Write-Host "✅ Tokens obtained`n" -ForegroundColor Green

# Create a fresh test list for user 1
Write-Host "Creating test list for user 1..." -ForegroundColor Gray
try {
    $newList = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} `
        -Body (@{ title = "Test List for Items"; visibility = "public" } | ConvertTo-Json)
    $listId = $newList.id
    Write-Host "✅ Created list ID: $listId`n" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create list" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "Error: $($reader.ReadToEnd())" -ForegroundColor Yellow
    exit
}

# Get place IDs
Write-Host "Getting place IDs..." -ForegroundColor Gray
$places = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/places?select=id,name_en,name_ja&limit=3" `
    -Method GET -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey}

if ($places.Count -eq 0) {
    Write-Host "❌ ERROR: No places found in database. Cannot test." -ForegroundColor Red
    exit
}

$place1 = $places[0]
$place2 = if ($places.Count -gt 1) { $places[1] } else { $null }
$placeName1 = if ($place1.name_en) { $place1.name_en } else { $place1.name_ja }
Write-Host "Place 1: $placeName1 ($($place1.id))" -ForegroundColor Gray
if ($place2) {
    $placeName2 = if ($place2.name_en) { $place2.name_en } else { $place2.name_ja }
    Write-Host "Place 2: $placeName2 ($($place2.id))`n" -ForegroundColor Gray
}

# TEST 1: Add item with notes
Write-Host "TEST 1: Add item with notes" -ForegroundColor Yellow
try {
    $body = @{
        place_id = $place1.id
        note = "Must try the special ramen!"
    } | ConvertTo-Json

    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body

    Write-Host "✅ Success: $($result.StatusCode)" -ForegroundColor Green
    Write-Host "   Item ID: $($result.item.id)" -ForegroundColor Gray
    $displayName = if ($result.item.place.name_en) { $result.item.place.name_en } else { $result.item.place.name_ja }
    Write-Host "   Place: $displayName" -ForegroundColor Gray
    Write-Host "   Notes: '$($result.item.note)'" -ForegroundColor Gray
    Write-Host "   Created: $($result.item.created_at)`n" -ForegroundColor Gray
    
    $itemId1 = $result.item.id
} catch {
    Write-Host "❌ FAIL" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "   Error: $($reader.ReadToEnd())`n" -ForegroundColor Yellow
}

# TEST 2: Add duplicate item (should fail with 409)
Write-Host "TEST 2: Add duplicate item (should 409)" -ForegroundColor Yellow
try {
    $body = @{
        place_id = $place1.id
        note = "Different note"
    } | ConvertTo-Json

    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body

    Write-Host "❌ FAIL - Should return 409`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409) {
        Write-Host "✅ PASS - Duplicate rejected (409)" -ForegroundColor Green
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "   Error: $($reader.ReadToEnd())`n" -ForegroundColor Gray
    } else {
        Write-Host "❌ FAIL - Wrong status: $($_.Exception.Response.StatusCode.value__)`n" -ForegroundColor Red
    }
}

# TEST 3: Add item without notes
if ($place2) {
    Write-Host "TEST 3: Add item without notes" -ForegroundColor Yellow
    try {
        $body = @{ place_id = $place2.id } | ConvertTo-Json

        $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
            -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body

        Write-Host "✅ PASS" -ForegroundColor Green
        $displayName = if ($result.item.place.name_en) { $result.item.place.name_en } else { $result.item.place.name_ja }
        Write-Host "   Place: $displayName" -ForegroundColor Gray
        Write-Host "   Note: $($result.item.note) (null)`n" -ForegroundColor Gray
    } catch {
        Write-Host "❌ FAIL`n" -ForegroundColor Red
    }
}

# TEST 4: Missing place_id (should 400)
Write-Host "TEST 4: Missing place_id (should 400)" -ForegroundColor Yellow
try {
    $body = @{ note = "No place ID" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL - Should return 400`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "✅ PASS - Validation error (400)`n" -ForegroundColor Green
    }
}

# TEST 5: Invalid place_id (should 404)
Write-Host "TEST 5: Invalid place_id (should 404)" -ForegroundColor Yellow
try {
    $body = @{ place_id = "00000000-0000-0000-0000-000000000000" } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL - Should return 404`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 404) {
        Write-Host "✅ PASS - Place not found (404)`n" -ForegroundColor Green
    }
}

# TEST 6: User 2 tries to add to User 1's list (should 403)
Write-Host "TEST 6: Unauthorized user tries to add item (should 403)" -ForegroundColor Yellow
try {
    $body = @{ place_id = $place1.id } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token2";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL - Should return 403`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 403) {
        Write-Host "✅ PASS - Authorization denied (403)`n" -ForegroundColor Green
    }
}

# TEST 7: Notes too long (should 400)
Write-Host "TEST 7: Notes too long (should 400)" -ForegroundColor Yellow
try {
    $longNotes = "A" * 201
    $body = @{ place_id = $place1.id; note = $longNotes } | ConvertTo-Json
    $result = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
        -Method POST -Headers @{"Authorization"="Bearer $token1";"apikey"=$anonKey;"X-API-Version"="v1";"Content-Type"="application/json"} -Body $body
    Write-Host "❌ FAIL - Should return 400`n" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 400) {
        Write-Host "✅ PASS - Validation error (400)`n" -ForegroundColor Green
    }
}

Write-Host "=== Step 5 Complete ===" -ForegroundColor Cyan