# leaderboard.ps1

$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey    = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
$email      = "testuser@example.com"
$password   = "TestPass123!"

$authHeaders = @{ "apikey"=$anonKey; "Content-Type"="application/json" }
$authBody    = @{ email=$email; password=$password } | ConvertTo-Json -Compress
$authUrl     = "https://$projectRef.supabase.co/auth/v1/token?grant_type=password"
$auth        = Invoke-RestMethod -Uri $authUrl -Method POST -Headers $authHeaders -Body $authBody
$jwt         = $auth.access_token

if ([string]::IsNullOrWhiteSpace($jwt)) { throw "JWT is empty (auth failed)" }

$baseFn = "https://$projectRef.supabase.co/functions/v1"
$fn     = "$baseFn/leaderboard"

$headers = @{
  "apikey"        = $anonKey
  "Authorization" = "Bearer $jwt"
  "X-API-Version" = "v1"
}

Add-Type -AssemblyName System.Web
function Encode([string]$s) { [System.Web.HttpUtility]::UrlEncode($s) }

$city  = "Tokyo"
$limit = 5

# WEEK
$u1 = "$($fn)?city=$(Encode $city)&range=week&limit=$limit"
Write-Host "GET $u1"
$r1 = Invoke-RestMethod -Uri $u1 -Headers $headers -Method GET
$r1 | ConvertTo-Json

# PAGE 2 (if any)
if ($r1.next_cursor) {
  $u2 = "$($fn)?city=$(Encode $city)&range=week&limit=$limit&cursor=$(Encode $($r1.next_cursor))"
  Write-Host "GET $u2"
  $r2 = Invoke-RestMethod -Uri $u2 -Headers $headers -Method GET
  $r2 | ConvertTo-Json
}

# LIFETIME
$u3 = "$($fn)?city=$(Encode $city)&range=lifetime&limit=$limit"
Write-Host "GET $u3"
$r3 = Invoke-RestMethod -Uri $u3 -Headers $headers -Method GET
$r3 | ConvertTo-Json
