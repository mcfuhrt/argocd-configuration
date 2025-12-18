#!/bin/bash

# DNS Automation Setup Script for sikwel.de
# This script helps you implement automatic DNS subdomain creation

set -e

echo "🚀 DNS Automation Setup for ArgoCD + Route53"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${GREEN}Step $1: $2${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Step 0: Install nginx Ingress Controller
print_step "0" "Installing nginx Ingress Controller"
echo "Installing nginx ingress controller for proper HTTPS/TLS handling..."
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo "Installing nginx ingress controller..."
    ./nginx-ingress/install.sh
else
    echo "✅ nginx ingress controller already installed"
fi

# Step 1: Prerequisites Check
print_step "1" "Checking Prerequisites"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can access the cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ kubectl is working"
echo "✅ Connected to cluster: $(kubectl config current-context)"

# Step 2: AWS Credentials
print_step "2" "AWS Credentials Setup"

echo "You need to create an AWS IAM user with Route53 permissions."
echo "Required IAM policy:"
cat << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": [
                "arn:aws:route53:::hostedzone/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ListResourceRecordSets",
                "route53:ListTagsForResource"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF

echo ""
read -p "Enter your AWS Access Key ID: " AWS_ACCESS_KEY_ID
read -s -p "Enter your AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
echo ""
read -p "Enter your AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

# Step 3: Install cert-manager
print_step "3" "Installing cert-manager"

if kubectl get namespace cert-manager &> /dev/null; then
    echo "✅ cert-manager namespace already exists"
else
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
    kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
    
    echo "✅ cert-manager installed successfully"
fi

# Step 4: Create AWS credentials secret
print_step "4" "Creating AWS Credentials Secret"

kubectl create namespace external-dns-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic aws-credentials \
  --from-literal=aws-access-key-id="$AWS_ACCESS_KEY_ID" \
  --from-literal=aws-secret-access-key="$AWS_SECRET_ACCESS_KEY" \
  -n external-dns-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ AWS credentials secret created"

# Step 5: Deploy External DNS
print_step "5" "Deploying External DNS"

kubectl apply -f /workspaces/recce-demo/argocd-configuration/external-dns/external-dns.yaml

echo "Waiting for External DNS to be ready..."
kubectl wait --for=condition=Available --timeout=300s deployment/external-dns -n external-dns-system

echo "✅ External DNS deployed successfully"

# Step 6: Create ClusterIssuer
print_step "6" "Creating Let's Encrypt ClusterIssuer"

# Update the ClusterIssuer with actual AWS credentials
sed -i "s/accessKeyID: \"\"/accessKeyID: \"$AWS_ACCESS_KEY_ID\"/" /workspaces/recce-demo/argocd-configuration/cert-manager/cluster-issuer.yaml
sed -i "s/region: us-east-1/region: $AWS_REGION/" /workspaces/recce-demo/argocd-configuration/cert-manager/cluster-issuer.yaml

kubectl apply -f /workspaces/recce-demo/argocd-configuration/cert-manager/cluster-issuer.yaml

echo "✅ ClusterIssuer created successfully"

# Step 7: Update ApplicationSet
print_step "7" "Updating ApplicationSet"

kubectl apply -f /workspaces/recce-demo/argocd-configuration/applications/recce/recce.applicationset.yaml

echo "✅ ApplicationSet updated"

# Step 8: Verification
print_step "8" "Verification"

echo "Checking External DNS logs..."
kubectl logs -n external-dns-system deployment/external-dns --tail=10

echo "Checking cert-manager status..."
kubectl get clusterissuer

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Create a new PR in your argo-dbt repository"
echo "2. Wait for ArgoCD to deploy the application"
echo "3. Check that DNS record is created: dig pr-{number}.sikwel.de"
echo "4. Verify HTTPS certificate: curl -I https://pr-{number}.sikwel.de"
echo ""
echo "Monitoring commands:"
echo "- External DNS logs: kubectl logs -n external-dns-system deployment/external-dns -f"
echo "- Certificates: kubectl get certificates -A"
echo "- Applications: kubectl get applications -n argocd"