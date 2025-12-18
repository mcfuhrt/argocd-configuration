# GKE + ArgoCD + Recce Infrastructure Setup

This repository contains Terraform configurations to set up a complete GitOps infrastructure on Google Cloud Platform (GCP) with:
- **GKE (Google Kubernetes Engine)** cluster with Workload Identity
- **ArgoCD** for GitOps continuous delivery
- **Recce** application with GCS Fuse for data synchronization
- **ApplicationSet** support for PR-based deployments

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         GCP Project                             │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    GKE Cluster                             │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │  │
│  │  │   ArgoCD     │  │    Recce     │  │  Recce PR-123   │  │  │
│  │  │  Namespace   │  │  Namespace   │  │   Namespace     │  │  │
│  │  │              │  │              │  │                 │  │  │
│  │  │  - Server    │  │  - Recce Pod │  │  - Recce Pod    │  │  │
│  │  │  - RepoSvr   │  │  - NGINX     │  │  - NGINX        │  │  │
│  │  │  - AppSet    │  │  - GCS Fuse  │  │  - GCS Fuse     │  │  │
│  │  └──────────────┘  └──────────────┘  └─────────────────┘  │  │
│  │          │                │                     │          │  │
│  └──────────┼────────────────┼─────────────────────┼──────────┘  │
│             │                │                     │             │
│             ▼                ▼                     ▼             │
│  ┌─────────────────┐  ┌──────────────────────────────────────┐  │
│  │  GitHub Repos   │  │      GCS Bucket (Recce Data)         │  │
│  │  - RepoA (cfg)  │  │  ┌────────┐  ┌────────┐  ┌────────┐  │  │
│  │  - RepoB (app)  │  │  │ Models │  │  Data  │  │ Checks │  │  │
│  │  - RepoC (PRs)  │  │  └────────┘  └────────┘  └────────┘  │  │
│  └─────────────────┘  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Repository Structure

- **RepoA** (`argocd-configuration`): ArgoCD configuration, projects, and ApplicationSets
- **RepoB** (`argo-applications/recce`): Helm chart for Recce application
- **RepoC** (`argo-applications`): Application code that triggers PR-based deployments

## Prerequisites

### Required Tools
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) (gcloud CLI)
- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [Helm](https://helm.sh/docs/intro/install/) >= 3.13 (optional, for manual operations)

### GCP Setup
1. **GCP Project**: Ensure you have access to the `sikwel-playground` project
2. **Authentication**: 
   ```bash
   gcloud auth login
   gcloud config set project sikwel-playground
   gcloud auth application-default login
   ```
3. **Required Permissions**: You need the following roles:
   - `roles/compute.admin`
   - `roles/container.admin`
   - `roles/storage.admin`
   - `roles/iam.serviceAccountAdmin`
   - `roles/iam.serviceAccountUser`
   - `roles/resourcemanager.projectIamAdmin`

### GitHub Setup
1. **SSH Key**: Generate an SSH key for GitHub access:
   ```bash
   ssh-keygen -t ed25519 -C "argocd@gke-cluster" -f ~/.ssh/argocd_github
   ```
   Add the public key to your GitHub account: https://github.com/settings/keys

2. **Personal Access Token**: Create a GitHub PAT with `repo` scope:
   - Go to: https://github.com/settings/tokens
   - Click "Generate new token (classic)"
   - Select scopes: `repo` (full control)
   - Copy the token

### DNS Setup (Route53)

If you have a domain registered in AWS Route53, you can create a subdomain for ArgoCD:

1. **Choose a subdomain**: For example, `argocd.yourdomain.com`

2. **Option A: Using AWS CLI** (recommended):
   ```bash
   # First, deploy the infrastructure to get the static IP
   cd terraform
   terraform apply
   
   # Get the static IP address
   ARGOCD_IP=$(terraform output -raw argocd_ingress_ip)
   echo "ArgoCD IP: $ARGOCD_IP"
   
   # Replace with your actual domain
   DOMAIN="yourdomain.com"
   SUBDOMAIN="argocd.$DOMAIN"
   
   # Get your Route53 hosted zone ID
   HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
     --query "HostedZones[?Name=='$DOMAIN.'].Id" \
     --output text | cut -d'/' -f3)
   
   # Create the A record
   aws route53 change-resource-record-sets \
     --hosted-zone-id $HOSTED_ZONE_ID \
     --change-batch '{
       "Changes": [{
         "Action": "UPSERT",
         "ResourceRecordSet": {
           "Name": "'$SUBDOMAIN'",
           "Type": "A",
           "TTL": 300,
           "ResourceRecords": [{"Value": "'$ARGOCD_IP'"}]
         }
       }]
     }'
   
   # Verify DNS propagation
   dig $SUBDOMAIN
   ```

3. **Option B: Using AWS Console**:
   - Log in to AWS Console
   - Navigate to Route53 → Hosted zones
   - Select your domain
   - Click "Create record"
   - Record name: `argocd`
   - Record type: `A`
   - Value: `<Static IP from terraform output>`
   - TTL: `300`
   - Click "Create records"

4. **Verify DNS propagation**:
   ```bash
   # Wait a few minutes, then check
   dig argocd.yourdomain.com
   nslookup argocd.yourdomain.com
   ```

5. **Update terraform.tfvars before deployment**:
   ```hcl
   argocd_domain = "argocd.yourdomain.com"
   ```

**Important**: 
- DNS changes can take 5-15 minutes to propagate
- Google's managed certificate provisioning requires DNS to be correctly configured
- The certificate will take an additional 10-30 minutes after DNS propagation

## Cost Optimization

This setup is optimized for minimal cost:
- **Spot instances**: ~70% cheaper than regular instances
- **Single-zone regional cluster**: Reduces cross-zone traffic
- **Minimal node pool**: 1-3 nodes with e2-standard-2 (2 vCPU, 8 GB RAM)
- **Standard storage**: For GCS bucket
- **No HA**: Single replicas for ArgoCD components

**Estimated Monthly Cost**: ~€50-80 for a running PoC cluster

## Deployment Guide

### Step 1: Configure Variables

1. Copy the example variables file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` and update:
   ```hcl
   argocd_domain = "argocd.your-domain.com"  # Your domain
   ```

### Step 2: Deploy Infrastructure

1. Initialize Terraform:
   ```bash
   cd terraform
   terraform init
   ```

2. Review the deployment plan:
   ```bash
   terraform plan
   ```

3. Deploy the infrastructure:
   ```bash
   terraform apply
   ```
   
   This will take approximately 10-15 minutes to create:
   - VPC and subnet
   - GKE cluster with node pool
   - GCS bucket for Recce data
   - Service accounts with Workload Identity
   - ArgoCD installation via Helm
   - Ingress and managed certificates

4. Save the outputs:
   ```bash
   terraform output -json > outputs.json
   ```

### Step 3: Configure kubectl

```bash
# Get cluster credentials
terraform output -raw kubectl_config_command | bash

# Verify connection
kubectl get nodes
kubectl get pods -n argocd
```

### Step 4: Update GitHub Secrets

#### Option A: Using the provided script
```bash
../scripts/update-github-secrets.sh
```

#### Option B: Manually

1. **Update SSH key secret**:
   ```bash
   # Get your SSH private key (base64 encoded)
   cat ~/.ssh/argocd_github | base64 -w 0
   
   # Update the secret
   kubectl create secret generic github-ssh-key \
     --from-literal=type=git \
     --from-literal=url=git@github.com:mcfuhrt \
     --from-file=sshPrivateKey=~/.ssh/argocd_github \
     -n argocd \
     --dry-run=client -o yaml | kubectl apply -f -
   
   # Add label for ArgoCD
   kubectl label secret github-ssh-key \
     -n argocd \
     argocd.argoproj.io/secret-type=repository
   ```

2. **Update GitHub token secret**:
   ```bash
   # Replace YOUR_GITHUB_TOKEN with actual token
   kubectl create secret generic github-token \
     --from-literal=token=YOUR_GITHUB_TOKEN \
     -n argocd \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

### Step 5: Configure DNS

Get the static IP address:
```bash
terraform output argocd_ingress_ip
```

#### If using Route53 (AWS):

```bash
# Get the static IP
ARGOCD_IP=$(terraform output -raw argocd_ingress_ip)

# Replace 'yourdomain.com' with your actual domain
DOMAIN="yourdomain.com"
SUBDOMAIN="argocd.$DOMAIN"

# Get hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --query "HostedZones[?Name=='$DOMAIN.'].Id" \
  --output text | cut -d'/' -f3)

# Create A record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'$SUBDOMAIN'",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$ARGOCD_IP'"}]
      }
    }]
  }'

# Verify DNS
dig $SUBDOMAIN
```

#### If using other DNS providers:

Create an A record:
```
argocd.your-domain.com  A  <IP_ADDRESS>
```

**Note**: SSL certificate provisioning takes 10-30 minutes after DNS propagation.

### Step 6: Access ArgoCD

#### Option A: Via Domain (after DNS configuration)
```bash
# Get initial admin password
terraform output argocd_initial_admin_password

# Or retrieve from Kubernetes
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Access ArgoCD UI
open https://argocd.your-domain.com
```

#### Option B: Via Port-Forward (immediate access)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access ArgoCD UI
open https://localhost:8080
```

Login credentials:
- **Username**: `admin`
- **Password**: (from command above)

### Step 7: Deploy ArgoCD Applications

```bash
# Apply Recce project
kubectl apply -f projects/recce/project.yaml

# Apply project watcher
kubectl apply -f projects/recce/recce-project-watcher.yaml

# The watcher will automatically deploy the Recce application
# from the applications/recce directory
```

### Step 8: Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check Recce pods
kubectl get pods -n recce

# Check GCS bucket access
kubectl logs -n recce -l app.kubernetes.io/name=recce -c recce
```

## Testing End-to-End

### Test 1: Manual Recce Deployment

1. Check the main Recce application:
   ```bash
   kubectl get application recce -n argocd
   argocd app get recce
   ```

2. Verify the Recce pod is running:
   ```bash
   kubectl get pods -n recce
   ```

3. Test GCS bucket access:
   ```bash
   kubectl exec -n recce -it <recce-pod-name> -c recce -- ls -la /data
   ```

### Test 2: Pull Request Deployment (ApplicationSet)

1. Uncomment the ApplicationSet in `applications/recce/recce.applicationset.yaml`

2. Apply the ApplicationSet:
   ```bash
   kubectl apply -f applications/recce/recce.applicationset.yaml
   ```

3. Create a Pull Request in RepoC (`mcfuhrt/argo-applications`)

4. ArgoCD should automatically create a new application:
   ```bash
   kubectl get applications -n argocd | grep recce-pr
   ```

5. Verify the PR-specific namespace:
   ```bash
   kubectl get namespaces | grep recce-pr
   kubectl get pods -n recce-pr-<NUMBER>
   ```

### Test 3: GCS Bucket Synchronization

1. Upload test data to the bucket:
   ```bash
   echo "test data" > test.txt
   gcloud storage cp test.txt gs://$(terraform output -raw gcs_bucket_name)/test.txt
   ```

2. Verify the data appears in the pod:
   ```bash
   kubectl exec -n recce -it <recce-pod-name> -c recce -- cat /data/test.txt
   ```

## Updating Recce Helm Chart Values

Update the `overrides/common.yaml` with the deployed bucket name:

```yaml
serviceAccountName: datahub-dbt

storage:
  bucketName: "sikwel-playground-recce-data"  # From terraform output

dataMount:
  type: pvc
  pvcName: "recce-pvc"
  pvName: "recce-pv"
  mountPath: /data

nginx:
  enabled: true
```

## Troubleshooting

### ArgoCD can't access GitHub repositories
```bash
# Check if SSH key is configured
kubectl get secret github-ssh-key -n argocd -o yaml

# Test SSH connection from repo-server
kubectl exec -n argocd -it deployment/argocd-repo-server -- \
  ssh -T git@github.com -o StrictHostKeyChecking=no
```

### Recce pod can't access GCS bucket
```bash
# Check Workload Identity annotation
kubectl get serviceaccount datahub-dbt -n recce -o yaml

# Check GCP service account permissions
gcloud projects get-iam-policy sikwel-playground \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$(terraform output -raw recce_service_account_email)"

# Check pod logs
kubectl logs -n recce <pod-name> -c gcs-fuse-sidecar
```

### Certificate not provisioning
```bash
# Check certificate status
kubectl describe managedcertificate argocd-cert -n argocd

# Check ingress status
kubectl describe ingress argocd-server-ingress -n argocd

# Verify DNS propagation
dig argocd.your-domain.com
```

### ApplicationSet not creating applications
```bash
# Check ApplicationSet status
kubectl get applicationset -n argocd
kubectl describe applicationset recce -n argocd

# Check GitHub token
kubectl get secret github-token -n argocd -o jsonpath='{.data.token}' | base64 -d

# Check ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will delete:
- GKE cluster and all workloads
- GCS bucket and all data (force_destroy = true)
- VPC and networking
- Service accounts and IAM bindings

## Security Considerations

### For Production Use

1. **Disable Spot Instances**: Set `use_spot_instances = false`
2. **Multi-zone Cluster**: Add more zones in node pool configuration
3. **Enable HA**: Increase replicas for ArgoCD components
4. **Private Cluster**: Use private GKE cluster with bastion host
5. **Network Policies**: Implement Kubernetes network policies
6. **RBAC**: Configure fine-grained ArgoCD RBAC policies
7. **Secret Management**: Use Google Secret Manager or HashiCorp Vault
8. **Backup**: Implement regular backups for ArgoCD and GCS data
9. **Monitoring**: Enable GCP monitoring and logging
10. **Auto-scaling**: Configure horizontal pod autoscaling

## Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
- [Recce Documentation](https://docs.reccehq.com/)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [GCS Fuse CSI Driver](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/cloud-storage-fuse-csi-driver)

## Support

For issues or questions:
- ArgoCD: [GitHub Issues](https://github.com/argoproj/argo-cd/issues)
- Recce: [Documentation](https://docs.reccehq.com/)
- Infrastructure: Create an issue in this repository
