#!/usr/bin/env bash
#
# setup-route53-dns.sh - Configure Route53 DNS for ArgoCD
#
# Usage: ./setup-route53-dns.sh [options]
# Options:
#   -h, --help              Show this help message
#   -d, --domain DOMAIN     Your Route53 domain (e.g., example.com)
#   -s, --subdomain NAME    Subdomain for ArgoCD (default: argocd)
#   -i, --ip IP             Static IP address (will auto-detect from terraform if not provided)

set -euo pipefail

# Default values
SUBDOMAIN="argocd"
STATIC_IP=""
DOMAIN=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform"

# Print colored output
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

# Show usage
usage() {
    cat << EOF
Usage: $(basename "$0") [options]

Configure Route53 DNS record for ArgoCD.

Options:
    -h, --help              Show this help message
    -d, --domain DOMAIN     Your Route53 domain (required, e.g., example.com)
    -s, --subdomain NAME    Subdomain for ArgoCD (default: argocd)
    -i, --ip IP             Static IP address (auto-detected from terraform if not provided)

Examples:
    # Auto-detect IP from terraform
    ./setup-route53-dns.sh --domain example.com

    # Specify custom subdomain
    ./setup-route53-dns.sh --domain example.com --subdomain argo

    # Specify custom IP
    ./setup-route53-dns.sh --domain example.com --ip 34.120.123.45

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -s|--subdomain)
            SUBDOMAIN="$2"
            shift 2
            ;;
        -i|--ip)
            STATIC_IP="$2"
            shift 2
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$DOMAIN" ]; then
    print_error "Domain is required. Use --domain to specify your Route53 domain."
    usage
fi

print_section "Route53 DNS Configuration for ArgoCD"

print_info "Domain: $DOMAIN"
print_info "Subdomain: $SUBDOMAIN"
FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
print_info "Full domain: $FULL_DOMAIN"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed"
    print_info "Install it from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
print_info "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured"
    print_info "Run: aws configure"
    exit 1
fi
print_success "AWS credentials configured"

# Get static IP from terraform if not provided
if [ -z "$STATIC_IP" ]; then
    print_section "Getting Static IP from Terraform"
    
    cd "$TERRAFORM_DIR"
    
    if [ ! -f "terraform.tfstate" ]; then
        print_error "Terraform state not found. Deploy infrastructure first with: ./initialize.sh"
        exit 1
    fi
    
    STATIC_IP=$(terraform output -raw argocd_ingress_ip 2>/dev/null || echo "")
    
    if [ -z "$STATIC_IP" ] || [ "$STATIC_IP" == "null" ]; then
        print_error "Could not get static IP from terraform. Deploy infrastructure first."
        exit 1
    fi
    
    print_success "Static IP: $STATIC_IP"
fi

# Get hosted zone ID
print_section "Finding Route53 Hosted Zone"

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --query "HostedZones[?Name=='$DOMAIN.'].Id" \
    --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    print_error "Could not find hosted zone for domain: $DOMAIN"
    print_info "Available hosted zones:"
    aws route53 list-hosted-zones --query "HostedZones[*].[Name,Id]" --output table
    exit 1
fi

print_success "Found hosted zone: $HOSTED_ZONE_ID"

# Check if record already exists
print_section "Checking Existing DNS Records"

EXISTING_RECORD=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --query "ResourceRecordSets[?Name=='$FULL_DOMAIN.' && Type=='A'].ResourceRecords[0].Value" \
    --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_RECORD" ] && [ "$EXISTING_RECORD" != "None" ]; then
    print_warning "A record already exists for $FULL_DOMAIN pointing to: $EXISTING_RECORD"
    
    if [ "$EXISTING_RECORD" == "$STATIC_IP" ]; then
        print_success "DNS record is already correctly configured!"
        
        # Verify DNS resolution
        print_section "Verifying DNS Resolution"
        print_info "Checking DNS resolution for $FULL_DOMAIN..."
        
        if command -v dig &> /dev/null; then
            dig +short "$FULL_DOMAIN"
        else
            nslookup "$FULL_DOMAIN"
        fi
        
        exit 0
    fi
    
    read -p "Update existing record to $STATIC_IP? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "DNS update cancelled"
        exit 0
    fi
fi

# Create or update DNS record
print_section "Creating/Updating DNS Record"

print_info "Creating A record: $FULL_DOMAIN -> $STATIC_IP"

CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$FULL_DOMAIN",
      "Type": "A",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$STATIC_IP"}]
    }
  }]
}
EOF
)

CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query "ChangeInfo.Id" \
    --output text | cut -d'/' -f3)

if [ -n "$CHANGE_ID" ]; then
    print_success "DNS record created/updated successfully!"
    print_info "Change ID: $CHANGE_ID"
    
    # Wait for change to propagate
    print_info "Waiting for DNS change to propagate..."
    
    aws route53 wait resource-record-sets-changed --id "/change/$CHANGE_ID" 2>/dev/null || true
    
    print_success "DNS change has propagated on Route53"
else
    print_error "Failed to create/update DNS record"
    exit 1
fi

# Verify DNS resolution
print_section "Verifying DNS Resolution"

print_info "Waiting for DNS to propagate globally (this may take a few minutes)..."
sleep 5

if command -v dig &> /dev/null; then
    print_info "DNS resolution:"
    dig +short "$FULL_DOMAIN" || print_warning "DNS not yet propagated"
else
    nslookup "$FULL_DOMAIN" || print_warning "DNS not yet propagated"
fi

# Update terraform.tfvars if needed
print_section "Updating Terraform Configuration"

cd "$TERRAFORM_DIR"

if [ -f "terraform.tfvars" ]; then
    # Check current domain
    CURRENT_DOMAIN=$(grep -E '^argocd_domain\s*=' terraform.tfvars | sed -E 's/.*=\s*"(.*)".*/\1/' || echo "")
    
    if [ "$CURRENT_DOMAIN" != "$FULL_DOMAIN" ]; then
        print_info "Updating argocd_domain in terraform.tfvars..."
        sed -i.bak "s|argocd_domain = .*|argocd_domain = \"$FULL_DOMAIN\"|" terraform.tfvars
        rm -f terraform.tfvars.bak
        print_success "Updated terraform.tfvars with domain: $FULL_DOMAIN"
        
        print_warning "You need to re-apply terraform for the ingress to use the new domain:"
        echo "  cd $TERRAFORM_DIR"
        echo "  terraform apply"
    else
        print_success "terraform.tfvars already has the correct domain"
    fi
fi

# Final summary
print_section "Setup Complete!"

cat << EOF

✅ DNS Configuration Summary:
   Domain:        $FULL_DOMAIN
   IP Address:    $STATIC_IP
   Hosted Zone:   $HOSTED_ZONE_ID
   Change ID:     $CHANGE_ID

⏱️  Next Steps:

1. Wait for global DNS propagation (5-15 minutes):
   dig $FULL_DOMAIN
   
2. The Google-managed certificate will automatically provision (10-30 minutes after DNS)
   Check status: kubectl describe managedcertificate argocd-cert -n argocd

3. Access ArgoCD:
   https://$FULL_DOMAIN
   
   Or use port-forward for immediate access:
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   
4. Get admin password:
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

EOF
