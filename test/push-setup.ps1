# verify-push-setup.ps1
# Verify push notification infrastructure is set up correctly

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"

Write-Host "=== Push Notification Setup Verification ===" -ForegroundColor Cyan

$baseUrl = "https://$projectRef.supabase.co/rest/v1"
$headers = @{ "apikey" = $anonKey }

# Check 1: Tables exist
Write-Host "`n1. Checking database tables..." -ForegroundColor Yellow
$checks = @(
    @{ table = "devices"; desc = "Device token storage" },
    @{ table = "notification_log"; desc = "Notification queue" }
)

foreach ($check in $checks) {
    try {
        $url = "$baseUrl/$($check.table)?select=count&limit=0"
        Invoke-RestMethod -Uri $url -Headers $headers -Method HEAD | Out-Null
        Write-Host "  ✓ $($check.table) - $($check.desc)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ $($check.table) - NOT FOUND" -ForegroundColor Red
    }
}

# Check 2: Functions deployed
Write-Host "`n2. Checking Edge Functions..." -ForegroundColor Yellow
$functions = @(
    "device-register",
    "device-update-preferences",
    "device-reset-badge",
    "process-notifications"
)

foreach ($func in $functions) {
    try {
        $url = "https://$projectRef.supabase.co/functions/v1/$func"
        Invoke-RestMethod -Uri $url -Method OPTIONS -ErrorAction Stop | Out-Null
        Write-Host "  ✓ $func" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ $func - NOT DEPLOYED" -ForegroundColor Red
    }
}

# Check 3: Triggers exist
Write-Host "`n3. Database triggers (requires auth)..." -ForegroundColor Yellow
Write-Host "  Run this SQL to verify:" -ForegroundColor Gray
Write-Host "  SELECT trigger_name FROM information_schema.triggers" -ForegroundColor Gray
Write-Host "  WHERE event_object_table = 'activity'" -ForegroundColor Gray
Write-Host "  AND trigger_name = 'trigger_auto_queue_notification';" -ForegroundColor Gray

Write-Host "`n=== Verification Complete ===" -ForegroundColor Cyan
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Get APNs credentials from Apple Developer Portal" -ForegroundColor White
Write-Host "2. Set environment variables (APNS_TEAM_ID, APNS_KEY_ID, etc.)" -ForegroundColor White
Write-Host "3. Run .\test-push-notifications.ps1 to test" -ForegroundColor White
Write-Host "4. Set up cron job to auto-process notifications" -ForegroundColor White