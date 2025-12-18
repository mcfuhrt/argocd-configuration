#!/usr/bin/env bash
#
# update-github-secrets.sh - Update GitHub SSH key and token secrets in ArgoCD
#
# Usage: ./update-github-secrets.sh

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi

print_section "Update GitHub Secrets for ArgoCD"

echo "This script will help you update the GitHub SSH key and token secrets."
echo ""

# Update SSH key
print_section "GitHub SSH Key Configuration"

echo "To access private GitHub repositories, ArgoCD needs an SSH key."
echo ""
print_info "Reference: https://medium.com/@tiwarisan/argocd-how-to-access-private-github-repository-with-ssh-key-new-way-49cc4431971b"
echo ""

# Check if SSH key exists
DEFAULT_SSH_KEY="$HOME/.ssh/argocd_github"
if [ -f "$DEFAULT_SSH_KEY" ]; then
    print_info "Found existing SSH key: $DEFAULT_SSH_KEY"
    read -p "Use this key? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        read -p "Enter path to SSH private key: " SSH_KEY_PATH
    else
        SSH_KEY_PATH="$DEFAULT_SSH_KEY"
    fi
else
    print_warning "No SSH key found at $DEFAULT_SSH_KEY"
    echo ""
    echo "Would you like to:"
    echo "  1) Generate a new SSH key"
    echo "  2) Specify an existing SSH key path"
    echo "  3) Skip SSH key configuration"
    read -p "Choose option (1-3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            print_info "Generating new SSH key..."
            mkdir -p "$HOME/.ssh"
            ssh-keygen -t ed25519 -C "argocd@gke-cluster" -f "$DEFAULT_SSH_KEY" -N ""
            SSH_KEY_PATH="$DEFAULT_SSH_KEY"
            
            print_success "SSH key generated"
            echo ""
            print_warning "IMPORTANT: Add the following public key to your GitHub account:"
            echo "https://github.com/settings/keys"
            echo ""
            cat "${DEFAULT_SSH_KEY}.pub"
            echo ""
            read -p "Press Enter after adding the key to GitHub..." -r
            ;;
        2)
            read -p "Enter path to SSH private key: " SSH_KEY_PATH
            ;;
        3)
            print_warning "Skipping SSH key configuration"
            SSH_KEY_PATH=""
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
fi

if [ -n "$SSH_KEY_PATH" ]; then
    if [ ! -f "$SSH_KEY_PATH" ]; then
        print_error "SSH key file not found: $SSH_KEY_PATH"
        exit 1
    fi
    
    print_info "Updating GitHub SSH key secret in ArgoCD..."
    
    kubectl create secret generic github-ssh-key \
        --from-literal=type=git \
        --from-literal=url=git@github.com:mcfuhrt \
        --from-file=sshPrivateKey="$SSH_KEY_PATH" \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl label secret github-ssh-key \
        -n argocd \
        argocd.argoproj.io/secret-type=repository \
        --overwrite
    
    print_success "GitHub SSH key secret updated"
    
    # Test SSH connection
    print_info "Testing SSH connection to GitHub..."
    if ssh -T git@github.com -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" 2>&1 | grep -q "successfully authenticated"; then
        print_success "SSH connection to GitHub successful"
    else
        print_warning "Could not verify SSH connection. Please check manually."
    fi
fi

# Update GitHub token
print_section "GitHub Token Configuration (for Pull Request Generator)"

echo "To use the Pull Request generator in ApplicationSet, you need a GitHub Personal Access Token."
echo ""
print_info "Create a token at: https://github.com/settings/tokens"
print_info "Required scopes: repo (full control)"
echo ""

read -p "Do you want to update the GitHub token? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    read -sp "Enter GitHub Personal Access Token: " GITHUB_TOKEN
    echo ""
    
    if [ -z "$GITHUB_TOKEN" ]; then
        print_warning "No token provided, skipping"
    else
        print_info "Updating GitHub token secret in ArgoCD..."
        
        kubectl create secret generic github-token \
            --from-literal=token="$GITHUB_TOKEN" \
            -n argocd \
            --dry-run=client -o yaml | kubectl apply -f -
        
        print_success "GitHub token secret updated"
    fi
else
    print_warning "Skipping GitHub token configuration"
fi

# Verify secrets
print_section "Verification"

echo "Current secrets in ArgoCD namespace:"
kubectl get secrets -n argocd | grep -E "github-ssh-key|github-token"

echo ""
print_info "To verify ArgoCD can access your repositories:"
echo "  1. Access ArgoCD UI"
echo "  2. Go to Settings > Repositories"
echo "  3. Check connection status for git@github.com:mcfuhrt"
echo ""

print_success "Secret configuration complete!"
