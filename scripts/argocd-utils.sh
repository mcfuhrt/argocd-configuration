#!/usr/bin/env bash
#
# argocd-utils.sh - Utility commands for ArgoCD management
#
# Usage: ./argocd-utils.sh <command> [options]

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

# Show usage
usage() {
    cat << EOF
ArgoCD Utility Commands

Usage: $(basename "$0") <command> [options]

Commands:
    password              Get ArgoCD admin password
    port-forward          Start port-forward to ArgoCD server
    login                 Login to ArgoCD CLI
    apps                  List all applications
    sync <app>            Sync an application
    delete <app>          Delete an application
    logs <app>            Get application logs
    status                Show cluster and ArgoCD status
    repos                 List configured repositories
    test-repo             Test repository connection
    help                  Show this help message

Examples:
    # Get admin password
    $(basename "$0") password

    # Access ArgoCD UI
    $(basename "$0") port-forward

    # List applications
    $(basename "$0") apps

    # Sync an application
    $(basename "$0") sync recce

    # View application logs
    $(basename "$0") logs recce

EOF
    exit 0
}

# Get ArgoCD password
get_password() {
    print_info "Retrieving ArgoCD admin password..."
    local password
    password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || {
        print_error "Could not retrieve password. Is ArgoCD installed?"
        exit 1
    }
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ArgoCD Admin Credentials"
    echo "═══════════════════════════════════════════════════════════"
    echo "  Username: admin"
    echo "  Password: $password"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    print_success "Password retrieved successfully"
}

# Port-forward to ArgoCD
port_forward() {
    print_info "Starting port-forward to ArgoCD server..."
    print_info "ArgoCD will be accessible at: https://localhost:8080"
    print_info "Press Ctrl+C to stop"
    echo ""
    
    kubectl port-forward svc/argocd-server -n argocd 8080:443
}

# Login to ArgoCD CLI
argocd_login() {
    if ! command -v argocd &> /dev/null; then
        print_error "ArgoCD CLI is not installed"
        print_info "Install from: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        exit 1
    fi
    
    print_info "Logging in to ArgoCD..."
    
    local password
    password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    # Start port-forward in background
    kubectl port-forward svc/argocd-server -n argocd 8080:443 &>/dev/null &
    local pf_pid=$!
    
    sleep 2
    
    argocd login localhost:8080 \
        --username admin \
        --password "$password" \
        --insecure
    
    kill $pf_pid 2>/dev/null || true
    
    print_success "Logged in to ArgoCD"
}

# List applications
list_apps() {
    print_info "ArgoCD Applications:"
    echo ""
    kubectl get applications -n argocd -o wide
}

# Sync application
sync_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        print_error "Application name required"
        echo "Usage: $(basename "$0") sync <app-name>"
        exit 1
    fi
    
    print_info "Syncing application: $app_name"
    
    if command -v argocd &> /dev/null; then
        argocd app sync "$app_name"
    else
        kubectl patch application "$app_name" -n argocd \
            --type merge -p '{"operation": {"initiatedBy": {"username": "cli"}, "sync": {}}}'
    fi
    
    print_success "Sync initiated for $app_name"
}

# Delete application
delete_app() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        print_error "Application name required"
        echo "Usage: $(basename "$0") delete <app-name>"
        exit 1
    fi
    
    print_warning "This will delete the application: $app_name"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled"
        exit 0
    fi
    
    print_info "Deleting application: $app_name"
    kubectl delete application "$app_name" -n argocd
    
    print_success "Application $app_name deleted"
}

# Get application logs
app_logs() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        print_error "Application name required"
        echo "Usage: $(basename "$0") logs <app-name>"
        exit 1
    fi
    
    print_info "Getting logs for application: $app_name"
    
    # Get namespace from application
    local namespace
    namespace=$(kubectl get application "$app_name" -n argocd \
        -o jsonpath='{.spec.destination.namespace}' 2>/dev/null)
    
    if [ -z "$namespace" ]; then
        print_error "Could not find application: $app_name"
        exit 1
    fi
    
    print_info "Application namespace: $namespace"
    echo ""
    
    # Get pods in namespace
    local pods
    pods=$(kubectl get pods -n "$namespace" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    
    if [ -z "$pods" ]; then
        print_warning "No pods found in namespace: $namespace"
        exit 0
    fi
    
    echo "Pods in namespace $namespace:"
    echo "$pods" | nl -w2 -s'. '
    echo ""
    
    # If only one pod, show logs directly
    local pod_count
    pod_count=$(echo "$pods" | wc -l)
    
    if [ "$pod_count" -eq 1 ]; then
        print_info "Showing logs for: $pods"
        kubectl logs -n "$namespace" "$pods" --tail=50 -f
    else
        read -p "Enter pod number (or 'a' for all): " choice
        
        if [ "$choice" = "a" ]; then
            kubectl logs -n "$namespace" --all-containers=true --tail=50
        else
            local selected_pod
            selected_pod=$(echo "$pods" | sed -n "${choice}p")
            kubectl logs -n "$namespace" "$selected_pod" --tail=50 -f
        fi
    fi
}

# Show status
show_status() {
    print_info "Cluster and ArgoCD Status"
    echo ""
    
    # Cluster info
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Cluster Information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl cluster-info | grep -E "Kubernetes|running"
    echo ""
    
    # Nodes
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Nodes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl get nodes
    echo ""
    
    # ArgoCD pods
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ArgoCD Pods"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl get pods -n argocd
    echo ""
    
    # Applications
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Applications"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if kubectl get applications -n argocd --no-headers 2>/dev/null | grep -q .; then
        kubectl get applications -n argocd
    else
        print_warning "No applications deployed yet"
    fi
    echo ""
    
    # Ingress
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ingress"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    kubectl get ingress -n argocd
    echo ""
}

# List repositories
list_repos() {
    print_info "Configured Repositories:"
    echo ""
    
    kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository \
        -o custom-columns=NAME:.metadata.name,URL:.data.url | \
        while read -r line; do
            echo "$line" | awk '{print $1"\t"$2}' | \
                sed 's/\([A-Za-z0-9+/]\{4\}\)/echo "\1" | base64 -d/e'
        done
}

# Test repository connection
test_repo() {
    print_info "Testing repository connection..."
    
    local repo_server_pod
    repo_server_pod=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server \
        -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$repo_server_pod" ]; then
        print_error "Could not find repo-server pod"
        exit 1
    fi
    
    print_info "Testing SSH connection to GitHub..."
    kubectl exec -n argocd "$repo_server_pod" -- \
        ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 || true
    
    echo ""
    print_success "Test complete"
}

# Main command dispatcher
case "${1:-help}" in
    password)
        get_password
        ;;
    port-forward|pf)
        port_forward
        ;;
    login)
        argocd_login
        ;;
    apps|list)
        list_apps
        ;;
    sync)
        sync_app "${2:-}"
        ;;
    delete|del)
        delete_app "${2:-}"
        ;;
    logs)
        app_logs "${2:-}"
        ;;
    status)
        show_status
        ;;
    repos)
        list_repos
        ;;
    test-repo)
        test_repo
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        usage
        ;;
esac
