#!/usr/bin/env bash
#
# cleanup.sh - Destroy the GKE + ArgoCD + Recce infrastructure
#
# Usage: ./cleanup.sh [options]

set -euo pipefail

# Default values
PROJECT_ID="${PROJECT_ID:-sikwel-playground}"
REGION="${REGION:-europe-west3}"
SKIP_CONFIRM=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

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

usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Destroy the GKE + ArgoCD + Recce infrastructure.

Options:
    -h, --help              Show this help message
    -p, --project PROJECT   GCP project ID (default: sikwel-playground)
    -r, --region REGION     GCP region (default: europe-west3)
    -y, --yes               Skip confirmation prompts

WARNING: This will permanently delete all resources including:
  - GKE cluster and all workloads
  - GCS bucket and ALL data
  - VPC and networking
  - Service accounts and IAM bindings

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

main() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                    Infrastructure Cleanup (Destroy)                          ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    print_warning "This will PERMANENTLY DELETE the following resources:"
    echo "  - GKE cluster: $(cd "$TERRAFORM_DIR" && terraform output -raw cluster_name 2>/dev/null || echo 'N/A')"
    echo "  - GCS bucket: $(cd "$TERRAFORM_DIR" && terraform output -raw gcs_bucket_name 2>/dev/null || echo 'N/A')"
    echo "  - All networking resources"
    echo "  - All service accounts"
    echo ""
    print_error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    if [ "$SKIP_CONFIRM" = false ]; then
        read -p "Type 'yes' to confirm destruction: " confirmation
        if [ "$confirmation" != "yes" ]; then
            print_warning "Cleanup cancelled"
            exit 0
        fi
        
        echo ""
        read -p "Are you absolutely sure? Type 'destroy' to proceed: " final_confirmation
        if [ "$final_confirmation" != "destroy" ]; then
            print_warning "Cleanup cancelled"
            exit 0
        fi
    fi
    
    print_section "Destroying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Running terraform destroy..."
    print_warning "This may take 5-10 minutes..."
    
    terraform destroy -auto-approve
    
    print_success "Infrastructure destroyed successfully"
    
    print_section "Cleanup Complete"
    
    print_info "The following resources have been deleted:"
    echo "  ✓ GKE cluster and all workloads"
    echo "  ✓ GCS bucket and all data"
    echo "  ✓ VPC and networking"
    echo "  ✓ Service accounts and IAM bindings"
    echo ""
    
    print_warning "Don't forget to:"
    echo "  - Remove DNS records for ArgoCD domain"
    echo "  - Clean up any local Kubernetes contexts"
    echo "  - Remove SSH keys from GitHub (if no longer needed)"
    echo ""
}

main
