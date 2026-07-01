#!/bin/bash
# save as: test_sso.sh
# chmod +x test_sso.sh && ./test_sso.sh

SSO_HOST="https://auth-sso2fa.mobifone.vn"
SSO_API_PORT="8015"
SSO_AUTH_PORT="8080"
REALM="sso-mobifone"
CLIENT_ID="CLIENT-MLMT"
CLIENT_SECRET="gy2xyLo1hmRpd1Z61Hc3g7rTz51q5T4C"
USERNAME="admin_mlmt@mobifone.vn"
PASSWORD="Mobifone@123"

echo "========================================"
echo "TEST 1: SSO API Login (port 8015)"
echo "========================================"
RESPONSE=$(curl -sk -X POST \
  "https://auth-sso2fa.mobifone.vn:${SSO_API_PORT}/login" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${USERNAME}\",
    \"password\": \"${PASSWORD}\",
    \"realmName\": \"${REALM}\",
    \"clientId\": \"${CLIENT_ID}\",
    \"clientSecret\": \"${CLIENT_SECRET}\"
  }")

echo "Response: $RESPONSE" | head -c 500
echo ""

ACCESS_TOKEN=$(echo $RESPONSE | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('access_token','NOT_FOUND')[:80])
except:
    print('PARSE_ERROR')
" 2>/dev/null)

echo "Access token (first 80 chars): $ACCESS_TOKEN"
echo ""

echo "========================================"
echo "TEST 2: Keycloak direct token endpoint (port 8080)"
echo "========================================"
RESPONSE2=$(curl -sk -X POST \
  "https://auth-sso2fa.mobifone.vn:${SSO_AUTH_PORT}/oauth/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  -d "scope=openid email profile")

echo "Response: $RESPONSE2" | head -c 500
echo ""

ACCESS_TOKEN2=$(echo $RESPONSE2 | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('access_token','NOT_FOUND')
    print(t[:80] if t != 'NOT_FOUND' else 'NOT_FOUND')
except:
    print('PARSE_ERROR')
" 2>/dev/null)

echo "Access token (first 80 chars): $ACCESS_TOKEN2"
echo ""

echo "========================================"
echo "TEST 3: Decode JWT to get user_id (sub)"
echo "========================================"
# Use the token from whichever test succeeded
TOKEN_TO_USE=""
if [ "$ACCESS_TOKEN" != "NOT_FOUND" ] && [ "$ACCESS_TOKEN" != "PARSE_ERROR" ]; then
    TOKEN_TO_USE=$(echo $RESPONSE | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('access_token',''))
" 2>/dev/null)
elif [ "$ACCESS_TOKEN2" != "NOT_FOUND" ] && [ "$ACCESS_TOKEN2" != "PARSE_ERROR" ]; then
    TOKEN_TO_USE=$(echo $RESPONSE2 | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d.get('access_token',''))
" 2>/dev/null)
fi

if [ -n "$TOKEN_TO_USE" ]; then
    echo "Decoding JWT payload..."
    python3 -c "
import base64, json, sys
token = '${TOKEN_TO_USE}'
parts = token.split('.')
if len(parts) >= 2:
    payload = parts[1]
    # Add padding
    payload += '=' * (4 - len(payload) % 4)
    decoded = base64.urlsafe_b64decode(payload)
    data = json.loads(decoded)
    print('sub (user_id):', data.get('sub','N/A'))
    print('email:', data.get('email','N/A'))
    print('name:', data.get('name','N/A'))
    print('preferred_username:', data.get('preferred_username','N/A'))
    print('realm_roles:', data.get('realm_access',{}).get('roles',[]))
" 2>/dev/null
else
    echo "No valid token obtained. Check SSO connectivity."
fi

echo ""
echo "========================================"
echo "TEST 4: Check SSO OpenID Connect discovery"
echo "========================================"
curl -sk \
  "https://auth-sso2fa.mobifone.vn:${SSO_AUTH_PORT}/oauth/realms/${REALM}/.well-known/openid-configuration" \
  | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('issuer:', d.get('issuer','N/A'))
    print('auth_endpoint:', d.get('authorization_endpoint','N/A'))
    print('token_endpoint:', d.get('token_endpoint','N/A'))
    print('userinfo_endpoint:', d.get('userinfo_endpoint','N/A'))
except:
    print('Cannot reach discovery endpoint')
" 2>/dev/null

echo ""
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "If TEST 1 or TEST 2 returned an access_token → SSO credentials are valid"
echo "If both failed → check network connectivity to auth-sso2fa.mobifone.vn"
echo "Then run the integration script below."
