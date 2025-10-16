# ================== CONFIG ==================
$projectRef = "jelbrfbhwwcosmuckjqm"
$anonKey    = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"    # keep safe
$email      = "testuser@example.com"
$password   = "TestPass123!"                # adjust if different
$placeId    = "178563c5-42db-4eaa-a4b6-e60c241fe94b"
# ============================================

$fnBase = "https://$projectRef.supabase.co/functions/v1"
$restBase = "https://$projectRef.supabase.co/rest/v1"

function Invoke-WithBodyCapture {
  param(
    [string]$Uri,
    [string]$Method = "GET",
    [hashtable]$Headers,
    [string]$Body = $null
  )
  try {
    if ($Body) {
      return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body
    } else {
      return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers
    }
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $reader = New-Object IO.StreamReader($resp.GetResponseStream())
      $errBody = $reader.ReadToEnd()
      Write-Host "HTTP $($resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Yellow
      Write-Host "URL: $Uri"
      Write-Host "Response body:`n$errBody" -ForegroundColor DarkYellow
    } else {
      Write-Host "Error with no response body: $_" -ForegroundColor Red
    }
    return $null
  }
}

Write-Host "== AUTH (password grant) ==" -ForegroundColor Cyan
$authHeaders = @{
  "apikey"       = $anonKey
  "Content-Type" = "application/json"
}
$authBody = @{ email = $email; password = $password } | ConvertTo-Json

$auth = Invoke-WithBodyCapture -Uri "https://$projectRef.supabase.co/auth/v1/token?grant_type=password" `
        -Method POST -Headers $authHeaders -Body $authBody

if (-not $auth) { Write-Host "Auth failed; aborting." -ForegroundColor Red; exit 1 }

$accessToken  = $auth.access_token
$refreshToken = $auth.refresh_token

Write-Host "Access token looks like JWT? " -NoNewline
if ($accessToken -match '^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$') {
  Write-Host "YES" -ForegroundColor Green
} else {
  Write-Host "NO" -ForegroundColor Red
}

# Decode JWT 'sub' (user id) for sanity
function Decode-Base64Url([string]$s) {
  $s = $s.Replace('-', '+').Replace('_', '/')
  switch ($s.Length % 4) {
    2 { $s += '==' }
    3 { $s += '='  }
  }
  [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($s))
}
function Get-JwtPayload([string]$jwt) {
  $parts = $jwt.Split('.'); if ($parts.Length -ne 3) { return $null }
  (Decode-Base64Url $parts[1]) | ConvertFrom-Json
}
$payload = Get-JwtPayload $accessToken
if ($payload) {
  Write-Host ("JWT sub (user id): {0}" -f $payload.sub) -ForegroundColor Gray
}

$fnHeaders = @{
  "apikey"        = $anonKey
  "Authorization" = "Bearer $accessToken"
  "X-API-Version" = "v1"
}

Write-Host "`n== EDGE FUNCTION TESTS ==" -ForegroundColor Cyan
Invoke-WithBodyCapture -Uri "$fnBase/places-get-visits/$placeId" -Method GET -Headers $fnHeaders | ConvertTo-Json
Invoke-WithBodyCapture -Uri "$fnBase/places-get-visits/$placeId?limit=5" -Method GET -Headers $fnHeaders | ConvertTo-Json
Invoke-WithBodyCapture -Uri "$fnBase/places-get-visits/$placeId?friends_only=true&limit=5" -Method GET -Headers $fnHeaders | ConvertTo-Json

# Try one more: cursor (will likely be null on first run)
$first = Invoke-WithBodyCapture -Uri "$fnBase/places-get-visits/$placeId?limit=2" -Method GET -Headers $fnHeaders
if ($first -and $first.next_cursor) {
  Invoke-WithBodyCapture -Uri "$fnBase/places-get-visits/$placeId?limit=2&cursor=$($first.next_cursor)" -Method GET -Headers $fnHeaders | ConvertTo-Json
} else {
  Write-Host "No next_cursor (ok)." -ForegroundColor Gray
}

Write-Host "`n== DIRECT RPC (bypass Edge) ==" -ForegroundColor Cyan
$rpcHeaders = @{
  "apikey"        = $anonKey
  "Authorization" = "Bearer $accessToken"
  "Content-Type"  = "application/json"
}
$rpcBody = @{
  p_place_id     = $placeId
  p_limit        = 5
  p_cursor       = $null
  p_friends_only = $false
} | ConvertTo-Json

Invoke-WithBodyCapture -Uri "$restBase/rpc/fn_places_get_visits_v1" -Method POST -Headers $rpcHeaders -Body $rpcBody | ConvertTo-Json
