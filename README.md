# ArgoCD Configuration for Recce Multi-PR Deployments

This repository contains the complete infrastructure setup for automatic deployment of Recce applications via Pull Requests with DNS automation, SSL certificates, and GCS data integration.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub PR     │───▶│   ArgoCD         │───▶│  GKE Cluster    │
│   (argo-dbt)    │    │   ApplicationSet │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                │                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Route53 DNS   │◀───│  External DNS    │◀───│ nginx Ingress   │
│  (sikwel.de)    │    │   Controller     │    │   Controller    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                       │                        │
        │              ┌──────────────────┐              │
        └──────────────│   cert-manager   │◀─────────────┘
                       │  (Let's Encrypt) │
                       └──────────────────┘
                                │
                       ┌──────────────────┐
                       │  GCS Bucket      │
                       │ (recce-data)     │
                       └──────────────────┘
```

## 🎯 Features

- **Automatic PR Deployments**: Each PR in `mcfuhrt/argo-dbt` creates a unique deployment
- **DNS Automation**: Automatic subdomain creation (`pr-X.sikwel.de`)
- **SSL Certificates**: Automatic Let's Encrypt certificates via cert-manager
- **Data Persistence**: GCS bucket integration with Workload Identity
- **HTTPS Redirect**: Automatic HTTP to HTTPS redirection
- **Clean Teardown**: Resources are automatically cleaned up when PRs are closed

## 📋 Prerequisites

- **GKE Cluster** (created via Terraform)
- **Route53 Domain** (sikwel.de)
- **AWS Credentials** (for Route53 management)
- **Google Cloud Project** with required APIs enabled
- **GitHub Token** (for PR monitoring)

## 🚀 Quick Start

### 1. Infrastructure Setup

```bash
# Clone the repository
git clone https://github.com/mcfuhrt/argocd-configuration.git
cd argocd-configuration

# Setup infrastructure with Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply

# Get cluster credentials
gcloud container clusters get-credentials argocd-recce-poc --zone europe-west3 --project sikwel-playground
```

### 2. DNS Automation Setup

```bash
# Run the automated setup script
./setup-dns-automation.sh
```

This script will:
- Install nginx Ingress Controller
- Deploy External DNS with Route53 integration
- Install cert-manager with Let's Encrypt ClusterIssuer
- Deploy ArgoCD ApplicationSet for PR monitoring
- Verify all components are working

### 3. Create a Pull Request

1. Create a PR in `mcfuhrt/argo-dbt` repository
2. ArgoCD automatically detects the PR
3. New deployment is created: `recce-pr-X`
4. DNS record is created: `pr-X.sikwel.de`
5. SSL certificate is provisioned automatically
6. Access your application at `https://pr-X.sikwel.de`

## 🔧 Component Details

### Terraform Infrastructure (`terraform/`)

Creates the foundational GKE cluster with:
- **GKE Cluster**: `argocd-recce-poc` in `europe-west3`
- **Node Pool**: 1-3 nodes (e2-standard-2)
- **Workload Identity**: For secure GCS access
- **Service Accounts**: For external DNS and GCS integration
- **GCS Bucket**: `sikwel-playground-recce-data`

Key files:
- `main.tf`: Core infrastructure definition
- `variables.tf`: Configuration variables
- `outputs.tf`: Important output values

### ArgoCD Setup (`applications/`, `projects/`)

#### Project Configuration (`projects/recce/`)
- **project.yaml**: Defines the recce ArgoCD project with permissions
- **recce-project-watcher.yaml**: Monitors project health

#### ApplicationSet (`applications/recce/`)
- **recce.applicationset.yaml**: Main ApplicationSet that monitors PRs

```yaml
# Key features of the ApplicationSet:
generators:
  - pullRequest:
      github:
        owner: mcfuhrt
        repo: argo-dbt
        tokenRef:
          secretName: github-token
          key: token

# Auto-generates applications with:
# - Unique names: recce-{branch}-{number}
# - nginx ingress with External DNS annotations
# - cert-manager SSL certificates
# - GCS data integration
```

### DNS Automation (`external-dns/`)

External DNS automatically manages Route53 records:

```yaml
# Monitors both ingresses and services
args:
  - --source=ingress
  - --source=service
  - --domain-filter=sikwel.de
  - --provider=aws
  - --registry=txt
  - --txt-owner-id=gke-cluster-external-dns
```

### SSL Certificates (`cert-manager/`)

Automated SSL certificate management:

```yaml
# ClusterIssuer for Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
    - dns01:
        route53:
          region: us-east-1
```

### Ingress Controller (`nginx-ingress/`)

nginx Ingress Controller for reliable HTTPS handling:
- LoadBalancer service for external access
- Automatic HTTP to HTTPS redirect
- SSL termination
- External DNS integration

## 🔐 Security & Access

### Service Accounts

1. **Workload Identity Service Account**
   - Used for GCS bucket access
   - Bound to Kubernetes service account `datahub-dbt`

2. **External DNS Service Account**
   - Route53 permissions for DNS record management
   - IAM user: `route53-argo-cd`

3. **cert-manager Service Account**
   - Route53 permissions for DNS-01 challenges
   - Same IAM user as External DNS

### Required AWS IAM Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:ListHostedZones",
                "route53:ListResourceRecordSets",
                "route53:ListHostedZonesByName",
                "route53:GetChange"
            ],
            "Resource": "*"
        }
    ]
}
```

### Secrets Management

Required secrets:
- `github-token`: GitHub personal access token
- `argocd-ssh-key`: SSH key for private repositories
- `aws-credentials`: AWS access keys for Route53

## 📊 Monitoring & Debugging

### Check Component Status

```bash
# ArgoCD Applications
kubectl get applications -n argocd

# External DNS
kubectl logs -l app.kubernetes.io/name=external-dns -n external-dns-system

# cert-manager
kubectl get certificates -A
kubectl describe clusterissuer letsencrypt-prod

# nginx Ingress
kubectl get ingress -A
kubectl get svc -n ingress-nginx
```

### Troubleshooting

1. **DNS not resolving**:
   ```bash
   # Check External DNS logs
   kubectl logs -l app=external-dns -n external-dns-system
   
   # Verify Route53 permissions
   aws route53 list-hosted-zones
   ```

2. **SSL certificate issues**:
   ```bash
   # Check cert-manager logs
   kubectl logs -l app=cert-manager -n cert-manager
   
   # Check certificate status
   kubectl describe certificate recce-pr-X-tls -n recce
   ```

3. **Application not accessible**:
   ```bash
   # Check ingress status
   kubectl get ingress recce-pr-X -n recce
   
   # Check nginx controller
   kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
   ```

## 🔄 Workflow Example

1. **Developer creates PR in `mcfuhrt/argo-dbt`**
2. **ArgoCD ApplicationSet detects PR**
   - Creates new application: `recce-feature123-7`
   - Deploys to namespace: `recce`
3. **nginx Ingress Controller**
   - Creates LoadBalancer service
   - Gets external IP: `34.185.139.242`
4. **External DNS**
   - Detects ingress with annotations
   - Creates Route53 A record: `pr-7.sikwel.de → 34.185.139.242`
5. **cert-manager**
   - Detects ingress with TLS configuration
   - Creates Let's Encrypt certificate via DNS-01 challenge
6. **Application Ready**
   - HTTPS access: `https://pr-7.sikwel.de`
   - Automatic HTTP redirect
   - Valid SSL certificate

## 📁 Directory Structure

```
argocd-configuration/
├── applications/           # ArgoCD Application definitions
│   └── recce/             # Recce ApplicationSet
├── cert-manager/          # SSL certificate management
├── configuration/         # ArgoCD configuration
├── external-dns/          # DNS automation
├── nginx-ingress/         # Ingress controller
├── projects/              # ArgoCD projects
│   └── recce/            # Recce project definition
├── scripts/               # Utility scripts
├── terraform/             # Infrastructure as code
├── setup-dns-automation.sh # Automated setup script
└── README.md              # This file
```

## 🔧 Configuration Files

### Key Configuration Files

- **ApplicationSet**: `applications/recce/recce.applicationset.yaml`
- **External DNS**: `external-dns/external-dns.yaml`
- **cert-manager**: `cert-manager/cluster-issuer.yaml`
- **nginx Ingress**: `nginx-ingress/install.sh`
- **Terraform**: `terraform/main.tf`

### Environment-Specific Values

Applications use Helm value overrides:
- `overrides/stg.yaml`: Staging environment configuration
- `overrides/prd.yaml`: Production environment configuration

## 🚀 Advanced Usage

### Custom Domains

To add additional domains, update External DNS domain filter:
```yaml
args:
  - --domain-filter=sikwel.de
  - --domain-filter=yourdomain.com
```

### Multiple Repositories

Add additional ApplicationSets for different repositories:
```yaml
generators:
- pullRequest:
    github:
      owner: yourorg
      repo: another-repo
```

### Resource Scaling

Adjust node pool and resource limits in `terraform/main.tf`:
```hcl
node_config {
  machine_type = "e2-standard-4"  # Larger instances
}
```

## 📝 Maintenance

### Regular Tasks

1. **Update ArgoCD**: Follow ArgoCD upgrade documentation
2. **Certificate Renewal**: Automatic via cert-manager
3. **DNS Records**: Automatic via External DNS
4. **Terraform State**: Backup `terraform.tfstate` regularly

### Backup Strategy

1. **ArgoCD Configuration**: Version controlled in this repository
2. **Terraform State**: Stored locally (consider remote backend)
3. **Kubernetes Resources**: Backed up via ArgoCD sync

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes in development environment
4. Submit a pull request

## 📞 Support

For issues and questions:
1. Check the troubleshooting section
2. Review component logs
3. Consult ArgoCD and Kubernetes documentation
4. Open an issue in this repository

## 🔗 References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [External DNS](https://github.com/kubernetes-sigs/external-dns)
- [cert-manager](https://cert-manager.io/)
- [nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Terraform GKE](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
