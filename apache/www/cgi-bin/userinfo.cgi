#!/bin/bash
#
# User Info CGI Script
# Displays user information from X-User-* headers set by API Gateway
#

# Get user info from headers
USER_SUB="${HTTP_X_USER_SUB:-Unknown}"
USER_EMAIL="${HTTP_X_USER_EMAIL:-Unknown}"
USER_NAME="${HTTP_X_USER_NAME:-Unknown}"
USER_USERNAME="${HTTP_X_USER_USERNAME:-Unknown}"
USER_GIVEN_NAME="${HTTP_X_USER_GIVEN_NAME:-}"
USER_FAMILY_NAME="${HTTP_X_USER_FAMILY_NAME:-}"
USER_GROUPS="${HTTP_X_USER_GROUPS:-None}"
SESSION_ID="${HTTP_X_USER_SESSION:-Unknown}"
SESSION_CREATED="${HTTP_X_SESSION_CREATED:-Unknown}"

# Convert session created timestamp if numeric
if [[ "$SESSION_CREATED" =~ ^[0-9]+$ ]]; then
    SESSION_CREATED_FMT=$(date -d "@$SESSION_CREATED" 2>/dev/null || echo "$SESSION_CREATED")
else
    SESSION_CREATED_FMT="$SESSION_CREATED"
fi

# Get initials for avatar
INITIALS=""
if [ -n "$USER_GIVEN_NAME" ]; then
    INITIALS="${USER_GIVEN_NAME:0:1}"
fi
if [ -n "$USER_FAMILY_NAME" ]; then
    INITIALS="${INITIALS}${USER_FAMILY_NAME:0:1}"
fi
if [ -z "$INITIALS" ] && [ -n "$USER_NAME" ]; then
    INITIALS="${USER_NAME:0:2}"
fi
INITIALS=$(echo "$INITIALS" | tr '[:lower:]' '[:upper:]')

# Output HTTP headers
echo "Content-Type: text/html"
echo ""

# Output HTML
cat << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome - ${USER_NAME}</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
            max-width: 550px;
            width: 100%;
        }
        .header {
            display: flex;
            align-items: center;
            margin-bottom: 30px;
            padding-bottom: 20px;
            border-bottom: 1px solid #eee;
        }
        .avatar {
            width: 70px;
            height: 70px;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 24px;
            font-weight: bold;
            margin-right: 20px;
        }
        .user-info h1 {
            color: #333;
            font-size: 24px;
            margin-bottom: 5px;
        }
        .user-info p {
            color: #666;
            font-size: 14px;
        }
        .details {
            margin-bottom: 25px;
        }
        .detail-row {
            display: flex;
            padding: 12px 0;
            border-bottom: 1px solid #f0f0f0;
        }
        .detail-row:last-child {
            border-bottom: none;
        }
        .detail-label {
            width: 140px;
            color: #888;
            font-size: 14px;
            font-weight: 500;
        }
        .detail-value {
            flex: 1;
            color: #333;
            font-size: 14px;
            word-break: break-all;
        }
        .groups {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
        }
        .group-badge {
            background: #e8f5e9;
            color: #2e7d32;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 500;
        }
        .actions {
            display: flex;
            gap: 15px;
            margin-top: 25px;
        }
        .btn {
            flex: 1;
            padding: 12px 20px;
            border-radius: 8px;
            text-decoration: none;
            text-align: center;
            font-weight: 600;
            font-size: 14px;
            transition: transform 0.2s;
        }
        .btn:hover {
            transform: translateY(-2px);
        }
        .btn-primary {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            color: white;
        }
        .btn-secondary {
            background: #f5f5f5;
            color: #333;
        }
        .btn-logout {
            background: #ffebee;
            color: #c62828;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="avatar">${INITIALS}</div>
            <div class="user-info">
                <h1>Welcome, ${USER_NAME}!</h1>
                <p>You are successfully authenticated</p>
            </div>
        </div>

        <div class="details">
            <div class="detail-row">
                <span class="detail-label">Email</span>
                <span class="detail-value">${USER_EMAIL}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Username</span>
                <span class="detail-value">${USER_USERNAME}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">User ID</span>
                <span class="detail-value" style="font-family: monospace; font-size: 12px;">${USER_SUB}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Session Created</span>
                <span class="detail-value">${SESSION_CREATED_FMT}</span>
            </div>
            <div class="detail-row">
                <span class="detail-label">Groups</span>
                <span class="detail-value">
                    <div class="groups">
EOF

# Output groups as badges
IFS=',' read -ra GROUP_ARRAY <<< "$USER_GROUPS"
for group in "${GROUP_ARRAY[@]}"; do
    group=$(echo "$group" | xargs)  # Trim whitespace
    if [ -n "$group" ] && [ "$group" != "None" ]; then
        echo "                        <span class=\"group-badge\">$group</span>"
    fi
done

if [ "$USER_GROUPS" = "None" ] || [ -z "$USER_GROUPS" ]; then
    echo "                        <span style=\"color: #999;\">No groups assigned</span>"
fi

cat << EOF
                    </div>
                </span>
            </div>
        </div>

        <div class="actions">
            <a href="/" class="btn btn-secondary">Home</a>
            <a href="/debug" class="btn btn-primary">Debug Info</a>
            <a href="/auth/logout" class="btn btn-logout">Logout</a>
        </div>
    </div>
</body>
</html>
EOF
