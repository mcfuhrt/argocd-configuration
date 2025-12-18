#!/usr/bin/env bash
#
# initialize.sh - Initialize and deploy the GKE + ArgoCD + Recce infrastructure
#
# Usage: ./initialize.sh [options]
# Options:
#   -h, --help              Show this help message
#   -p, --project PROJECT   GCP project ID (default: sikwel-playground)
#   -r, --region REGION     GCP region (default: europe-west3)
#   -y, --yes               Skip confirmation prompts
#   --skip-gcloud-auth      Skip gcloud authentication
#   --skip-terraform-init   Skip terraform init

set -euo pipefail

# Default values
PROJECT_ID="${PROJECT_ID:-sikwel-playground}"
REGION="${REGION:-europe-west3}"
SKIP_CONFIRM=false
SKIP_GCLOUD_AUTH=false
SKIP_TERRAFORM_INIT=false

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

Initialize and deploy the GKE + ArgoCD + Recce infrastructure on GCP.

Options:
    -h, --help              Show this help message
    -p, --project PROJECT   GCP project ID (default: sikwel-playground)
    -r, --region REGION     GCP region (default: europe-west3)
    -y, --yes               Skip confirmation prompts
    --skip-gcloud-auth      Skip gcloud authentication
    --skip-terraform-init   Skip terraform init

Environment Variables:
    PROJECT_ID              GCP project ID
    REGION                  GCP region

Examples:
    # Interactive deployment
    ./initialize.sh

    # Non-interactive deployment
    ./initialize.sh --yes

    # Custom project and region
    ./initialize.sh --project my-project --region us-central1

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
        --skip-gcloud-auth)
            SKIP_GCLOUD_AUTH=true
            shift
            ;;
        --skip-terraform-init)
            SKIP_TERRAFORM_INIT=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check gcloud
    if ! command -v gcloud &> /dev/null; then
        missing_tools+=("gcloud (Google Cloud SDK)")
    else
        print_success "gcloud: $(gcloud version --format='value(core)' 2>/dev/null)"
    fi
    
    # Check terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    else
        print_success "terraform: $(terraform version -json | jq -r '.terraform_version')"
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    else
        print_success "kubectl: $(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')"
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        echo ""
        print_info "Please install the missing tools and try again."
        exit 1
    fi
}

# Authenticate with GCP
authenticate_gcp() {
    if [ "$SKIP_GCLOUD_AUTH" = true ]; then
        print_info "Skipping gcloud authentication"
        return
    fi
    
    print_section "Authenticating with GCP"
    
    print_info "Checking gcloud authentication..."
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "No active gcloud authentication found"
        print_info "Running: gcloud auth login"
        gcloud auth login
    else
        print_success "Already authenticated with gcloud"
    fi
    
    print_info "Setting GCP project to: $PROJECT_ID"
    gcloud config set project "$PROJECT_ID"
    
    print_info "Checking application default credentials..."
    if ! gcloud auth application-default print-access-token &> /dev/null; then
        print_warning "Application default credentials not found"
        print_info "Running: gcloud auth application-default login"
        gcloud auth application-default login
    else
        print_success "Application default credentials are configured"
    fi
}

# Prepare Terraform configuration
prepare_terraform() {
    print_section "Preparing Terraform Configuration"
    
    cd "$TERRAFORM_DIR"
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        print_info "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        
        # Update project_id and region
        sed -i.bak "s/project_id = .*/project_id = \"$PROJECT_ID\"/" terraform.tfvars
        sed -i.bak "s/region = .*/region = \"$REGION\"/" terraform.tfvars
        rm -f terraform.tfvars.bak
        
        print_warning "Please edit terraform.tfvars and update the following:"
        echo "  - argocd_domain (required for ingress)"
        echo "  - github_ssh_private_key (required for repo access)"
        echo "  - github_token (required for PR generator)"
        echo ""
        
        if [ "$SKIP_CONFIRM" = false ]; then
            read -p "Open terraform.tfvars in editor now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ${EDITOR:-vi} terraform.tfvars
            fi
        fi
    else
        print_success "terraform.tfvars already exists"
    fi
    
    # Initialize Terraform
    if [ "$SKIP_TERRAFORM_INIT" = false ]; then
        print_info "Initializing Terraform..."
        terraform init
        print_success "Terraform initialized"
    else
        print_info "Skipping terraform init"
    fi
}

# Show deployment plan
show_plan() {
    print_section "Terraform Deployment Plan"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Generating Terraform plan..."
    terraform plan -out=tfplan
    
    if [ "$SKIP_CONFIRM" = false ]; then
        echo ""
        read -p "Do you want to proceed with this deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled"
            rm -f tfplan
            exit 0
        fi
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    print_section "Deploying Infrastructure"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Starting Terraform apply..."
    print_warning "This will take approximately 10-15 minutes..."
    
    terraform apply tfplan
    
    rm -f tfplan
    
    print_success "Infrastructure deployed successfully!"
}

# Configure kubectl
configure_kubectl() {
    print_section "Configuring kubectl"
    
    cd "$TERRAFORM_DIR"
    
    local cluster_name
    cluster_name=$(terraform output -raw cluster_name)
    
    print_info "Getting cluster credentials..."
    gcloud container clusters get-credentials "$cluster_name" \
        --region "$REGION" \
        --project "$PROJECT_ID"
    
    print_info "Verifying cluster access..."
    kubectl cluster-info
    
    print_success "kubectl configured successfully"
}

# Install ArgoCD
install_argocd() {
    print_section "Installing ArgoCD"
    
    cd "$TERRAFORM_DIR"
    
    print_info "Creating argocd namespace..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "Installing ArgoCD using official installation manifest..."
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_info "Waiting for ArgoCD pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
    
    print_info "Patching argocd-server service for GCP Load Balancer..."
    kubectl annotate service argocd-server -n argocd \
        cloud.google.com/neg='{"ingress": true}' \
        cloud.google.com/backend-config='{"ports": {"http":"argocd-backend-config"}}' \
        --overwrite
    
    print_info "Creating BackendConfig for ArgoCD..."
    kubectl apply -f "$SCRIPT_DIR/../argocd-backendconfig.yaml"
    
    print_info "Creating FrontendConfig for ArgoCD..."
    kubectl apply -f "$SCRIPT_DIR/../argocd-frontendconfig.yaml"
    
    print_info "Creating ManagedCertificate for ArgoCD..."
    kubectl apply -f "$TERRAFORM_DIR/argocd-managed-cert.yaml"
    
    print_info "Creating Ingress for ArgoCD..."
    local argocd_domain
    argocd_domain=$(terraform output -raw argocd_domain)
    local ingress_ip
    ingress_ip=$(terraform output -raw ingress_ip_name)
    
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "gce"
    kubernetes.io/ingress.global-static-ip-name: "$ingress_ip"
    networking.gke.io/managed-certificates: "argocd-cert"
    networking.gke.io/v1beta1.FrontendConfig: "argocd-frontend-config"
    kubernetes.io/ingress.allow-http: "false"
spec:
  rules:
  - host: $argocd_domain
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
    
    print_info "Configuring ArgoCD for insecure mode (SSL termination at load balancer)..."
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge \
        -p '{"data":{"server.insecure":"true"}}'
    
    print_info "Restarting ArgoCD server..."
    kubectl rollout restart deployment argocd-server -n argocd
    kubectl rollout status deployment argocd-server -n argocd --timeout=120s
    
    print_success "ArgoCD installed successfully!"
    
    # Get initial admin password
    print_info "Retrieving ArgoCD initial admin password..."
    local admin_password
    admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo ""
    print_success "ArgoCD Admin Credentials:"
    echo "  Username: admin"
    echo "  Password: $admin_password"
    echo "  URL: https://$argocd_domain"
    echo ""
    print_warning "Please save these credentials securely!"
    print_warning "Delete the secret after changing the password: kubectl delete secret argocd-initial-admin-secret -n argocd"
    echo ""
}

# Show next steps
show_next_steps() {
    print_section "Deployment Complete!"
    
    cd "$TERRAFORM_DIR"
    
    echo ""
    terraform output -raw next_steps
    echo ""
    
    # Save outputs to file
    print_info "Saving outputs to outputs.json..."
    terraform output -json > outputs.json
    print_success "Outputs saved to: $TERRAFORM_DIR/outputs.json"
}

# Main execution
main() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║          GKE + ArgoCD + Recce Infrastructure Initialization                  ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    
    echo ""
    print_info "Project ID: $PROJECT_ID"
    print_info "Region: $REGION"
    echo ""
    
    if [ "$SKIP_CONFIRM" = false ]; then
        read -p "Continue with initialization? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Initialization cancelled"
            exit 0
        fi
    fi
    
    check_prerequisites
    authenticate_gcp
    prepare_terraform
    show_plan
    deploy_infrastructure
    configure_kubectl
    install_argocd
    show_next_steps
    
    print_success "All done! 🎉"
}

# Run main function
main
