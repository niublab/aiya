#!/bin/bash

# Element Server Suite (ESS) Community Edition Deployment Script
# Improved Version Based on Security and Best Practices Review
# Version: 2.0
# Compatible with ESS-Helm Chart 25.6.0

# Strict error handling
set -euo pipefail

# Script configuration
SCRIPT_VERSION="2.0"
ESS_CHART_VERSION="25.6.0"
INSTALL_DIR="/opt/matrix"
CONFIG_DIR="${INSTALL_DIR}/config"
LOG_FILE="${INSTALL_DIR}/logs/setup.log"
NAMESPACE="ess"

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configuration variables
DOMAIN_NAME=""
SYNAPSE_DOMAIN=""
AUTH_DOMAIN=""
RTC_DOMAIN=""
WEB_DOMAIN=""
CERT_EMAIL=""
ADMIN_EMAIL=""
CLOUDFLARE_API_TOKEN=""
CLOUDFLARE_ZONE_ID=""

# Required ports
REQUIRED_PORTS=(80 443 30881 30882)

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Script execution failed with exit code $exit_code"
        print_info "Cleaning up temporary files..."
        # Add cleanup logic here if needed
        print_info "Check logs at: $LOG_FILE"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Enhanced logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# Print functions with enhanced formatting
print_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log "$message"
}

print_title() {
    echo
    print_message "$CYAN" "=== $1 ==="
    echo
}

print_step() {
    print_message "$BLUE" "→ $1"
}

print_success() {
    print_message "$GREEN" "✓ $1"
}

print_error() {
    print_message "$RED" "✗ $1"
}

print_warning() {
    print_message "$YELLOW" "⚠ $1"
}

print_info() {
    print_message "$WHITE" "ℹ $1"
}

# Enhanced error exit function
error_exit() {
    print_error "$1"
    log "ERROR: $1"
    exit 1
}

# Progress display function
show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    printf "\r[%3d%%] %s" "$percent" "$desc"
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# Retry mechanism for network operations
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            print_warning "Command failed, attempt $attempt/$max_attempts. Retrying in ${delay}s..."
            sleep "$delay"
        fi
        ((attempt++))
    done
    
    print_error "Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Enhanced command checking
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# Input validation functions
validate_domain() {
    local domain="$1"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        error_exit "Invalid domain format: $domain"
    fi
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error_exit "Invalid email format: $email"
    fi
}

# Enhanced directory creation with proper permissions
create_directories() {
    print_step "Creating installation directories..."
    
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$CONFIG_DIR"
    sudo mkdir -p "${INSTALL_DIR}/logs"
    sudo mkdir -p "${INSTALL_DIR}/data"
    sudo mkdir -p "${INSTALL_DIR}/backup"
    
    # Set proper ownership and permissions
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    chmod 700 "$CONFIG_DIR"  # More restrictive for config files
    chmod 755 "${INSTALL_DIR}/logs"
    chmod 755 "${INSTALL_DIR}/data"
    chmod 755 "${INSTALL_DIR}/backup"
    
    print_success "Directories created successfully"
}

# Secure configuration file permissions
secure_config_files() {
    print_step "Setting secure permissions for configuration files..."
    
    if [[ -d "$CONFIG_DIR" ]]; then
        find "$CONFIG_DIR" -name "*.yaml" -exec chmod 600 {} \;
        find "$CONFIG_DIR" -name "*.yaml" -exec chown "$USER:$USER" {} \;
        print_success "Configuration files secured"
    fi
}

# Welcome message with version info
show_welcome() {
    clear
    print_title "Element Server Suite Community Edition Deployment"
    print_info "Script Version: $SCRIPT_VERSION"
    print_info "Target ESS Chart Version: $ESS_CHART_VERSION"
    print_info "Based on: https://github.com/element-hq/ess-helm"
    echo
    print_info "This script will deploy Element Server Suite Community Edition"
    print_info "using Kubernetes (K3s) and Helm with enhanced security and best practices."
    echo
    print_warning "Please ensure you have:"
    print_info "  • A clean Debian-based system"
    print_info "  • At least 2 CPU cores and 2GB RAM"
    print_info "  • 5GB+ available disk space"
    print_info "  • Domain names configured in DNS"
    print_info "  • Email for Let's Encrypt certificates"
    echo
    
    read -p "Press Enter to continue or Ctrl+C to exit..."
}

# Enhanced system requirements check
check_system() {
    print_title "System Requirements Check"
    
    # Check OS
    if [[ ! -f /etc/debian_version ]]; then
        error_exit "This script only supports Debian-based systems"
    fi
    print_success "Operating system: Debian-based ✓"
    
    # Check user
    if [[ $EUID -eq 0 ]]; then
        error_exit "Please do not run this script as root user"
    fi
    print_success "User check: Non-root user ✓"
    
    # Check sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_warning "Sudo privileges required. Please enter password:"
        sudo -v || error_exit "Cannot obtain sudo privileges"
    fi
    print_success "Sudo privileges: Available ✓"
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error_exit "Network connection failed. Please check network settings"
    fi
    print_success "Network connectivity: Available ✓"
    
    # Check disk space (minimum 5GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB in KB
        error_exit "Insufficient disk space. At least 5GB available space required"
    fi
    print_success "Disk space: Sufficient ✓"
    
    # Check memory (minimum 2GB)
    local total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 1800 ]]; then  # Allow some margin
        print_warning "System has less than 2GB RAM. Performance may be affected"
    else
        print_success "Memory: Sufficient ✓"
    fi
    
    # Check CPU cores (minimum 2)
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 2 ]]; then
        print_warning "System has less than 2 CPU cores. Performance may be affected"
    else
        print_success "CPU cores: Sufficient ✓"
    fi
}

# Network requirements check
check_network_requirements() {
    print_title "Network Requirements Check"
    
    print_step "Checking port availability..."
    for port in "${REQUIRED_PORTS[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            error_exit "Port $port is already in use. Please free it before continuing"
        fi
        print_success "Port $port: Available ✓"
    done
    
    print_step "Checking DNS resolution..."
    if [[ -n "$DOMAIN_NAME" ]]; then
        if ! nslookup "$DOMAIN_NAME" &>/dev/null; then
            print_warning "Domain $DOMAIN_NAME cannot be resolved. Please ensure DNS is configured correctly"
        else
            print_success "Domain resolution: $DOMAIN_NAME ✓"
        fi
    fi
}

# Get public IP with multiple methods
get_public_ip() {
    print_step "Detecting public IP address..."
    
    local ip=""
    local methods=(
        "curl -s https://ipv4.icanhazip.com"
        "curl -s https://api.ipify.org"
        "curl -s https://checkip.amazonaws.com"
        "dig +short myip.opendns.com @resolver1.opendns.com"
    )
    
    for method in "${methods[@]}"; do
        if ip=$(timeout 10 $method 2>/dev/null) && [[ -n "$ip" ]]; then
            # Validate IP format
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                print_success "Public IP detected: $ip"
                echo "$ip"
                return 0
            fi
        fi
    done
    
    print_warning "Could not detect public IP automatically"
    return 1
}

# Enhanced domain configuration with validation
configure_domains() {
    print_title "Domain Configuration"
    
    print_info "You need to configure 5 domain names for ESS Community:"
    print_info "1. Server name (main domain)"
    print_info "2. Synapse server"
    print_info "3. Authentication service"
    print_info "4. RTC backend"
    print_info "5. Element Web client"
    echo
    
    # Get public IP
    local public_ip
    if public_ip=$(get_public_ip); then
        print_info "Please ensure all domains point to: $public_ip"
        echo
    fi
    
    # Server name (main domain)
    while [[ -z "$DOMAIN_NAME" ]]; do
        read -p "Enter server name (e.g., matrix.example.com): " DOMAIN_NAME
        if [[ -n "$DOMAIN_NAME" ]]; then
            validate_domain "$DOMAIN_NAME"
        fi
    done
    
    # Synapse domain
    while [[ -z "$SYNAPSE_DOMAIN" ]]; do
        read -p "Enter Synapse domain (e.g., synapse.example.com): " SYNAPSE_DOMAIN
        if [[ -n "$SYNAPSE_DOMAIN" ]]; then
            validate_domain "$SYNAPSE_DOMAIN"
        fi
    done
    
    # Authentication domain
    while [[ -z "$AUTH_DOMAIN" ]]; do
        read -p "Enter Authentication service domain (e.g., auth.example.com): " AUTH_DOMAIN
        if [[ -n "$AUTH_DOMAIN" ]]; then
            validate_domain "$AUTH_DOMAIN"
        fi
    done
    
    # RTC domain
    while [[ -z "$RTC_DOMAIN" ]]; do
        read -p "Enter RTC backend domain (e.g., rtc.example.com): " RTC_DOMAIN
        if [[ -n "$RTC_DOMAIN" ]]; then
            validate_domain "$RTC_DOMAIN"
        fi
    done
    
    # Web client domain
    while [[ -z "$WEB_DOMAIN" ]]; do
        read -p "Enter Element Web domain (e.g., chat.example.com): " WEB_DOMAIN
        if [[ -n "$WEB_DOMAIN" ]]; then
            validate_domain "$WEB_DOMAIN"
        fi
    done
    
    print_success "Domain configuration completed"
}

# Enhanced port configuration
configure_ports() {
    print_title "Port Configuration"
    
    print_info "ESS Community requires the following ports:"
    print_info "• TCP 80: HTTP (redirects to HTTPS)"
    print_info "• TCP 443: HTTPS"
    print_info "• TCP 30881: WebRTC TCP connections"
    print_info "• UDP 30882: WebRTC UDP connections"
    echo
    
    print_step "Generating port configuration..."
    cat > "${CONFIG_DIR}/ports.yaml" << EOF
# Port configuration for ESS Community
global:
  ports:
    http: 80
    https: 443
    webrtc:
      tcp: 30881
      udp: 30882

# Service-specific port configurations
services:
  traefik:
    ports:
      web:
        port: 80
        exposedPort: 80
      websecure:
        port: 443
        exposedPort: 443
  
  matrixRtcBackend:
    ports:
      webrtc:
        tcp: 30881
        udp: 30882
EOF
    
    print_success "Port configuration generated"
}

# Certificate configuration with enhanced options
configure_certificates() {
    print_title "Certificate Configuration"
    
    print_info "Choose certificate configuration method:"
    print_info "1. Let's Encrypt (automatic, recommended)"
    print_info "2. Existing wildcard certificate"
    print_info "3. Individual certificates"
    print_info "4. External reverse proxy (no TLS in cluster)"
    echo
    
    local cert_choice
    while [[ ! "$cert_choice" =~ ^[1-4]$ ]]; do
        read -p "Select option (1-4): " cert_choice
    done
    
    case $cert_choice in
        1)
            configure_letsencrypt
            ;;
        2)
            configure_wildcard_cert
            ;;
        3)
            configure_individual_certs
            ;;
        4)
            configure_external_proxy
            ;;
    esac
}

# Let's Encrypt configuration
configure_letsencrypt() {
    print_step "Configuring Let's Encrypt..."
    
    while [[ -z "$CERT_EMAIL" ]]; do
        read -p "Enter email for Let's Encrypt certificates: " CERT_EMAIL
        if [[ -n "$CERT_EMAIL" ]]; then
            validate_email "$CERT_EMAIL"
        fi
    done
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# Let's Encrypt TLS configuration
global:
  tls:
    mode: letsencrypt
    letsencrypt:
      email: "$CERT_EMAIL"
      server: https://acme-v02.api.letsencrypt.org/directory
      
# Certificate issuer configuration
certManager:
  enabled: true
  issuer:
    name: letsencrypt-prod
    email: "$CERT_EMAIL"
    server: https://acme-v02.api.letsencrypt.org/directory
    
# Ingress TLS configuration
ingress:
  tls:
    enabled: true
    issuer: letsencrypt-prod
EOF
    
    print_success "Let's Encrypt configuration completed"
}

# Wildcard certificate configuration
configure_wildcard_cert() {
    print_step "Configuring wildcard certificate..."
    
    print_info "Please ensure your wildcard certificate covers:"
    print_info "• $DOMAIN_NAME"
    print_info "• $SYNAPSE_DOMAIN"
    print_info "• $AUTH_DOMAIN"
    print_info "• $RTC_DOMAIN"
    print_info "• $WEB_DOMAIN"
    echo
    
    local cert_path key_path
    read -p "Enter path to certificate file: " cert_path
    read -p "Enter path to private key file: " key_path
    
    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        error_exit "Certificate or key file not found"
    fi
    
    # Import certificate to Kubernetes
    kubectl create secret tls ess-certificate -n "$NAMESPACE" \
        --cert="$cert_path" --key="$key_path" || error_exit "Failed to import certificate"
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# Wildcard certificate TLS configuration
global:
  tls:
    mode: existing
    secretName: ess-certificate
    
# Ingress TLS configuration
ingress:
  tls:
    enabled: true
    secretName: ess-certificate
EOF
    
    print_success "Wildcard certificate configuration completed"
}

# Individual certificates configuration
configure_individual_certs() {
    print_step "Configuring individual certificates..."
    
    print_info "You need separate certificates for each domain"
    
    local domains=("$WEB_DOMAIN" "$SYNAPSE_DOMAIN" "$AUTH_DOMAIN" "$RTC_DOMAIN" "$DOMAIN_NAME")
    local secrets=("ess-chat-certificate" "ess-matrix-certificate" "ess-auth-certificate" "ess-rtc-certificate" "ess-well-known-certificate")
    
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local secret="${secrets[$i]}"
        
        print_step "Configuring certificate for $domain..."
        
        local cert_path key_path
        read -p "Enter path to certificate file for $domain: " cert_path
        read -p "Enter path to private key file for $domain: " key_path
        
        if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
            error_exit "Certificate or key file not found for $domain"
        fi
        
        kubectl create secret tls "$secret" -n "$NAMESPACE" \
            --cert="$cert_path" --key="$key_path" || error_exit "Failed to import certificate for $domain"
    done
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# Individual certificates TLS configuration
global:
  tls:
    mode: individual
    
# Service-specific TLS configuration
services:
  elementWeb:
    tls:
      secretName: ess-chat-certificate
  synapse:
    tls:
      secretName: ess-matrix-certificate
  matrixAuthenticationService:
    tls:
      secretName: ess-auth-certificate
  matrixRtcBackend:
    tls:
      secretName: ess-rtc-certificate
  wellKnown:
    tls:
      secretName: ess-well-known-certificate
EOF
    
    print_success "Individual certificates configuration completed"
}

# External proxy configuration
configure_external_proxy() {
    print_step "Configuring for external reverse proxy..."
    
    print_info "External reverse proxy configuration selected"
    print_info "TLS will be terminated at the reverse proxy level"
    
    cat > "${CONFIG_DIR}/tls.yaml" << EOF
# External reverse proxy TLS configuration
global:
  tls:
    mode: disabled
    
# Ingress configuration for external proxy
ingress:
  tls:
    enabled: false
  annotations:
    kubernetes.io/ingress.class: traefik
    traefik.ingress.kubernetes.io/router.entrypoints: web
EOF
    
    print_success "External proxy configuration completed"
}

# Installation configuration
configure_installation() {
    print_title "Installation Configuration"
    
    while [[ -z "$ADMIN_EMAIL" ]]; do
        read -p "Enter administrator email: " ADMIN_EMAIL
        if [[ -n "$ADMIN_EMAIL" ]]; then
            validate_email "$ADMIN_EMAIL"
        fi
    done
    
    print_success "Installation configuration completed"
}

# Configuration summary
show_configuration_summary() {
    print_title "Configuration Summary"
    
    print_info "Installation Directory: $INSTALL_DIR"
    print_info "Namespace: $NAMESPACE"
    print_info "ESS Chart Version: $ESS_CHART_VERSION"
    echo
    print_info "Domain Configuration:"
    print_info "  Server Name: $DOMAIN_NAME"
    print_info "  Synapse: $SYNAPSE_DOMAIN"
    print_info "  Authentication: $AUTH_DOMAIN"
    print_info "  RTC Backend: $RTC_DOMAIN"
    print_info "  Element Web: $WEB_DOMAIN"
    echo
    print_info "Administrator Email: $ADMIN_EMAIL"
    if [[ -n "$CERT_EMAIL" ]]; then
        print_info "Certificate Email: $CERT_EMAIL"
    fi
    echo
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Configuration cancelled"
        exit 0
    fi
}

# Save configuration to file
save_configuration() {
    print_step "Saving configuration..."
    
    cat > "${CONFIG_DIR}/main.yaml" << EOF
# ESS Community Main Configuration
# Generated on: $(date)
# Script Version: $SCRIPT_VERSION

metadata:
  version: "$SCRIPT_VERSION"
  chartVersion: "$ESS_CHART_VERSION"
  generatedAt: "$(date -Iseconds)"
  
installation:
  directory: "$INSTALL_DIR"
  namespace: "$NAMESPACE"
  
domains:
  serverName: "$DOMAIN_NAME"
  synapse: "$SYNAPSE_DOMAIN"
  authentication: "$AUTH_DOMAIN"
  rtcBackend: "$RTC_DOMAIN"
  elementWeb: "$WEB_DOMAIN"
  
contacts:
  adminEmail: "$ADMIN_EMAIL"
  certEmail: "$CERT_EMAIL"
  
network:
  requiredPorts: [${REQUIRED_PORTS[*]}]
EOF
    
    secure_config_files
    print_success "Configuration saved to ${CONFIG_DIR}/main.yaml"
}

# Enhanced dependency installation with retry
install_dependencies() {
    print_title "Installing Dependencies"
    
    print_step "Updating package lists..."
    retry_command "sudo apt-get update" 3 5
    
    local packages=(
        "curl"
        "wget"
        "gnupg"
        "lsb-release"
        "ca-certificates"
        "apt-transport-https"
        "software-properties-common"
        "dnsutils"
        "net-tools"
        "jq"
    )
    
    print_step "Installing required packages..."
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            print_step "Installing $package..."
            retry_command "sudo apt-get install -y $package" 3 5
        else
            print_success "$package already installed"
        fi
    done
    
    print_success "Dependencies installation completed"
}

# K3s installation with enhanced configuration
install_k3s() {
    print_title "Installing K3s"
    
    if check_command k3s; then
        print_success "K3s already installed"
        return 0
    fi
    
    print_step "Installing K3s..."
    local k3s_config="--default-local-storage-path=${INSTALL_DIR}/data/k3s-storage"
    k3s_config+=" --disable=traefik"  # We'll configure Traefik separately
    
    retry_command "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"server ${k3s_config}\" sh -" 3 10
    
    print_step "Configuring kubectl access..."
    mkdir -p ~/.kube
    export KUBECONFIG=~/.kube/config
    sudo k3s kubectl config view --raw > "$KUBECONFIG"
    chmod 600 "$KUBECONFIG"
    chown "$USER:$USER" "$KUBECONFIG"
    
    # Add to bashrc for persistence
    if ! grep -q "export KUBECONFIG=~/.kube/config" ~/.bashrc; then
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
    fi
    
    print_step "Waiting for K3s to be ready..."
    local retries=0
    while ! sudo k3s kubectl get nodes &>/dev/null; do
        if [[ $retries -ge 30 ]]; then
            error_exit "K3s startup timeout"
        fi
        sleep 2
        ((retries++))
    done
    
    print_success "K3s installation completed"
}

# Traefik configuration for custom ports
configure_k3s_ports() {
    print_title "Configuring K3s Networking"
    
    print_step "Installing Traefik with custom configuration..."
    
    sudo tee /var/lib/rancher/k3s/server/manifests/traefik-config.yaml > /dev/null << EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    ports:
      web:
        port: 8080
        exposedPort: 80
      websecure:
        port: 8443
        exposedPort: 443
      webrtc-tcp:
        port: 30881
        exposedPort: 30881
        protocol: TCP
      webrtc-udp:
        port: 30882
        exposedPort: 30882
        protocol: UDP
    service:
      type: LoadBalancer
    additionalArguments:
      - "--entrypoints.webrtc-tcp.address=:30881/tcp"
      - "--entrypoints.webrtc-udp.address=:30882/udp"
EOF
    
    print_step "Restarting K3s to apply Traefik configuration..."
    sudo systemctl restart k3s
    
    # Wait for Traefik to be ready
    print_step "Waiting for Traefik to be ready..."
    local retries=0
    while ! sudo k3s kubectl get pods -n kube-system | grep traefik | grep -q Running; do
        if [[ $retries -ge 60 ]]; then
            error_exit "Traefik startup timeout"
        fi
        sleep 2
        ((retries++))
    done
    
    print_success "Traefik configuration completed"
}

# Helm installation
install_helm() {
    print_title "Installing Helm"
    
    if check_command helm; then
        print_success "Helm already installed"
        return 0
    fi
    
    print_step "Installing Helm..."
    retry_command "curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash" 3 10
    
    print_success "Helm installation completed"
}

# Namespace creation
create_namespace() {
    print_title "Creating Kubernetes Namespace"
    
    print_step "Creating namespace: $NAMESPACE"
    if ! sudo k3s kubectl get namespace "$NAMESPACE" &>/dev/null; then
        sudo k3s kubectl create namespace "$NAMESPACE"
        print_success "Namespace '$NAMESPACE' created"
    else
        print_success "Namespace '$NAMESPACE' already exists"
    fi
}

# Cert-manager installation with enhanced configuration
install_cert_manager() {
    print_title "Installing Cert-Manager"
    
    # Check if cert-manager is already installed
    if sudo k3s kubectl get namespace cert-manager &>/dev/null; then
        print_success "Cert-manager already installed"
        return 0
    fi
    
    print_step "Adding Jetstack Helm repository..."
    retry_command "helm repo add jetstack https://charts.jetstack.io --force-update" 3 5
    
    print_step "Updating Helm repositories..."
    retry_command "helm repo update" 3 5
    
    print_step "Installing cert-manager..."
    retry_command "helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.17.0 \
        --set crds.enabled=true \
        --wait \
        --timeout=10m" 3 10
    
    # Create ClusterIssuer for Let's Encrypt if using Let's Encrypt
    if [[ -n "$CERT_EMAIL" ]]; then
        print_step "Creating Let's Encrypt ClusterIssuer..."
        sudo k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod-private-key
    solvers:
      - http01:
          ingress:
            class: traefik
EOF
    fi
    
    print_success "Cert-manager installation completed"
}

# Cloudflare DNS configuration (optional)
configure_cloudflare_dns() {
    print_title "Cloudflare DNS Configuration (Optional)"
    
    print_info "Do you want to configure Cloudflare DNS validation for certificates?"
    print_info "This is useful for wildcard certificates or when HTTP validation is not possible."
    echo
    
    read -p "Configure Cloudflare DNS? (y/N): " use_cloudflare
    if [[ ! "$use_cloudflare" =~ ^[Yy]$ ]]; then
        print_info "Skipping Cloudflare DNS configuration"
        return 0
    fi
    
    read -p "Enter Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    read -p "Enter Cloudflare Zone ID: " CLOUDFLARE_ZONE_ID
    
    if [[ -z "$CLOUDFLARE_API_TOKEN" ]] || [[ -z "$CLOUDFLARE_ZONE_ID" ]]; then
        print_warning "Cloudflare credentials not provided, skipping DNS configuration"
        return 0
    fi
    
    # Create Cloudflare secret
    sudo k3s kubectl create secret generic cloudflare-api-token-secret \
        --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
        -n cert-manager
    
    # Create DNS ClusterIssuer
    sudo k3s kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $CERT_EMAIL
    privateKeySecretRef:
      name: letsencrypt-dns-prod-private-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - "$DOMAIN_NAME"
EOF
    
    print_success "Cloudflare DNS validation configured"
}

# Generate enhanced ESS configuration
generate_ess_config() {
    print_title "Generating ESS Configuration Files"
    
    print_step "Generating hostname configuration..."
    cat > "${CONFIG_DIR}/hostnames.yaml" << EOF
# ESS Community hostname configuration
# Generated on: $(date)

global:
  hosts:
    serverName: "$DOMAIN_NAME"
    synapse: "$SYNAPSE_DOMAIN"
    elementWeb: "$WEB_DOMAIN"
    matrixAuthenticationService: "$AUTH_DOMAIN"
    matrixRtcBackend: "$RTC_DOMAIN"
  
  # Server configuration
  server:
    name: "$DOMAIN_NAME"
    
  # Well-known delegation
  wellKnown:
    enabled: true
    server: "$SYNAPSE_DOMAIN"
    
# Deployment markers for tracking
deploymentMarkers:
  enabled: true
  version: "$ESS_CHART_VERSION"
  deployedAt: "$(date -Iseconds)"
  deployedBy: "$USER"
EOF
    
    print_step "Generating resource configuration..."
    cat > "${CONFIG_DIR}/resources.yaml" << EOF
# Resource limits and requests configuration
# Optimized for production deployment

global:
  resources:
    # Default resource settings
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

# Service-specific resource configuration
synapse:
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "4Gi"
      cpu: "2000m"
  
  # Synapse-specific configuration
  config:
    workers:
      enabled: true
      count: 2
    
postgresql:
  resources:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
  
  # PostgreSQL configuration
  persistence:
    enabled: true
    size: 10Gi
    storageClass: "local-path"

matrixAuthenticationService:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"

matrixRtcBackend:
  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

elementWeb:
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
      cpu: "200m"
EOF
    
    print_step "Generating security configuration..."
    cat > "${CONFIG_DIR}/security.yaml" << EOF
# Security configuration for ESS Community
# Implements security best practices

global:
  # Security context for all pods
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  
  # Pod security context
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  
  # Container security context
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000
    capabilities:
      drop:
        - ALL

# Network policies
networkPolicy:
  enabled: true
  ingress:
    enabled: true
  egress:
    enabled: true

# Pod disruption budgets
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Service mesh configuration (if using Istio)
serviceMesh:
  enabled: false
  mtls:
    mode: STRICT
EOF
    
    print_step "Generating monitoring configuration..."
    cat > "${CONFIG_DIR}/monitoring.yaml" << EOF
# Monitoring and observability configuration

# Prometheus monitoring
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
  
  # Grafana dashboards
  grafana:
    enabled: true
    dashboards:
      enabled: true
  
  # Alerting rules
  prometheusRule:
    enabled: true
    rules:
      - alert: SynapseDown
        expr: up{job="synapse"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Synapse is down"
          description: "Synapse has been down for more than 5 minutes"

# Logging configuration
logging:
  enabled: true
  level: INFO
  
  # Log aggregation
  fluentd:
    enabled: false
  
  # Log retention
  retention:
    days: 30

# Health checks
healthChecks:
  enabled: true
  livenessProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 3
  
  readinessProbe:
    enabled: true
    initialDelaySeconds: 5
    periodSeconds: 5
    timeoutSeconds: 3
    failureThreshold: 3
  
  startupProbe:
    enabled: true
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30
EOF
    
    secure_config_files
    print_success "ESS configuration files generated"
}

# Configuration validation
validate_configuration() {
    print_title "Validating Configuration"
    
    print_step "Validating YAML syntax..."
    for config_file in "${CONFIG_DIR}"/*.yaml; do
        if [[ -f "$config_file" ]]; then
            if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                error_exit "Configuration file syntax error: $config_file"
            fi
            print_success "$(basename "$config_file"): Valid ✓"
        fi
    done
    
    print_step "Validating Kubernetes connectivity..."
    if ! sudo k3s kubectl cluster-info &>/dev/null; then
        error_exit "Kubernetes cluster is not accessible"
    fi
    print_success "Kubernetes connectivity: OK ✓"
    
    print_step "Validating Helm repositories..."
    if ! helm repo list | grep -q jetstack; then
        print_warning "Jetstack repository not found, adding..."
        helm repo add jetstack https://charts.jetstack.io --force-update
    fi
    print_success "Helm repositories: OK ✓"
    
    print_success "Configuration validation completed"
}

# Enhanced ESS deployment
deploy_ess() {
    print_title "Deploying ESS Community"
    
    validate_configuration
    
    print_step "Deploying Matrix Stack with Helm..."
    print_info "Chart Version: $ESS_CHART_VERSION"
    print_info "Namespace: $NAMESPACE"
    
    # Prepare Helm command with all configuration files
    local helm_cmd="helm upgrade --install --namespace \"$NAMESPACE\" ess"
    helm_cmd+=" oci://ghcr.io/element-hq/ess-helm/matrix-stack"
    helm_cmd+=" --version \"$ESS_CHART_VERSION\""
    helm_cmd+=" -f \"${CONFIG_DIR}/hostnames.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/tls.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/ports.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/resources.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/security.yaml\""
    helm_cmd+=" -f \"${CONFIG_DIR}/monitoring.yaml\""
    helm_cmd+=" --wait"
    helm_cmd+=" --timeout=20m"
    
    # Execute deployment with retry
    retry_command "$helm_cmd" 2 30
    
    print_step "Waiting for all pods to be ready..."
    local retries=0
    local max_retries=60
    
    while true; do
        local pending_pods=$(sudo k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
        
        if [[ $pending_pods -eq 0 ]]; then
            break
        fi
        
        if [[ $retries -ge $max_retries ]]; then
            print_error "Timeout waiting for pods to be ready"
            sudo k3s kubectl get pods -n "$NAMESPACE"
            error_exit "Deployment timeout"
        fi
        
        show_progress $retries $max_retries "Waiting for pods to be ready... ($pending_pods pending)"
        sleep 5
        ((retries++))
    done
    
    print_success "ESS Community deployment completed"
}

# Create initial user with enhanced options
create_initial_user() {
    print_title "Creating Initial User"
    
    print_info "ESS Community does not allow user registration by default."
    print_info "You need to create an initial administrator user."
    echo
    
    read -p "Create initial user now? (Y/n): " create_user
    if [[ "$create_user" =~ ^[Nn]$ ]]; then
        print_info "Skipping user creation. You can create users later using:"
        print_info "kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
        return 0
    fi
    
    print_step "Creating initial user..."
    print_info "Follow the prompts to create your administrator user:"
    
    # Interactive user creation
    sudo k3s kubectl exec -n "$NAMESPACE" -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user
    
    print_success "Initial user creation completed"
}

# Backup functionality
backup_configuration() {
    print_title "Creating Configuration Backup"
    
    local backup_dir="${INSTALL_DIR}/backup/config-$(date +%Y%m%d-%H%M%S)"
    print_step "Creating backup directory: $backup_dir"
    
    mkdir -p "$backup_dir"
    cp -r "${CONFIG_DIR}"/* "$backup_dir/"
    
    # Create backup metadata
    cat > "$backup_dir/backup-info.yaml" << EOF
# Backup Information
backupDate: "$(date -Iseconds)"
scriptVersion: "$SCRIPT_VERSION"
chartVersion: "$ESS_CHART_VERSION"
namespace: "$NAMESPACE"
domains:
  serverName: "$DOMAIN_NAME"
  synapse: "$SYNAPSE_DOMAIN"
  authentication: "$AUTH_DOMAIN"
  rtcBackend: "$RTC_DOMAIN"
  elementWeb: "$WEB_DOMAIN"
EOF
    
    # Set secure permissions
    chmod -R 600 "$backup_dir"
    chown -R "$USER:$USER" "$backup_dir"
    
    print_success "Configuration backup created: $backup_dir"
}

# Database backup functionality
backup_database() {
    print_title "Creating Database Backup"
    
    local backup_file="${INSTALL_DIR}/backup/postgres-$(date +%Y%m%d-%H%M%S).sql"
    print_step "Creating database backup: $backup_file"
    
    # Create database backup
    if sudo k3s kubectl exec -n "$NAMESPACE" deployment/ess-postgresql -- pg_dump -U synapse synapse > "$backup_file"; then
        chmod 600 "$backup_file"
        chown "$USER:$USER" "$backup_file"
        print_success "Database backup created: $backup_file"
    else
        print_error "Database backup failed"
        return 1
    fi
}

# Enhanced deployment verification
verify_deployment() {
    print_title "Verifying Deployment"
    
    print_step "Checking pod status..."
    local failed_pods=$(sudo k3s kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
    
    if [[ $failed_pods -gt 0 ]]; then
        print_error "Some pods are not running:"
        sudo k3s kubectl get pods -n "$NAMESPACE"
        return 1
    fi
    print_success "All pods are running ✓"
    
    print_step "Checking service endpoints..."
    local services=("ess-synapse" "ess-element-web" "ess-matrix-authentication-service")
    for service in "${services[@]}"; do
        if sudo k3s kubectl get service "$service" -n "$NAMESPACE" &>/dev/null; then
            print_success "Service $service: Available ✓"
        else
            print_warning "Service $service: Not found"
        fi
    done
    
    print_step "Checking ingress configuration..."
    if sudo k3s kubectl get ingress -n "$NAMESPACE" &>/dev/null; then
        print_success "Ingress configuration: Available ✓"
    else
        print_warning "Ingress configuration: Not found"
    fi
    
    print_step "Testing internal connectivity..."
    # Test if Synapse is responding
    if sudo k3s kubectl exec -n "$NAMESPACE" deployment/ess-synapse -- curl -s http://localhost:8008/health &>/dev/null; then
        print_success "Synapse health check: OK ✓"
    else
        print_warning "Synapse health check: Failed"
    fi
    
    print_success "Deployment verification completed"
}

# Enhanced completion information
show_completion_info() {
    print_title "Deployment Completed Successfully!"
    
    print_success "ESS Community has been deployed successfully!"
    echo
    
    print_info "Access Information:"
    print_info "• Element Web Client: https://$WEB_DOMAIN"
    print_info "• Server Name: $DOMAIN_NAME"
    print_info "• Synapse Server: https://$SYNAPSE_DOMAIN"
    print_info "• Authentication Service: https://$AUTH_DOMAIN"
    print_info "• RTC Backend: https://$RTC_DOMAIN"
    echo
    
    print_info "Administrative Information:"
    print_info "• Installation Directory: $INSTALL_DIR"
    print_info "• Configuration Files: $CONFIG_DIR"
    print_info "• Kubernetes Namespace: $NAMESPACE"
    print_info "• Log File: $LOG_FILE"
    echo
    
    print_info "Useful Commands:"
    print_info "• Check pod status: kubectl get pods -n $NAMESPACE"
    print_info "• View logs: kubectl logs -n $NAMESPACE deployment/ess-synapse"
    print_info "• Create user: kubectl exec -n $NAMESPACE -it deploy/ess-matrix-authentication-service -- mas-cli manage register-user"
    print_info "• Backup database: kubectl exec -n $NAMESPACE deployment/ess-postgresql -- pg_dump -U synapse synapse > backup.sql"
    echo
    
    print_info "Next Steps:"
    print_info "1. Test federation: https://federationtester.matrix.org/"
    print_info "2. Configure Element clients with server: $DOMAIN_NAME"
    print_info "3. Set up monitoring and alerting"
    print_info "4. Configure regular backups"
    echo
    
    print_warning "Security Recommendations:"
    print_info "• Regularly update ESS Community"
    print_info "• Monitor system resources and logs"
    print_info "• Implement proper backup strategy"
    print_info "• Review and update security configurations"
    echo
    
    # Create completion marker
    echo "$(date -Iseconds)" > "${INSTALL_DIR}/.deployment-completed"
    
    print_success "Deployment information saved. Enjoy your Matrix server!"
}

# Cleanup environment function
cleanup_environment() {
    print_title "Environment Cleanup"
    
    print_warning "This will remove the entire ESS Community installation!"
    print_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "Cleanup cancelled"
        return 0
    fi
    
    print_step "Creating final backup before cleanup..."
    backup_configuration
    backup_database
    
    print_step "Removing Helm deployment..."
    helm uninstall ess -n "$NAMESPACE" || true
    
    print_step "Removing namespace..."
    sudo k3s kubectl delete namespace "$NAMESPACE" || true
    
    print_step "Removing cert-manager..."
    helm uninstall cert-manager -n cert-manager || true
    sudo k3s kubectl delete namespace cert-manager || true
    
    print_step "Stopping K3s..."
    sudo systemctl stop k3s || true
    
    read -p "Remove K3s completely? (y/N): " remove_k3s
    if [[ "$remove_k3s" =~ ^[Yy]$ ]]; then
        print_step "Uninstalling K3s..."
        sudo /usr/local/bin/k3s-uninstall.sh || true
    fi
    
    read -p "Remove installation directory? (y/N): " remove_dir
    if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
        print_step "Removing installation directory..."
        sudo rm -rf "$INSTALL_DIR"
    fi
    
    print_success "Environment cleanup completed"
}

# Restart services function
restart_services() {
    print_title "Restarting Services"
    
    print_step "Restarting ESS Community deployment..."
    sudo k3s kubectl rollout restart deployment -n "$NAMESPACE"
    
    print_step "Waiting for pods to be ready..."
    sudo k3s kubectl rollout status deployment -n "$NAMESPACE" --timeout=300s
    
    print_success "Services restarted successfully"
}

# Enhanced main menu
show_main_menu() {
    while true; do
        clear
        print_title "ESS Community Management Menu"
        print_info "Installation Directory: $INSTALL_DIR"
        print_info "Namespace: $NAMESPACE"
        print_info "Chart Version: $ESS_CHART_VERSION"
        echo
        
        print_info "Available Options:"
        print_info "1. View deployment status"
        print_info "2. Create user account"
        print_info "3. Backup configuration"
        print_info "4. Backup database"
        print_info "5. Restart services"
        print_info "6. View logs"
        print_info "7. Update deployment"
        print_info "8. Cleanup environment"
        print_info "9. Exit"
        echo
        
        read -p "Select option (1-9): " choice
        
        case $choice in
            1)
                sudo k3s kubectl get pods -n "$NAMESPACE"
                echo
                sudo k3s kubectl get services -n "$NAMESPACE"
                echo
                read -p "Press Enter to continue..."
                ;;
            2)
                create_initial_user
                read -p "Press Enter to continue..."
                ;;
            3)
                backup_configuration
                read -p "Press Enter to continue..."
                ;;
            4)
                backup_database
                read -p "Press Enter to continue..."
                ;;
            5)
                restart_services
                read -p "Press Enter to continue..."
                ;;
            6)
                print_info "Available deployments:"
                sudo k3s kubectl get deployments -n "$NAMESPACE"
                echo
                read -p "Enter deployment name to view logs: " deployment
                if [[ -n "$deployment" ]]; then
                    sudo k3s kubectl logs -n "$NAMESPACE" deployment/"$deployment" --tail=50
                fi
                read -p "Press Enter to continue..."
                ;;
            7)
                print_warning "Update functionality not implemented yet"
                read -p "Press Enter to continue..."
                ;;
            8)
                cleanup_environment
                if [[ ! -d "$INSTALL_DIR" ]]; then
                    exit 0
                fi
                ;;
            9)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-9."
                sleep 2
                ;;
        esac
    done
}

# Main deployment function
main_deployment() {
    log "Starting ESS Community deployment - Script version $SCRIPT_VERSION"
    
    show_welcome
    create_directories
    check_system
    configure_domains
    check_network_requirements
    configure_ports
    configure_certificates
    configure_installation
    show_configuration_summary
    save_configuration
    install_dependencies
    install_k3s
    configure_k3s_ports
    install_helm
    create_namespace
    install_cert_manager
    configure_cloudflare_dns
    generate_ess_config
    deploy_ess
    create_initial_user
    verify_deployment
    backup_configuration
    show_completion_info
    
    log "ESS Community deployment completed successfully"
}

# Main function
main() {
    # Check if already deployed
    if [[ -f "${INSTALL_DIR}/config/main.yaml" ]] && sudo k3s kubectl get namespace "$NAMESPACE" &>/dev/null; then
        show_main_menu
    else
        main_deployment
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
