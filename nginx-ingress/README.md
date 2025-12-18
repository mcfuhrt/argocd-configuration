# nginx Ingress Controller Installation

This document explains how to install the nginx ingress controller that our DNS automation depends on.

## Installation

The nginx ingress controller was installed using:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

## Verification

Check that it's running:
```bash
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

The ingress controller should get an external LoadBalancer IP which External DNS will use for creating DNS records.

## Why nginx Instead of GCE?

We switched from GCE ingress to nginx ingress because:
1. GCE ingress controller was not provisioning external IPs reliably
2. nginx ingress controller provisions LoadBalancer services immediately  
3. nginx ingress handles TLS termination properly with cert-manager certificates
4. More predictable behavior across different GKE configurations

## Integration with Our Setup

The ApplicationSet in `applications/recce/recce.applicationset.yaml` is configured to use:
```yaml
ingress:
  className: "nginx"
```

External DNS automatically detects ingresses and creates DNS records pointing to the nginx LoadBalancer IP.