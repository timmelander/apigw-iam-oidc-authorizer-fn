#!/bin/bash
#
# Debug CGI Script
# Displays all HTTP headers and environment variables for debugging
#

# Output HTTP headers
echo "Content-Type: text/html"
echo ""

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

cat << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Debug Information</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: #1a1a2e;
            color: #eee;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
        }
        h1 {
            color: #00d4ff;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #888;
            margin-bottom: 30px;
        }
        .section {
            background: #16213e;
            border-radius: 8px;
            margin-bottom: 20px;
            overflow: hidden;
        }
        .section-header {
            background: #0f3460;
            padding: 15px 20px;
            font-weight: 600;
            color: #00d4ff;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .section-header .count {
            background: #00d4ff;
            color: #1a1a2e;
            padding: 2px 10px;
            border-radius: 12px;
            font-size: 12px;
        }
        .section-content {
            padding: 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        tr {
            border-bottom: 1px solid #0f3460;
        }
        tr:last-child {
            border-bottom: none;
        }
        tr:hover {
            background: #1f4068;
        }
        td {
            padding: 12px 20px;
            font-size: 13px;
        }
        td:first-child {
            width: 250px;
            color: #e94560;
            font-family: 'Monaco', 'Menlo', monospace;
            font-weight: 500;
        }
        td:last-child {
            color: #a5d6a7;
            font-family: 'Monaco', 'Menlo', monospace;
            word-break: break-all;
        }
        .actions {
            margin-bottom: 30px;
        }
        .btn {
            display: inline-block;
            padding: 10px 20px;
            background: #0f3460;
            color: #00d4ff;
            text-decoration: none;
            border-radius: 6px;
            margin-right: 10px;
            font-size: 14px;
            transition: background 0.2s;
        }
        .btn:hover {
            background: #1f4068;
        }
        .btn-logout {
            background: #4a1942;
            color: #ff6b9d;
        }
        .highlight {
            background: #1f4068;
        }
        .timestamp {
            color: #666;
            font-size: 12px;
            margin-top: 20px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Debug Information</h1>
        <p class="subtitle">HTTP Headers and Environment Variables</p>

        <div class="actions">
            <a href="/" class="btn">Home</a>
            <a href="/welcome" class="btn">User Info</a>
            <a href="/auth/logout" class="btn btn-logout">Logout</a>
        </div>

        <div class="section">
            <div class="section-header">
                <span>User Headers (X-User-*)</span>
EOF

# Count X-User headers
USER_HEADER_COUNT=$(env | grep -c "^HTTP_X_USER" || echo "0")
echo "                <span class=\"count\">$USER_HEADER_COUNT headers</span>"

cat << 'EOF'
            </div>
            <div class="section-content">
                <table>
EOF

# Output X-User-* headers
env | grep "^HTTP_X_USER\|^HTTP_X_SESSION\|^HTTP_X_RAW" | sort | while IFS='=' read -r name value; do
    # Convert HTTP_X_USER_SUB to X-User-Sub
    header_name=$(echo "$name" | sed 's/^HTTP_//' | tr '_' '-')
    echo "                    <tr class=\"highlight\"><td>$header_name</td><td>$value</td></tr>"
done

cat << 'EOF'
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-header">
                <span>Request Headers</span>
EOF

# Count all HTTP headers
HTTP_HEADER_COUNT=$(env | grep -c "^HTTP_" || echo "0")
echo "                <span class=\"count\">$HTTP_HEADER_COUNT headers</span>"

cat << 'EOF'
            </div>
            <div class="section-content">
                <table>
EOF

# Output all HTTP headers
env | grep "^HTTP_" | grep -v "^HTTP_X_USER\|^HTTP_X_SESSION\|^HTTP_X_RAW" | sort | while IFS='=' read -r name value; do
    header_name=$(echo "$name" | sed 's/^HTTP_//' | tr '_' '-')
    # Truncate long values
    if [ ${#value} -gt 100 ]; then
        value="${value:0:100}..."
    fi
    echo "                    <tr><td>$header_name</td><td>$value</td></tr>"
done

cat << 'EOF'
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-header">
                <span>CGI Environment</span>
            </div>
            <div class="section-content">
                <table>
EOF

# Output CGI environment variables
for var in REQUEST_METHOD REQUEST_URI QUERY_STRING REMOTE_ADDR REMOTE_HOST SERVER_NAME SERVER_PORT SERVER_PROTOCOL SCRIPT_NAME PATH_INFO CONTENT_TYPE CONTENT_LENGTH; do
    value="${!var:-<not set>}"
    echo "                    <tr><td>$var</td><td>$value</td></tr>"
done

cat << EOF
                </table>
            </div>
        </div>

        <p class="timestamp">Generated at: $TIMESTAMP</p>
    </div>
</body>
</html>
EOF
