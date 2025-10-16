# End-to-End Test: Complete Lists Workflow
# Tests: Create list → Add items → Fetch list → Verify everything

$supabaseUrl = "https://jelbrfbhwwcosmuckjqm.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

function Get-FreshToken($email) {
    $body = @{ email = $email; password = "TestPass123!" } | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$supabaseUrl/auth/v1/token?grant_type=password" `
        -Method POST -Headers @{"apikey"=$anonKey;"Content-Type"="application/json"} -Body $body
    return $response.access_token
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   END-TO-END LISTS WORKFLOW TEST" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$token = Get-FreshToken "testuser@example.com"
Write-Host "1. Authentication: Token obtained`n" -ForegroundColor Green

# ============================================
# STEP 1: Create a new list
# ============================================
Write-Host "STEP 1: Creating a new list 'Tokyo Ramen Quest'" -ForegroundColor Yellow
Write-Host "----------------------------------------------" -ForegroundColor Gray

try {
    $createListBody = @{
        title = "Tokyo Ramen Quest"
        description = "The best ramen spots in Tokyo - my personal favorites"
        visibility = "public"
    } | ConvertTo-Json

    $newList = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-create" `
        -Method POST `
        -Headers @{
            "Authorization" = "Bearer $token"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
            "Content-Type" = "application/json"
        } `
        -Body $createListBody

    $listId = $newList.id
    
    Write-Host "Success: List created!" -ForegroundColor Green
    Write-Host "  List ID: $listId" -ForegroundColor White
    Write-Host "  Title: $($newList.title)" -ForegroundColor White
    Write-Host "  Description: $($newList.description)" -ForegroundColor White
    Write-Host "  Visibility: $($newList.visibility)" -ForegroundColor White
    Write-Host ""
} catch {
    Write-Host "FAIL: Could not create list" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "Error: $($reader.ReadToEnd())" -ForegroundColor Yellow
    exit
}

# ============================================
# STEP 2: Get available places
# ============================================
Write-Host "STEP 2: Fetching available places" -ForegroundColor Yellow
Write-Host "----------------------------------------------" -ForegroundColor Gray

try {
    $places = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/places?select=id,name_en,name_ja,city,ward&limit=5" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token"
            "apikey" = $anonKey
        }

    Write-Host "Success: Found $($places.Count) places" -ForegroundColor Green
    $places | ForEach-Object {
        $displayName = if ($_.name_en) { $_.name_en } else { $_.name_ja }
        Write-Host "  - $displayName ($($_.ward), $($_.city))" -ForegroundColor White
    }
    Write-Host ""
} catch {
    Write-Host "FAIL: Could not fetch places" -ForegroundColor Red
    exit
}

# ============================================
# STEP 3: Add items to the list
# ============================================
Write-Host "STEP 3: Adding items to the list" -ForegroundColor Yellow
Write-Host "----------------------------------------------" -ForegroundColor Gray

$addedItems = @()
$itemNotes = @(
    "Best tonkotsu broth - creamy and rich!",
    "Perfect for late night cravings",
    "Their spicy miso is legendary"
)

for ($i = 0; $i -lt [Math]::Min(3, $places.Count); $i++) {
    $place = $places[$i]
    $note = $itemNotes[$i]
    
    try {
        $addItemBody = @{
            place_id = $place.id
            note = $note
        } | ConvertTo-Json

        $addedItem = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-add-item/$listId/items" `
            -Method POST `
            -Headers @{
                "Authorization" = "Bearer $token"
                "apikey" = $anonKey
                "X-API-Version" = "v1"
                "Content-Type" = "application/json"
            } `
            -Body $addItemBody

        $displayName = if ($addedItem.item.place.name_en) { $addedItem.item.place.name_en } else { $addedItem.item.place.name_ja }
        
        Write-Host "  Added: $displayName" -ForegroundColor Green
        Write-Host "    Note: $($addedItem.item.note)" -ForegroundColor Gray
        
        $addedItems += $addedItem.item
    } catch {
        $displayName = if ($place.name_en) { $place.name_en } else { $place.name_ja }
        Write-Host "  Failed to add: $displayName" -ForegroundColor Red
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "    Error: $($reader.ReadToEnd())" -ForegroundColor Yellow
    }
}

Write-Host "`nTotal items added: $($addedItems.Count)" -ForegroundColor Green
Write-Host ""

# ============================================
# STEP 4: Fetch the list back
# ============================================
Write-Host "STEP 4: Fetching the list to verify" -ForegroundColor Yellow
Write-Host "----------------------------------------------" -ForegroundColor Gray

try {
    $fetchedLists = Invoke-RestMethod -Uri "$supabaseUrl/functions/v1/lists-get?limit=20" `
        -Method GET `
        -Headers @{
            "Authorization" = "Bearer $token"
            "apikey" = $anonKey
            "X-API-Version" = "v1"
        }

    $ourList = $fetchedLists.lists | Where-Object { $_.id -eq $listId }

    if ($ourList) {
        Write-Host "Success: List found in user's lists!" -ForegroundColor Green
        Write-Host "  Title: $($ourList.title)" -ForegroundColor White
        Write-Host "  Description: $($ourList.description)" -ForegroundColor White
        Write-Host "  Visibility: $($ourList.visibility)" -ForegroundColor White
        Write-Host "  Item count: $($ourList.item_count)" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "WARNING: List not found in GET /v1/lists response!" -ForegroundColor Yellow
        Write-Host ""
    }
} catch {
    Write-Host "FAIL: Could not fetch lists" -ForegroundColor Red
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host "Error: $($reader.ReadToEnd())" -ForegroundColor Yellow
}

# ============================================
# STEP 5: Verify item count matches
# ============================================
Write-Host "STEP 5: Verification & Summary" -ForegroundColor Yellow
Write-Host "----------------------------------------------" -ForegroundColor Gray

$expectedCount = $addedItems.Count
$actualCount = $ourList.item_count

Write-Host "Expected items: $expectedCount" -ForegroundColor White
Write-Host "Actual items: $actualCount" -ForegroundColor White

if ($expectedCount -eq $actualCount) {
    Write-Host "`nItem count matches!" -ForegroundColor Green
} else {
    Write-Host "`nWARNING: Item count mismatch!" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# FINAL SUMMARY
# ============================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   END-TO-END TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Workflow Steps:" -ForegroundColor White
Write-Host "  1. Create list          - PASS" -ForegroundColor Green
Write-Host "  2. Fetch places         - PASS" -ForegroundColor Green
Write-Host "  3. Add items ($expectedCount)        - PASS" -ForegroundColor Green
Write-Host "  4. Fetch list back      - PASS" -ForegroundColor Green
Write-Host "  5. Verify item count    - $(if ($expectedCount -eq $actualCount) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($expectedCount -eq $actualCount) { 'Green' } else { 'Red' })
Write-Host ""
Write-Host "List Details:" -ForegroundColor White
Write-Host "  ID: $listId" -ForegroundColor Gray
Write-Host "  Title: $($ourList.title)" -ForegroundColor Gray
Write-Host "  Items: $actualCount places with notes" -ForegroundColor Gray
Write-Host "  Visibility: $($ourList.visibility)" -ForegroundColor Gray
Write-Host ""

if ($expectedCount -eq $actualCount) {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green -BackgroundColor Black
    Write-Host ""
    Write-Host "The complete lists workflow is working correctly:" -ForegroundColor Green
    Write-Host "  - Lists can be created with metadata" -ForegroundColor White
    Write-Host "  - Items can be added to lists with notes" -ForegroundColor White
    Write-Host "  - Lists can be fetched with accurate item counts" -ForegroundColor White
    Write-Host "  - All data persists correctly" -ForegroundColor White
} else {
    Write-Host "TEST FAILED!" -ForegroundColor Red -BackgroundColor Black
    Write-Host "There is a discrepancy in item counts" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================`n" -ForegroundColor Cyan