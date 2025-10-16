@echo off
setlocal enabledelayedexpansion

set PROJECT_REF=jelbrfbhwwcosmuckjqm
set ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck
set AUTH_URL=https://%PROJECT_REF%.supabase.co/auth/v1/token?grant_type=password
set SUBMIT_URL=https://%PROJECT_REF%.supabase.co/functions/v1/ugc-places-submit

echo ============================================
echo   UTF-8 TEST WITH CURL
echo ============================================

echo.
echo --- Authenticating ---
curl -s -X POST "%AUTH_URL%" ^
  -H "apikey: %ANON_KEY%" ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"testuser@example.com\",\"password\":\"TestPass123!\"}" > auth.json

for /f "tokens=*" %%a in ('type auth.json ^| jq -r .access_token') do set JWT=%%a
for /f "tokens=*" %%a in ('type auth.json ^| jq -r .user.id') do set USER_ID=%%a

echo User ID: %USER_ID%
echo JWT: %JWT:~0,50%...

echo.
echo --- Test 1: Japanese name (つじ田) ---
curl -s -X POST "%SUBMIT_URL%" ^
  -H "apikey: %ANON_KEY%" ^
  -H "Authorization: Bearer %JWT%" ^
  -H "Content-Type: application/json; charset=utf-8" ^
  -H "X-API-Version: v1" ^
  -d "{\"name_ja\":\"つじ田\",\"lat\":35.6595,\"lng\":139.7020}" > response1.json

type response1.json | jq .

echo.
echo --- Test 2: Chinese name (辻田) ---
curl -s -X POST "%SUBMIT_URL%" ^
  -H "apikey: %ANON_KEY%" ^
  -H "Authorization: Bearer %JWT%" ^
  -H "Content-Type: application/json; charset=utf-8" ^
  -H "X-API-Version: v1" ^
  -d "{\"name_zh\":\"辻田\",\"lat\":35.6596,\"lng\":139.7021}" > response2.json

type response2.json | jq .

echo.
echo --- Test 3: Trilingual ---
curl -s -X POST "%SUBMIT_URL%" ^
  -H "apikey: %ANON_KEY%" ^
  -H "Authorization: Bearer %JWT%" ^
  -H "Content-Type: application/json; charset=utf-8" ^
  -H "X-API-Version: v1" ^
  -d "{\"name_en\":\"Tsujita Ramen\",\"name_ja\":\"つじ田\",\"name_zh\":\"辻田\",\"city\":\"Tokyo\",\"lat\":35.6597,\"lng\":139.7022}" > response3.json

type response3.json | jq .
for /f "tokens=*" %%a in ('type response3.json ^| jq -r .place_id') do set PLACE_ID=%%a

echo.
echo --- Verifying stored data for Place ID: %PLACE_ID% ---
timeout /t 2 /nobreak > nul

curl -s "https://%PROJECT_REF%.supabase.co/rest/v1/places?select=name_en,name_ja,name_zh&id=eq.%PLACE_ID%" ^
  -H "apikey: %ANON_KEY%" ^
  -H "Authorization: Bearer %JWT%" | jq .

echo.
echo ============================================
echo   TEST COMPLETE
echo ============================================

del auth.json response1.json response2.json response3.json 2>nul