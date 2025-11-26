#!/bin/bash
#
# Apache Backend Install Script
# Installs and configures Apache HTTP Server for the OIDC Authentication solution
#
# Usage: sudo ./install.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (sudo ./install.sh)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "Starting Apache backend installation..."

# Detect OS
if [ -f /etc/oracle-release ]; then
    OS="oracle"
    PKG_MGR="dnf"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    PKG_MGR="dnf"
elif [ -f /etc/debian_version ]; then
    OS="debian"
    PKG_MGR="apt"
else
    log_error "Unsupported operating system"
    exit 1
fi

log_info "Detected OS: $OS"

# Install Apache
log_info "Installing Apache HTTP Server..."
if [ "$PKG_MGR" = "dnf" ]; then
    dnf install -y httpd mod_ssl
    APACHE_SERVICE="httpd"
    APACHE_CONF_DIR="/etc/httpd/conf.d"
    DOCUMENT_ROOT="/var/www/html"
    CGI_DIR="/var/www/cgi-bin"
elif [ "$PKG_MGR" = "apt" ]; then
    apt update
    apt install -y apache2
    a2enmod cgi
    a2enmod ssl
    APACHE_SERVICE="apache2"
    APACHE_CONF_DIR="/etc/apache2/conf-available"
    DOCUMENT_ROOT="/var/www/html"
    CGI_DIR="/usr/lib/cgi-bin"
fi

# Create CGI directory if it doesn't exist
mkdir -p "$CGI_DIR"

# Copy web content
log_info "Installing web content..."
cp -r "$SCRIPT_DIR/www/"* "$DOCUMENT_ROOT/"

# Copy CGI scripts
log_info "Installing CGI scripts..."
cp "$SCRIPT_DIR/www/cgi-bin/"* "$CGI_DIR/"
chmod +x "$CGI_DIR/"*

# Create Apache configuration for CGI
log_info "Configuring Apache..."
if [ "$PKG_MGR" = "dnf" ]; then
    cat > "$APACHE_CONF_DIR/oidc-backend.conf" << 'EOF'
# OIDC Backend Configuration
# Serves pages that display user information from X-User-* headers

<Directory "/var/www/cgi-bin">
    AllowOverride None
    Options +ExecCGI
    AddHandler cgi-script .cgi
    Require all granted
</Directory>

# Log format to include user headers
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{X-User-Sub}i\" \"%{X-User-Email}i\"" oidc_combined
CustomLog logs/oidc_access_log oidc_combined
EOF
else
    cat > "$APACHE_CONF_DIR/oidc-backend.conf" << 'EOF'
# OIDC Backend Configuration
<Directory "/usr/lib/cgi-bin">
    AllowOverride None
    Options +ExecCGI
    AddHandler cgi-script .cgi
    Require all granted
</Directory>
EOF
    a2enconf oidc-backend
fi

# Configure firewall
log_info "Configuring firewall..."
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    ufw allow 80/tcp
fi

# Start Apache
log_info "Starting Apache..."
systemctl enable "$APACHE_SERVICE"
systemctl restart "$APACHE_SERVICE"

# Verify installation
if systemctl is-active --quiet "$APACHE_SERVICE"; then
    log_info "Apache is running"
else
    log_error "Apache failed to start"
    exit 1
fi

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}')

log_info "Installation complete!"
echo ""
echo "Apache backend is now running."
echo ""
echo "Local endpoints:"
echo "  Landing page:    http://$LOCAL_IP/"
echo "  User info (CGI): http://$LOCAL_IP/cgi-bin/userinfo.cgi"
echo "  Debug (CGI):     http://$LOCAL_IP/cgi-bin/debug.cgi"
echo "  Logged out:      http://$LOCAL_IP/logged-out.html"
echo ""
echo "Update API Gateway deployment with backend URL: http://$LOCAL_IP"
echo ""
