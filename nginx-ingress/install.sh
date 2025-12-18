#!/bin/bash

# Install nginx Ingress Controller for DNS Automation
# This script installs the nginx ingress controller required for our DNS automation setup

set -e

echo "🚀 Installing nginx Ingress Controller..."

# Install nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml

echo "⏳ Waiting for nginx ingress controller to be ready..."

# Wait for the ingress controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "✅ nginx Ingress Controller installed successfully!"

# Show the LoadBalancer IP
echo "📋 nginx Ingress Controller Service:"
kubectl get svc ingress-nginx-controller -n ingress-nginx

echo ""
echo "🎯 nginx ingress controller is ready for DNS automation!"
echo "   - External DNS will create Route53 records pointing to the LoadBalancer IP"
echo "   - cert-manager will provision SSL certificates for ingresses"
echo "   - ApplicationSet will generate ingresses with className: nginx"