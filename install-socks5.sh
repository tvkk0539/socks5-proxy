#!/bin/bash

# SOCKS5 Proxy Auto-Installer
# Supports: Dante, 3proxy, and microsocks
# Tested on: Ubuntu 20.04/22.04, Debian 10/11, CentOS 7/8, Rocky Linux 8/9

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
PROXY_PORT="1080"
PROXY_USER=""
PROXY_PASSWORD=""
INTERFACE="0.0.0.0"
DNS_SERVERS="8.8.8.8,8.8.4.4"
METHOD="password"  # password or none
SERVER_TYPE="dante"  # dante, 3proxy, microsocks
LOG_FILE="/var/log/socks5-proxy.log"

# Function to print colored output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    print_message "Detected OS: $OS $VERSION"
}

# Function to install dependencies
install_dependencies() {
    print_message "Installing dependencies..."
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y wget curl build-essential gcc make
            ;;
        centos|rhel|rocky|almalinux)
            if [[ $OS == "centos" && ${VERSION%%.*} -eq 7 ]]; then
                yum install -y epel-release
                yum install -y wget curl gcc make
            else
                dnf install -y epel-release
                dnf install -y wget curl gcc make
            fi
            ;;
        *)
            print_error "Unsupported OS"
            exit 1
            ;;
    esac
}

# Function to generate random password
generate_password() {
    openssl rand -base64 12
}

# Function to get user input
get_user_input() {
    echo ""
    echo "SOCKS5 Proxy Configuration"
    echo "=========================="
    echo ""
    
    # Select server type
    echo "Select SOCKS5 server type:"
    echo "1) Dante (feature-rich, recommended for production)"
    echo "2) 3proxy (lightweight, good performance)"
    echo "3) microsocks (very lightweight, single-threaded)"
    read -p "Choice [1-3] (default: 1): " server_choice
    
    case $server_choice in
        2) SERVER_TYPE="3proxy" ;;
        3) SERVER_TYPE="microsocks" ;;
        *) SERVER_TYPE="dante" ;;
    esac
    
    # Proxy port
    read -p "Enter proxy port (default: 1080): " user_port
    if [[ ! -z "$user_port" ]]; then
        PROXY_PORT=$user_port
    fi
    
    # Authentication method
    echo ""
    echo "Select authentication method:"
    echo "1) Username/Password (recommended)"
    echo "2) No authentication (open proxy - not recommended)"
    read -p "Choice [1-2] (default: 1): " auth_choice
    
    if [[ $auth_choice == "2" ]]; then
        METHOD="none"
        print_warning "You selected no authentication. This will create an open proxy!"
    else
        METHOD="password"
        read -p "Enter username (default: proxyuser): " PROXY_USER
        if [[ -z "$PROXY_USER" ]]; then
            PROXY_USER="proxyuser"
        fi
        
        read -s -p "Enter password (leave empty to generate random): " user_password
        echo ""
        if [[ -z "$user_password" ]]; then
            PROXY_PASSWORD=$(generate_password)
            print_message "Generated password: $PROXY_PASSWORD"
        else
            PROXY_PASSWORD=$user_password
        fi
    fi
    
    # Interface
    read -p "Bind to interface (0.0.0.0 for all, or specific IP) (default: 0.0.0.0): " user_interface
    if [[ ! -z "$user_interface" ]]; then
        INTERFACE=$user_interface
    fi
    
    echo ""
    print_message "Configuration summary:"
    echo "  Server Type: $SERVER_TYPE"
    echo "  Port: $PROXY_PORT"
    echo "  Auth Method: $METHOD"
    if [[ $METHOD == "password" ]]; then
        echo "  Username: $PROXY_USER"
        echo "  Password: $PROXY_PASSWORD"
    fi
    echo "  Bind Interface: $INTERFACE"
    echo ""
    
    read -p "Continue with installation? (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_message "Installation cancelled"
        exit 0
    fi
}

# Function to install and configure Dante
install_dante() {
    print_message "Installing Dante SOCKS5 server..."
    
    case $OS in
        ubuntu|debian)
            apt-get install -y dante-server
            ;;
        centos|rhel|rocky|almalinux)
            if [[ $OS == "centos" && ${VERSION%%.*} -eq 7 ]]; then
                yum install -y dante-server
            else
                dnf install -y dante-server
            fi
            ;;
    esac
    
    # Backup original config
    if [ -f /etc/danted.conf ]; then
        cp /etc/danted.conf /etc/danted.conf.backup
    fi
    
    # Create Dante configuration
    cat > /etc/danted.conf <<EOF
# Dante SOCKS5 Server Configuration
# Auto-generated by SOCKS5 installer

logoutput: $LOG_FILE

# The server will bind to this address/port
internal: $INTERFACE port = $PROXY_PORT
external: $(ip route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')

# Authentication methods
method: $METHOD

# User privileges
user.privileged: root
user.notprivileged: nobody

# Client authentication rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}
EOF

    # Add authentication rules
    if [[ $METHOD == "password" ]]; then
        cat >> /etc/danted.conf <<EOF

# SOCKS methods
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    socksmethod: username
    log: error
}
EOF
        
        # Create user for authentication
        if id "$PROXY_USER" &>/dev/null; then
            print_warning "User $PROXY_USER already exists, updating password"
        else
            useradd -r -s /bin/false $PROXY_USER
        fi
        echo "$PROXY_USER:$PROXY_PASSWORD" | chpasswd
    else
        cat >> /etc/danted.conf <<EOF

# SOCKS methods - no authentication
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    socksmethod: none
    log: error
}
EOF
    fi
    
    # Start and enable Dante
    systemctl restart danted
    systemctl enable danted
}

# Function to install and configure 3proxy
install_3proxy() {
    print_message "Installing 3proxy SOCKS5 server..."
    
    # Install 3proxy
    case $OS in
        ubuntu|debian)
            apt-get install -y 3proxy
            ;;
        centos|rhel|rocky|almalinux)
            # For CentOS/Rocky, compile from source
            cd /tmp
            wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz
            tar -xzf 0.9.4.tar.gz
            cd 3proxy-0.9.4
            make -f Makefile.Linux
            make install
            ;;
    esac
    
    # Create 3proxy configuration
    cat > /etc/3proxy/3proxy.cfg <<EOF
# 3proxy Configuration
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
external $(ip route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
internal $INTERFACE

# Logging
log /var/log/3proxy.log D
logformat "- +_L%t.%.  %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30

# SOCKS5 proxy
socks -p$PROXY_PORT -i$INTERFACE -e$(ip route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
EOF

    # Add authentication if needed
    if [[ $METHOD == "password" ]]; then
        # Create users file
        cat > /etc/3proxy/passwd <<EOF
$PROXY_USER:CL:$PROXY_PASSWORD
EOF
        # Modify config to use authentication
        sed -i "s/^socks .*/& -a -n/" /etc/3proxy/3proxy.cfg
    fi
    
    # Create systemd service
    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=forking
PIDFile=/var/run/3proxy.pid
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
ExecStop=/bin/kill -TERM \$MAINPID
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable 3proxy
    systemctl daemon-reload
    systemctl restart 3proxy
    systemctl enable 3proxy
}

# Function to install and configure microsocks
install_microsocks() {
    print_message "Installing microsocks SOCKS5 server..."
    
    # Install dependencies
    case $OS in
        ubuntu|debian)
            apt-get install -y git
            ;;
        centos|rhel|rocky|almalinux)
            if [[ $OS == "centos" && ${VERSION%%.*} -eq 7 ]]; then
                yum install -y git
            else
                dnf install -y git
            fi
            ;;
    esac
    
    # Clone and compile microsocks
    cd /tmp
    git clone https://github.com/rofl0r/microsocks.git
    cd microsocks
    make
    
    # Install binary
    cp microsocks /usr/local/bin/
    
    # Create systemd service
    cat > /etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=microsocks SOCKS5 Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -i $INTERFACE -p $PROXY_PORT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable microsocks
    systemctl daemon-reload
    systemctl restart microsocks
    systemctl enable microsocks
}

# Function to configure firewall
configure_firewall() {
    print_message "Configuring firewall..."
    
    # Check if ufw is installed (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        ufw allow $PROXY_PORT/tcp
        ufw allow $PROXY_PORT/udp
        print_message "UFW rules added"
    fi
    
    # Check if firewalld is installed (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$PROXY_PORT/tcp
        firewall-cmd --permanent --add-port=$PROXY_PORT/udp
        firewall-cmd --reload
        print_message "Firewalld rules added"
    fi
    
    # Check if iptables is available as fallback
    if command -v iptables &> /dev/null; then
        iptables -I INPUT -p tcp --dport $PROXY_PORT -j ACCEPT
        iptables -I INPUT -p udp --dport $PROXY_PORT -j ACCEPT
        print_message "iptables rules added"
    fi
}

# Function to test proxy
test_proxy() {
    print_message "Testing SOCKS5 proxy..."
    
    # Wait for service to start
    sleep 5
    
    # Test local connection
    if command -v curl &> /dev/null; then
        if [[ $METHOD == "password" ]]; then
            curl --socks5 $PROXY_USER:$PROXY_PASSWORD@localhost:$PROXY_PORT https://api.ipify.org
        else
            curl --socks5 localhost:$PROXY_PORT https://api.ipify.org
        fi
        
        if [ $? -eq 0 ]; then
            print_message "Proxy test successful!"
        else
            print_warning "Proxy test failed. Please check configuration."
        fi
    else
        print_warning "curl not installed, skipping proxy test"
    fi
}

# Function to display connection info
display_info() {
    # Get public IP
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Unable to determine")
    
    echo ""
    echo "========================================"
    echo "SOCKS5 Proxy Installation Complete!"
    echo "========================================"
    echo ""
    echo "Connection Details:"
    echo "  Server IP: $PUBLIC_IP"
    echo "  Port: $PROXY_PORT"
    echo "  Authentication: $METHOD"
    if [[ $METHOD == "password" ]]; then
        echo "  Username: $PROXY_USER"
        echo "  Password: $PROXY_PASSWORD"
    fi
    echo ""
    echo "Connection String Examples:"
    echo "  Browser/Application:"
    if [[ $METHOD == "password" ]]; then
        echo "    socks5://$PROXY_USER:$PROXY_PASSWORD@$PUBLIC_IP:$PROXY_PORT"
    else
        echo "    socks5://$PUBLIC_IP:$PROXY_PORT"
    fi
    echo ""
    echo "  curl command:"
    if [[ $METHOD == "password" ]]; then
        echo "    curl --socks5 $PROXY_USER:$PROXY_PASSWORD@$PUBLIC_IP:$PROXY_PORT https://api.ipify.org"
    else
        echo "    curl --socks5 $PUBLIC_IP:$PROXY_PORT https://api.ipify.org"
    fi
    echo ""
    echo "Service Management:"
    case $SERVER_TYPE in
        dante)
            echo "  Status: systemctl status danted"
            echo "  Restart: systemctl restart danted"
            echo "  Config: /etc/danted.conf"
            ;;
        3proxy)
            echo "  Status: systemctl status 3proxy"
            echo "  Restart: systemctl restart 3proxy"
            echo "  Config: /etc/3proxy/3proxy.cfg"
            ;;
        microsocks)
            echo "  Status: systemctl status microsocks"
            echo "  Restart: systemctl restart microsocks"
            echo "  Config: /etc/systemd/system/microsocks.service"
            ;;
    esac
    echo "  Logs: $LOG_FILE"
    echo ""
    echo "Security Notes:"
    echo "  - Keep your credentials secure"
    echo "  - Consider restricting access by IP in production"
    echo "  - Monitor logs for unauthorized access"
    echo "========================================"
}

# Main installation function
main() {
    print_message "Starting SOCKS5 Proxy Auto-Installer"
    echo "=========================================="
    
    check_root
    detect_os
    get_user_input
    install_dependencies
    
    case $SERVER_TYPE in
        dante)
            install_dante
            ;;
        3proxy)
            install_3proxy
            ;;
        microsocks)
            install_microsocks
            ;;
    esac
    
    configure_firewall
    test_proxy
    display_info
}

# Run main function
main
