#!/bin/bash
#
# Apache Backend Uninstall Script
# Removes Apache HTTP Server and OIDC configuration
#
# Usage: sudo ./uninstall.sh
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
    log_error "Please run as root (sudo ./uninstall.sh)"
    exit 1
fi

log_info "Starting Apache backend uninstallation..."

# Detect OS
if [ -f /etc/oracle-release ] || [ -f /etc/redhat-release ]; then
    PKG_MGR="dnf"
    APACHE_SERVICE="httpd"
    APACHE_CONF_DIR="/etc/httpd/conf.d"
elif [ -f /etc/debian_version ]; then
    PKG_MGR="apt"
    APACHE_SERVICE="apache2"
    APACHE_CONF_DIR="/etc/apache2/conf-available"
fi

# Confirm
read -p "This will remove Apache and all web content. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Uninstall cancelled"
    exit 0
fi

# Stop Apache
log_info "Stopping Apache..."
systemctl stop "$APACHE_SERVICE" 2>/dev/null || true
systemctl disable "$APACHE_SERVICE" 2>/dev/null || true

# Remove configuration
log_info "Removing configuration..."
if [ "$PKG_MGR" = "dnf" ]; then
    rm -f "$APACHE_CONF_DIR/oidc-backend.conf"
else
    a2disconf oidc-backend 2>/dev/null || true
    rm -f "$APACHE_CONF_DIR/oidc-backend.conf"
fi

# Remove web content (optional - ask user)
read -p "Remove web content from /var/www/html? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing web content..."
    rm -f /var/www/html/index.html
    rm -f /var/www/html/logged-out.html
    rm -f /var/www/cgi-bin/userinfo.cgi 2>/dev/null || true
    rm -f /var/www/cgi-bin/debug.cgi 2>/dev/null || true
    rm -f /usr/lib/cgi-bin/userinfo.cgi 2>/dev/null || true
    rm -f /usr/lib/cgi-bin/debug.cgi 2>/dev/null || true
fi

# Remove Apache (optional)
read -p "Remove Apache package? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing Apache..."
    if [ "$PKG_MGR" = "dnf" ]; then
        dnf remove -y httpd mod_ssl
    else
        apt remove -y apache2
    fi
fi

# Update firewall
log_info "Updating firewall..."
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --remove-service=http 2>/dev/null || true
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    ufw delete allow 80/tcp 2>/dev/null || true
fi

log_info "Uninstallation complete!"
