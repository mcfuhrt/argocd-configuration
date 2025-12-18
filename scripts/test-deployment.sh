#!/usr/bin/env bash
#
# test-deployment.sh - Test the deployed infrastructure end-to-end
#
# Usage: ./test-deployment.sh

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    print_info "Testing: $test_name"
    
    if eval "$test_command" &> /dev/null; then
        print_success "$test_name: PASS"
        ((TESTS_PASSED++))
        return 0
    else
        print_error "$test_name: FAIL"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Main test suite
main() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                    Infrastructure End-to-End Tests                           ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    
    # Test 1: Cluster connectivity
    print_section "Test 1: Cluster Connectivity"
    
    run_test "kubectl cluster access" "kubectl cluster-info"
    run_test "GKE nodes are ready" "kubectl get nodes | grep -q Ready"
    
    # Test 2: ArgoCD installation
    print_section "Test 2: ArgoCD Installation"
    
    run_test "ArgoCD namespace exists" "kubectl get namespace argocd"
    run_test "ArgoCD server is running" "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server | grep -q Running"
    run_test "ArgoCD repo-server is running" "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server | grep -q Running"
    run_test "ArgoCD applicationset-controller is running" "kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller | grep -q Running"
    
    # Test 3: Secrets configuration
    print_section "Test 3: Secrets Configuration"
    
    run_test "GitHub SSH key secret exists" "kubectl get secret github-ssh-key -n argocd"
    run_test "GitHub token secret exists" "kubectl get secret github-token -n argocd"
    
    # Test 4: Recce namespace and service account
    print_section "Test 4: Recce Configuration"
    
    run_test "Recce namespace exists" "kubectl get namespace recce"
    run_test "Recce service account exists" "kubectl get serviceaccount datahub-dbt -n recce"
    
    # Check Workload Identity annotation
    local sa_annotation
    sa_annotation=$(kubectl get serviceaccount datahub-dbt -n recce -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}' 2>/dev/null || echo "")
    if [ -n "$sa_annotation" ]; then
        print_success "Workload Identity is configured: $sa_annotation"
        ((TESTS_PASSED++))
    else
        print_error "Workload Identity annotation missing"
        ((TESTS_FAILED++))
    fi
    
    # Test 5: GCS bucket
    print_section "Test 5: GCS Bucket"
    
    cd "$TERRAFORM_DIR"
    local bucket_name
    bucket_name=$(terraform output -raw gcs_bucket_name 2>/dev/null || echo "")
    
    if [ -n "$bucket_name" ]; then
        run_test "GCS bucket exists" "gcloud storage ls gs://$bucket_name"
        
        # Test write access
        print_info "Testing write access to GCS bucket..."
        if echo "test-$(date +%s)" | gcloud storage cp - "gs://$bucket_name/test-file.txt" 2>/dev/null; then
            print_success "Write access to bucket: PASS"
            ((TESTS_PASSED++))
            gcloud storage rm "gs://$bucket_name/test-file.txt" 2>/dev/null || true
        else
            print_error "Write access to bucket: FAIL"
            ((TESTS_FAILED++))
        fi
    else
        print_error "Could not retrieve bucket name from Terraform"
        ((TESTS_FAILED++))
    fi
    
    # Test 6: ArgoCD applications
    print_section "Test 6: ArgoCD Applications"
    
    # Check if project is deployed
    if kubectl get appproject recce -n argocd &> /dev/null; then
        print_success "ArgoCD project 'recce' exists"
        ((TESTS_PASSED++))
    else
        print_warning "ArgoCD project 'recce' not found (may not be deployed yet)"
        print_info "Run: kubectl apply -f ../projects/recce/project.yaml"
    fi
    
    # Check if applications are deployed
    local app_count
    app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$app_count" -gt 0 ]; then
        print_success "Found $app_count ArgoCD application(s)"
        ((TESTS_PASSED++))
        kubectl get applications -n argocd
    else
        print_warning "No ArgoCD applications found (may not be deployed yet)"
        print_info "Run: kubectl apply -f ../projects/recce/recce-project-watcher.yaml"
    fi
    
    # Test 7: Ingress and networking
    print_section "Test 7: Ingress and Networking"
    
    run_test "ArgoCD ingress exists" "kubectl get ingress argocd-server-ingress -n argocd"
    
    # Check managed certificate
    if kubectl get managedcertificate argocd-cert -n argocd &> /dev/null; then
        local cert_status
        cert_status=$(kubectl get managedcertificate argocd-cert -n argocd -o jsonpath='{.status.certificateStatus}' 2>/dev/null || echo "Unknown")
        if [ "$cert_status" = "Active" ]; then
            print_success "Managed certificate is Active"
            ((TESTS_PASSED++))
        else
            print_warning "Managed certificate status: $cert_status (may take 10-30 minutes)"
        fi
    else
        print_warning "Managed certificate not found"
    fi
    
    # Check static IP
    local ingress_ip
    ingress_ip=$(terraform output -raw argocd_ingress_ip 2>/dev/null || echo "")
    if [ -n "$ingress_ip" ]; then
        print_success "Static IP allocated: $ingress_ip"
        ((TESTS_PASSED++))
    else
        print_error "Could not retrieve ingress IP"
        ((TESTS_FAILED++))
    fi
    
    # Test 8: DNS and connectivity
    print_section "Test 8: DNS and Connectivity"
    
    local argocd_domain
    argocd_domain=$(cd "$TERRAFORM_DIR" && terraform output -raw argocd_url 2>/dev/null | sed 's|https://||' || echo "")
    
    if [ -n "$argocd_domain" ] && [ "$argocd_domain" != "https://argocd.example.com" ]; then
        print_info "Testing DNS resolution for: $argocd_domain"
        local resolved_ip
        resolved_ip=$(dig +short "$argocd_domain" | head -n 1 || echo "")
        
        if [ -n "$resolved_ip" ]; then
            print_success "DNS resolves to: $resolved_ip"
            ((TESTS_PASSED++))
            
            if [ "$resolved_ip" = "$ingress_ip" ]; then
                print_success "DNS points to correct ingress IP"
                ((TESTS_PASSED++))
            else
                print_warning "DNS does not point to ingress IP ($ingress_ip)"
            fi
        else
            print_warning "DNS not configured yet"
            print_info "Add A record: $argocd_domain -> $ingress_ip"
        fi
    else
        print_warning "ArgoCD domain not configured (using example.com)"
    fi
    
    # Summary
    print_section "Test Summary"
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    echo ""
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo "Total Tests:  $total_tests"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed! 🎉"
        echo ""
        print_info "Next steps:"
        echo "  1. Access ArgoCD UI: $(cd "$TERRAFORM_DIR" && terraform output -raw argocd_url)"
        echo "  2. Deploy applications: kubectl apply -f ../projects/recce/project.yaml"
        echo "  3. Monitor applications: kubectl get applications -n argocd"
        exit 0
    else
        print_error "Some tests failed. Please review the errors above."
        exit 1
    fi
}

main
