#!/bin/bash

# This script performs a curl-based end-to-end test of the OIDC authentication flow.
# It simulates a browser's interaction with the Load Balancer, API Gateway, OCI Functions,
# and OCI IAM Identity Domain.
#
# IMPORTANT: This script CANNOT automate the actual user login and MFA steps at the OCI IAM Identity Domain.
#            It will verify the redirects to and from the IdP and the subsequent handling of tokens and cookies
#            by the API Gateway and Functions.
#
# Prerequisites:
# - All OCI infrastructure deployed and configured.
# - Environment variables set:
#   - LB_PUBLIC_IP: Public IP address of the OCI Flexible Load Balancer.
#   - OCI_IAM_BASE_URL: Base URL of your OCI IAM Identity Domain (e.g., https://idcs-xxxx.identity.oraclecloud.com).
#   - OIDC_CLIENT_ID: Client ID of your Confidential Application in OCI IAM.
#   - OIDC_REDIRECT_URI: The full public URL of your API Gateway's /oauth2/callback endpoint.
#   - OIDC_LOGOUT_REDIRECT_URI: The full public URL of your API Gateway's /logout endpoint.
#   - TEST_USER_EMAIL: An email of a test user configured in OCI IAM.
#   - TEST_USER_PASSWORD: Password for the test user.
#
# Usage:
#   ./verify-deployment.sh
#

set -euo pipefail

# --- Configuration ---
LB_PUBLIC_IP=${LB_PUBLIC_IP:-"127.0.0.1"} # Replace with your LB Public IP if not set
OCI_IAM_BASE_URL=${OCI_IAM_BASE_URL:-"https://idcs-xxxxxxxx.identity.oraclecloud.com"} # Replace
OIDC_CLIENT_ID=${OIDC_CLIENT_ID:-"your_oidc_client_id"} # Replace
OIDC_REDIRECT_URI=${OIDC_REDIRECT_URI:-"https://$LB_PUBLIC_IP/oauth2/callback"} # Replace
OIDC_LOGOUT_REDIRECT_URI=${OIDC_LOGOUT_REDIRECT_URI:-"https://$LB_PUBLIC_IP/logout"} # Replace

# User for IdP interaction (for manual testing)
TEST_USER_EMAIL=${TEST_USER_EMAIL:-"test.user@yourdomain.com"} # Replace with a valid test user email
TEST_USER_PASSWORD=${TEST_USER_PASSWORD:-"YourSuperSecurePassword"} # Replace with password


# --- Internal Variables ---
COOKIE_JAR=$(mktemp)
echo "Using temporary cookie jar: $COOKIE_JAR"

# PKCE variables (generate once for the flow)
CODE_VERIFIER=$(head /dev/urandom | tr -dc A-Za-z0-9-._~ | head -c 128 ; echo '')
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 -w 0 | sed 's/">+</-/' | sed 's/">+</_
/' | sed 's/=//g')

# Function to extract Location header
extract_location_header() {
    grep -i '^Location:' | sed -e 's/^Location: //i' -e 's/$//'
}

# Function to extract Set-Cookie header (specifically the OIDC_SESSION)
extract_oidc_session_cookie() {
    grep -i '^Set-Cookie:' | grep "$OIDC_SESSION" | sed -e 's/^Set-Cookie: //i' -e 's/;.*$//' -e 's/$//'
}

echo "--- Starting End-to-End Verification Script ---"

# --- 1. Initial Access to Protected Resource (Unauthenticated) ---
echo -e "\n--- Step 1: Accessing protected resource (unauthenticated) ---"
echo "Expecting redirect to OCI IAM Identity Domain login page."
RESPONSE=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null -H "User-Agent: test-script" "$OIDC_REDIRECT_URI") # Use redirect URI as entry point
# Alternatively, start from protected resource if API Gateway is already set up to redirect
# RESPONSE=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null -H "User-Agent: test-script" "https://$LB_PUBLIC_IP/")

echo "Initial Access HTTP Status Code: $RESPONSE"
if [ "$RESPONSE" -ne 302 ]; then
    echo "FAIL: Expected 302 redirect to IdP. Received $RESPONSE."
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: Redirect to IdP initiated (checked by curl -L following redirects)."

# Now, we need to manually perform the login through a browser, capturing the final redirect URL.
echo -e "\n--- Step 2: MANUAL INTERVENTION REQUIRED - OIDC Login and MFA ---"
echo "Please open the following URL in your browser, log in with '$TEST_USER_EMAIL', and complete any MFA steps:"

# Construct the authorization URL
AUTH_URL=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -D - "https://$LB_PUBLIC_IP/" | grep -i '^Location:' | tail -1 | sed -e 's/^Location: //i' -e 's/$//')
if [[ -z "$AUTH_URL" ]]; then
    echo "FAIL: Could not extract authorization URL from initial access."
    rm "$COOKIE_JAR"
    exit 1
fi

AUTH_REQUEST_PARAMS=$(echo "$AUTH_URL" | cut -d'?' -f2)
STATE_PARAM=$(echo "$AUTH_REQUEST_PARAMS" | sed -n 's/.*state=\([^&]*\).*/\1/p')

if [[ -z "$STATE_PARAM" ]]; then
    echo "FAIL: Could not extract state parameter from authorization URL. This is critical for PKCE."
    rm "$COOKIE_JAR"
    exit 1
fi

echo "Authorization URL: $AUTH_URL"
echo "Manually log in and you will be redirected to the API Gateway's /oauth2/callback endpoint."
echo "Copy the FULL URL from your browser's address bar after successful login (it will start with $OIDC_REDIRECT_URI?code=...). This is the 'Callback URL'."
echo "Press any key to continue after you have the Callback URL..."
read -r -n 1

# --- 3. Simulate OIDC Callback with 'code' (from manual step) ---
echo -e "\n--- Step 3: Simulate OIDC Callback ---"
read -p "Paste the FULL Callback URL from your browser here: " CALLBACK_URL

if [[ -z "$CALLBACK_URL" ]]; then
    echo "FAIL: No Callback URL provided."
    rm "$COOKIE_JAR"
    exit 1
fi

# Extract 'code' and 'state' from the provided Callback URL
CALLBACK_QUERY_STRING=$(echo "$CALLBACK_URL" | cut -d'?' -f2)
CALLBACK_CODE=$(echo "$CALLBACK_QUERY_STRING" | sed -n 's/.*code=\([^&]*\).*/\1/p')
CALLBACK_STATE=$(echo "$CALLBACK_QUERY_STRING" | sed -n 's/.*state=\([^&]*\).*/\1/p')

if [[ -z "$CALLBACK_CODE" ]] || [[ -z "$CALLBACK_STATE" ]]; then
    echo "FAIL: Could not extract 'code' or 'state' from the provided Callback URL. Ensure it's the complete URL."
    rm "$COOKIE_JAR"
    exit 1
fi

echo "Callback Code: $CALLBACK_CODE"
echo "Callback State: $CALLBACK_STATE"

# Use the extracted code to complete the flow via API Gateway
echo "Simulating API Gateway's call to /oauth2/callback with the received code."
# Using -L to follow the 302 redirect from the OIDC Function to the protected resource
# -D - to show response headers
CALLBACK_RESPONSE_HEADERS=$(curl -s -D - -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o /dev/null -H "User-Agent: test-script" "${OIDC_REDIRECT_URI}?code=${CALLBACK_CODE}&state=${CALLBACK_STATE}")
CALLBACK_STATUS_CODE=$(echo "$CALLBACK_RESPONSE_HEADERS" | head -n 1 | awk '{print $2}')
echo "Callback to APIGW HTTP Status Code: $CALLBACK_STATUS_CODE"

if [[ "$CALLBACK_STATUS_CODE" -ne 200 && "$CALLBACK_STATUS_CODE" -ne 302 ]]; then # Expect 200 if no redirect or 302 for successful redirect
    echo "FAIL: OIDC Callback to API Gateway did not return expected status code (200 or 302). Received $CALLBACK_STATUS_CODE."
    echo "Response Headers:"
    echo "$CALLBACK_RESPONSE_HEADERS"
    rm "$COOKIE_JAR"
    exit 1
fi

echo "SUCCESS: OIDC Callback processed by API Gateway. Checking for session cookie."
OIDC_SESSION_COOKIE=$(extract_oidc_session_cookie <<< "$CALLBACK_RESPONSE_HEADERS")
if [[ -z "$OIDC_SESSION_COOKIE" ]]; then
    echo "FAIL: No OIDC_SESSION cookie found after callback."
    echo "Response Headers:"
    echo "$CALLBACK_RESPONSE_HEADERS"
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: OIDC_SESSION cookie found: $OIDC_SESSION_COOKIE"

# --- 4. Access Protected Page (Authenticated) ---
echo -e "\n--- Step 4: Accessing protected resource (authenticated) ---"
echo "Expecting HTTP 200 OK with protected content."
PROTECTED_RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/stdout -H "User-Agent: test-script" "https://$LB_PUBLIC_IP/")
PROTECTED_STATUS_CODE=$(echo "$PROTECTED_RESPONSE" | tail -n 1) # Extract status code from last line
PROTECTED_BODY=$(echo "$PROTECTED_RESPONSE" | head -n -1) # Extract body

echo "Protected Resource HTTP Status Code: $PROTECTED_STATUS_CODE"
if [ "$PROTECTED_STATUS_CODE" -ne 200 ]; then
    echo "FAIL: Expected 200 OK for protected resource. Received $PROTECTED_STATUS_CODE."
    echo "Response Body:"
    echo "$PROTECTED_BODY"
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: Protected resource accessed successfully."
echo "Response Body Snippet:"
echo "$PROTECTED_BODY" | head -n 5
echo "..."

# --- 5. Initiate Logout ---
echo -e "\n--- Step 5: Initiating Logout ---"
echo "Expecting redirect to OCI IAM Identity Domain end_session_endpoint, then to POST_LOGOUT_REDIRECT_URI."
LOGOUT_RESPONSE_HEADERS=$(curl -s -D - -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -o /dev/null -H "User-Agent: test-script" "https://$LB_PUBLIC_IP/logout")
LOGOUT_STATUS_CODE=$(echo "$LOGOUT_RESPONSE_HEADERS" | head -n 1 | awk '{print $2}')
echo "Logout Request HTTP Status Code: $LOGOUT_STATUS_CODE"

if [[ "$LOGOUT_STATUS_CODE" -ne 200 && "$LOGOUT_STATUS_CODE" -ne 302 ]]; then
    echo "FAIL: Logout request did not return expected status code (200 or 302). Received $LOGOUT_STATUS_CODE."
    echo "Response Headers:"
    echo "$LOGOUT_RESPONSE_HEADERS"
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: Logout initiated."

# Verify OIDC_SESSION cookie is cleared
CLEARED_COOKIE=$(extract_oidc_session_cookie <<< "$LOGOUT_RESPONSE_HEADERS" | grep 'Expires=Thu, 01 Jan 1970')
if [[ -z "$CLEARED_COOKIE" ]]; then
    echo "FAIL: OIDC_SESSION cookie was not cleared after logout."
    echo "Response Headers:"
    echo "$LOGOUT_RESPONSE_HEADERS"
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: OIDC_SESSION cookie cleared."

# --- 6. Access Protected Page (After Logout - Should Redirect to IdP) ---
echo -e "\n--- Step 6: Accessing protected resource after logout ---"
echo "Expecting redirect to OCI IAM Identity Domain login page again."
POST_LOGOUT_ACCESS=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" -w "%{http_code}" -o /dev/null -H "User-Agent: test-script" "https://$LB_PUBLIC_IP/")
echo "Post Logout Access HTTP Status Code: $POST_LOGOUT_ACCESS"

if [ "$POST_LOGOUT_ACCESS" -ne 302 ]; then
    echo "FAIL: Expected 302 redirect to IdP after logout. Received $POST_LOGOUT_ACCESS."
    rm "$COOKIE_JAR"
    exit 1
fi
echo "SUCCESS: Redirect to IdP initiated after logout, session is terminated."

echo -e "\n--- End-to-End Verification Script Completed Successfully ---"

rm "$COOKIE_JAR"
exit 0
