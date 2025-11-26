# Apache Backend Setup

This directory contains everything needed to set up the Apache HTTP Server backend for the OIDC Authentication solution.

## Overview

The Apache backend serves as a simple HTTP server that:
- Displays user information from X-User-* headers (set by API Gateway)
- Provides landing and logout pages
- Runs CGI scripts for dynamic content

## Directory Structure

```
apache/
├── README.md           # This file
├── install.sh          # Installation script
├── uninstall.sh        # Removal script
├── user_data.yaml      # Cloud-init config (legacy mTLS setup)
└── www/
    ├── index.html      # Landing page
    ├── logged-out.html # Post-logout page
    └── cgi-bin/
        ├── userinfo.cgi # User info page (welcome)
        └── debug.cgi    # Debug page showing all headers
```

## Quick Start

### 1. Deploy a Compute Instance

Create an OCI Compute instance in the private subnet:

```bash
oci compute instance launch \
  --compartment-id <compartment-ocid> \
  --display-name "apigw-oidc-backend" \
  --availability-domain "<ad-name>" \
  --shape "VM.Standard.E4.Flex" \
  --shape-config '{"ocpus": 1, "memoryInGBs": 8}' \
  --subnet-id <private-subnet-ocid> \
  --image-id <oracle-linux-image-ocid> \
  --assign-public-ip false \
  --ssh-authorized-keys-file ~/.ssh/id_rsa.pub
```

### 2. Copy Files to Instance

```bash
# Get instance IP (via bastion or VPN)
INSTANCE_IP=<private-ip>

# Copy apache directory
scp -r apache/ opc@$INSTANCE_IP:~/
```

### 3. Run Installation

```bash
# SSH to instance
ssh opc@$INSTANCE_IP

# Run install script
cd ~/apache
sudo ./install.sh
```

### 4. Update API Gateway

Update `scripts/api_deployment.json` with the backend IP:

```json
{
  "backend": {
    "type": "HTTP_BACKEND",
    "url": "http://<instance-ip>/",
    ...
  }
}
```

Deploy the update:

```bash
oci api-gateway deployment update \
  --deployment-id <deployment-ocid> \
  --specification file://scripts/api_deployment.json --force
```

## Web Pages

### Landing Page (`/`)

- **File**: `www/index.html`
- **URL**: `http://<backend-ip>/` → API Gateway route: `/`
- **Purpose**: Public landing page with "Sign In" button

### User Info Page (`/welcome`)

- **File**: `www/cgi-bin/userinfo.cgi`
- **URL**: `http://<backend-ip>/cgi-bin/userinfo.cgi` → API Gateway route: `/welcome`
- **Purpose**: Displays authenticated user's information
- **Headers Used**:
  - `X-User-Sub` - User ID
  - `X-User-Email` - Email address
  - `X-User-Name` - Display name
  - `X-User-Username` - Username
  - `X-User-Given-Name` - First name
  - `X-User-Family-Name` - Last name
  - `X-User-Groups` - Group membership
  - `X-User-Session` - Session ID
  - `X-Session-Created` - Session creation timestamp

### Debug Page (`/debug`)

- **File**: `www/cgi-bin/debug.cgi`
- **URL**: `http://<backend-ip>/cgi-bin/debug.cgi` → API Gateway route: `/debug`
- **Purpose**: Shows all HTTP headers for debugging
- **Useful for**: Verifying header propagation from API Gateway

### Logged Out Page (`/logged-out`)

- **File**: `www/logged-out.html`
- **URL**: `http://<backend-ip>/logged-out.html` → API Gateway route: `/logged-out`
- **Purpose**: Displayed after successful logout

## API Gateway Route Mapping

| API Gateway Route | Backend URL | File |
|-------------------|-------------|------|
| `/` | `http://<ip>/index.html` | `www/index.html` |
| `/welcome` | `http://<ip>/cgi-bin/userinfo.cgi` | `www/cgi-bin/userinfo.cgi` |
| `/debug` | `http://<ip>/cgi-bin/debug.cgi` | `www/cgi-bin/debug.cgi` |
| `/logged-out` | `http://<ip>/logged-out.html` | `www/logged-out.html` |

## Manual Installation

If you prefer to install manually:

```bash
# Install Apache (Oracle Linux / RHEL)
sudo dnf install -y httpd

# Copy web content
sudo cp www/index.html /var/www/html/
sudo cp www/logged-out.html /var/www/html/

# Copy CGI scripts
sudo cp www/cgi-bin/*.cgi /var/www/cgi-bin/
sudo chmod +x /var/www/cgi-bin/*.cgi

# Start Apache
sudo systemctl enable --now httpd

# Configure firewall
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

## Uninstallation

```bash
sudo ./uninstall.sh
```

This will prompt you to:
1. Remove web content
2. Remove Apache package (optional)

## Customization

### Modifying Pages

Edit the HTML/CGI files in `www/` and re-run the install script, or copy manually:

```bash
sudo cp www/index.html /var/www/html/
```

### Adding New Pages

1. Create the HTML/CGI file in `www/`
2. Update `install.sh` if needed
3. Add the route to `scripts/api_deployment.json`

### Styling

The pages use inline CSS for simplicity. To use external stylesheets:

1. Create `www/css/style.css`
2. Update `install.sh` to copy the CSS directory
3. Update HTML files to link the stylesheet

## Troubleshooting

### CGI Scripts Not Executing

```bash
# Check permissions
ls -la /var/www/cgi-bin/

# Scripts should be executable
sudo chmod +x /var/www/cgi-bin/*.cgi

# Check Apache error log
sudo tail -f /var/log/httpd/error_log
```

### Headers Not Appearing

1. Check API Gateway header transformations in `scripts/api_deployment.json`
2. Use `/debug` page to see what headers are received
3. Verify the authorizer is returning claims in the context

### Connection Refused

```bash
# Check Apache is running
sudo systemctl status httpd

# Check firewall
sudo firewall-cmd --list-all

# Check Apache is listening
sudo ss -tlnp | grep :80
```

## Security Notes

- The backend runs on HTTP (port 80) because API Gateway handles HTTPS termination
- Ensure the private subnet security list only allows traffic from API Gateway
- Do not expose the backend directly to the internet
