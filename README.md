# ArgoCD Configuration Repository

GitOps configuration repository for deploying and managing applications on GKE using ArgoCD.

## 🏗️ Architecture

This repository implements a complete GitOps workflow with:

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Repositories                         │
├─────────────────────────────────────────────────────────────────┤
│  RepoA (argocd-configuration)                                   │
│    └── ArgoCD projects, applications, ApplicationSets           │
│                                                                  │
│  RepoB (argo-applications/recce)                                │
│    └── Helm charts and application manifests                    │
│                                                                  │
│  RepoC (argo-applications)                                      │
│    └── Application code that triggers PR-based deployments      │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GKE Cluster (GCP)                           │
├─────────────────────────────────────────────────────────────────┤
│  ArgoCD (GitOps Controller)                                     │
│    ├── Watches Git repositories                                 │
│    ├── Syncs Kubernetes manifests                               │
│    └── Manages ApplicationSets for PR-based deploys             │
│                                                                  │
│  Recce Application                                              │
│    ├── Data validation and comparison tool                      │
│    ├── GCS Fuse for bucket synchronization                      │
│    └── Nginx reverse proxy                                      │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Google Cloud Storage                          │
│                   (Shared Data Volume)                           │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 Repository Structure

```
argocd-configuration/
├── applications/              # ArgoCD Application definitions
│   └── recce/
│       └── recce.applicationset.yaml
├── projects/                  # ArgoCD Project definitions
│   └── recce/
│       ├── project.yaml
│       └── recce-project-watcher.yaml
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # GKE cluster, ArgoCD, GCS bucket
│   ├── variables.tf          # Configuration variables
│   ├── outputs.tf            # Output values
│   ├── argocd-values.yaml    # ArgoCD Helm values
│   └── README.md             # Detailed documentation
├── scripts/                   # Helper scripts
│   ├── initialize.sh         # Deploy infrastructure
│   ├── update-github-secrets.sh  # Configure GitHub access
│   ├── test-deployment.sh    # End-to-end tests
│   └── cleanup.sh            # Destroy infrastructure
├── QUICKSTART.md             # Fast-track deployment guide
└── README.md                 # This file
```

## 🚀 Quick Start

### Option 1: Automated (Recommended)

```bash
# 1. Clone the repository
git clone git@github.com:mcfuhrt/argocd-configuration.git
cd argocd-configuration

# 2. Run the initialization script
cd scripts
./initialize.sh

# 3. Follow the prompts
```

### Option 2: Manual

See the [Quick Start Guide](QUICKSTART.md) or [Detailed Documentation](terraform/README.md)

## 📋 Prerequisites

- **GCP Access**: Project `sikwel-playground` with appropriate permissions
- **Tools**: gcloud CLI, Terraform >= 1.5.0, kubectl
- **GitHub**: SSH key and Personal Access Token (PAT)

## 🎯 What Gets Deployed

### Infrastructure (Terraform)
- ✅ GKE cluster (cost-optimized with spot instances)
- ✅ VPC and networking
- ✅ GCS bucket for Recce data
- ✅ Workload Identity (secure bucket access)
- ✅ Static IP for ingress
- ✅ Service accounts and IAM bindings

### ArgoCD (Helm)
- ✅ ArgoCD server and UI
- ✅ Repository server
- ✅ Application controller
- ✅ ApplicationSet controller (for PR-based deployments)
- ✅ Managed ingress with SSL certificate

### Recce Application
- ✅ Helm chart deployment
- ✅ GCS Fuse sidecar for data sync
- ✅ Nginx reverse proxy
- ✅ Workload Identity integration

## 🔄 GitOps Workflow

1. **Infrastructure**: Managed by Terraform in this repository
2. **Application Config**: ArgoCD Applications watch RepoB for Helm charts
3. **Pull Requests**: ApplicationSet creates temporary environments for each PR in RepoC
4. **Sync**: ArgoCD automatically syncs changes from Git to Kubernetes

## 📊 Cost Optimization

This setup is designed for minimal cost (~€50-80/month):

- **Spot Instances**: 70% cheaper than regular instances
- **Single Zone**: Reduces cross-zone traffic costs
- **Minimal Node Pool**: 1-3 nodes with e2-standard-2 machines
- **Standard Storage**: For GCS bucket

See [Cost Optimization Guide](terraform/README.md#cost-optimization) for more details.

## 🧪 Testing

Run the comprehensive test suite:

```bash
cd scripts
./test-deployment.sh
```

Tests include:
- ✅ Cluster connectivity
- ✅ ArgoCD installation
- ✅ Secrets configuration
- ✅ Workload Identity
- ✅ GCS bucket access
- ✅ DNS and SSL certificates
- ✅ Application deployments

## 📖 Documentation

- **[Quick Start Guide](QUICKSTART.md)**: Fast-track deployment (30 minutes)
- **[Detailed README](terraform/README.md)**: Comprehensive documentation
- **[Architecture Diagrams](terraform/README.md#architecture-overview)**: Visual guides
- **[Troubleshooting Guide](terraform/README.md#troubleshooting)**: Common issues

## 🔐 Security

### Secrets Management

This repository uses Kubernetes secrets for sensitive data:
- GitHub SSH key (for private repository access)
- GitHub token (for Pull Request generator)

**Important**: Never commit secrets to Git!

### Workload Identity

Applications access GCS buckets using Workload Identity (not service account keys):
- More secure than downloading keys
- Automatic credential rotation
- Fine-grained IAM permissions

## 🛠️ Management Commands

### Deploy Infrastructure
```bash
cd scripts
./initialize.sh
```

### Update GitHub Secrets
```bash
cd scripts
./update-github-secrets.sh
```

### Test Deployment
```bash
cd scripts
./test-deployment.sh
```

### Access ArgoCD
```bash
# Via port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### View Applications
```bash
kubectl get applications -n argocd
kubectl get pods -n recce
```

### Cleanup
```bash
cd scripts
./cleanup.sh
```

## 🔧 Configuration

### Terraform Variables

Key variables in `terraform/terraform.tfvars`:

```hcl
project_id         = "sikwel-playground"
region             = "europe-west3"
cluster_name       = "argocd-recce-poc"
machine_type       = "e2-standard-2"
use_spot_instances = true
argocd_domain      = "argocd.your-domain.com"
```

### ArgoCD Applications

Applications are defined in `applications/recce/`:
- **recce.applicationset.yaml**: Main application or ApplicationSet for PR-based deploys

Projects are defined in `projects/recce/`:
- **project.yaml**: ArgoCD project definition
- **recce-project-watcher.yaml**: Auto-applies applications from this repo

## 📦 Application Deployment

### Manual Deployment
```bash
kubectl apply -f projects/recce/project.yaml
kubectl apply -f projects/recce/recce-project-watcher.yaml
```

### Automatic Sync
The project watcher automatically deploys applications when you commit changes to the `applications/recce/` directory.

### Pull Request Deployments
Uncomment the ApplicationSet section in `recce.applicationset.yaml` to enable PR-based deployments.

## 🐛 Troubleshooting

### ArgoCD can't sync applications
- Check GitHub SSH key: `kubectl get secret github-ssh-key -n argocd`
- Verify repository connection in ArgoCD UI: Settings → Repositories

### Pods can't access GCS bucket
- Check Workload Identity: `kubectl get sa datahub-dbt -n recce -o yaml`
- View logs: `kubectl logs -n recce <pod> -c gcs-fuse-sidecar`

### SSL certificate not provisioning
- Verify DNS: `dig argocd.your-domain.com`
- Check certificate: `kubectl describe managedcertificate argocd-cert -n argocd`
- Wait 10-30 minutes for certificate provisioning

See [Detailed Troubleshooting](terraform/README.md#troubleshooting) for more solutions.

## 📚 Additional Resources

### Official Documentation
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Recce Documentation](https://docs.reccehq.com/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

### Guides
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [GCS Fuse CSI Driver](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver)
- [GitHub SSH Access](https://medium.com/@tiwarisan/argocd-how-to-access-private-github-repository-with-ssh-key-new-way-49cc4431971b)

## 🤝 Contributing

1. Create a feature branch
2. Make your changes
3. Test with `./scripts/test-deployment.sh`
4. Submit a pull request

## 📝 License

[Your License Here]

## 💬 Support

For issues or questions:
- Check [Troubleshooting Guide](terraform/README.md#troubleshooting)
- Review [Quick Start](QUICKSTART.md)
- Open an issue in this repository

---

**Made with ❤️ for GitOps and Infrastructure as Code**
