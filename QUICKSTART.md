# Quick Start Guide

This is a fast-track guide to get your GKE + ArgoCD + Recce infrastructure up and running.

## Prerequisites Checklist

- [ ] Google Cloud SDK installed (`gcloud`)
- [ ] Terraform >= 1.5.0 installed
- [ ] kubectl installed
- [ ] Access to GCP project `sikwel-playground`
- [ ] GitHub account with admin access to `mcfuhrt` organization

## Deployment Steps (30 minutes)

### 1. Authenticate with GCP (2 minutes)

```bash
gcloud auth login
gcloud config set project sikwel-playground
gcloud auth application-default login
```

### 2. Configure Domain (1 minute)

Edit `terraform/terraform.tfvars.example` and set your domain:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Update the `argocd_domain` variable with your actual domain (e.g., `argocd.your-company.com`)

### 3. Deploy Infrastructure (15-20 minutes)

Run the automated initialization script:

```bash
cd scripts
./initialize.sh
```

Or manually:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**☕ Take a coffee break - this takes ~15 minutes**

### 4. Configure kubectl (1 minute)

```bash
gcloud container clusters get-credentials argocd-recce-poc \
  --region europe-west3 \
  --project sikwel-playground
```

### 5. Set Up GitHub Access (5 minutes)

Run the interactive script:

```bash
cd scripts
./update-github-secrets.sh
```

Or manually:

1. **Generate SSH key**:
   ```bash
   ssh-keygen -t ed25519 -C "argocd@gke" -f ~/.ssh/argocd_github
   ```

2. **Add public key to GitHub**: https://github.com/settings/keys
   ```bash
   cat ~/.ssh/argocd_github.pub
   ```

3. **Create GitHub PAT**: https://github.com/settings/tokens (with `repo` scope)

4. **Update secrets**:
   ```bash
   kubectl create secret generic github-ssh-key \
     --from-literal=type=git \
     --from-literal=url=git@github.com:mcfuhrt \
     --from-file=sshPrivateKey=~/.ssh/argocd_github \
     -n argocd --dry-run=client -o yaml | kubectl apply -f -
   
   kubectl label secret github-ssh-key \
     -n argocd argocd.argoproj.io/secret-type=repository --overwrite
   
   kubectl create secret generic github-token \
     --from-literal=token=YOUR_GITHUB_TOKEN \
     -n argocd --dry-run=client -o yaml | kubectl apply -f -
   ```

### 6. Configure DNS (2 minutes)

Get the static IP:
```bash
cd terraform
terraform output argocd_ingress_ip
```

Add an A record in your DNS provider:
```
argocd.your-domain.com  A  <IP_ADDRESS>
```

**Note**: SSL certificate provisioning takes 10-30 minutes after DNS propagation.

### 7. Access ArgoCD (1 minute)

Get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

**Option A**: Via domain (after DNS + cert are ready)
```bash
open https://argocd.your-domain.com
```

**Option B**: Via port-forward (immediate)
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
open https://localhost:8080
```

Login:
- Username: `admin`
- Password: (from command above)

### 8. Deploy Recce Application (2 minutes)

```bash
cd ..  # Back to argocd-configuration root

# Deploy the Recce project
kubectl apply -f projects/recce/project.yaml

# Deploy the project watcher (auto-deploys applications)
kubectl apply -f projects/recce/recce-project-watcher.yaml

# Wait for sync
watch kubectl get applications -n argocd
```

### 9. Verify Deployment (2 minutes)

Run the test suite:
```bash
cd scripts
./test-deployment.sh
```

Check Recce application:
```bash
kubectl get pods -n recce
kubectl logs -n recce -l app.kubernetes.io/name=recce
```

## Quick Commands

### Get ArgoCD password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Port-forward ArgoCD
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Check applications
```bash
kubectl get applications -n argocd
```

### Check Recce pods
```bash
kubectl get pods -n recce
kubectl logs -n recce <pod-name>
```

### Get GCS bucket name
```bash
cd terraform
terraform output gcs_bucket_name
```

### Test GCS bucket access
```bash
# Upload test file
echo "test" > test.txt
gcloud storage cp test.txt gs://$(cd terraform && terraform output -raw gcs_bucket_name)/

# Verify in pod
kubectl exec -n recce -it <recce-pod-name> -c recce -- ls -la /data
```

## Testing Pull Request Deployment

1. **Enable ApplicationSet** (if using PR-based deployments):
   ```bash
   # Edit and uncomment the ApplicationSet section
   vim applications/recce/recce.applicationset.yaml
   kubectl apply -f applications/recce/recce.applicationset.yaml
   ```

2. **Create a Pull Request** in `mcfuhrt/argo-applications`

3. **Watch for new application**:
   ```bash
   watch kubectl get applications -n argocd
   # Should see: recce-pr-<number>
   ```

4. **Check PR-specific namespace**:
   ```bash
   kubectl get namespaces | grep recce-pr
   kubectl get pods -n recce-pr-<number>
   ```

## Troubleshooting

### ArgoCD can't connect to GitHub
```bash
# Check SSH key
kubectl get secret github-ssh-key -n argocd -o yaml

# Test from repo-server
kubectl exec -n argocd -it deployment/argocd-repo-server -- \
  ssh -T git@github.com -o StrictHostKeyChecking=no
```

### Pods can't access GCS bucket
```bash
# Check Workload Identity
kubectl get serviceaccount datahub-dbt -n recce -o yaml | grep iam.gke.io

# Check logs
kubectl logs -n recce <pod-name> -c gcs-fuse-sidecar
```

### Certificate not provisioning
```bash
# Check certificate status
kubectl describe managedcertificate argocd-cert -n argocd

# Verify DNS
dig argocd.your-domain.com
```

## Cleanup

To destroy everything:
```bash
cd scripts
./cleanup.sh
```

Or manually:
```bash
cd terraform
terraform destroy
```

## Cost Optimization

Current setup (~€50-80/month):
- ✅ Spot instances (70% cheaper)
- ✅ Single zone
- ✅ Minimal node pool (1-3 nodes)
- ✅ e2-standard-2 machines

For even lower costs:
- Use e2-small machines (edit `terraform/variables.tf`)
- Stop cluster when not in use:
  ```bash
  # Stop (deletes nodes)
  gcloud container clusters resize argocd-recce-poc --num-nodes=0 --region=europe-west3
  
  # Start
  gcloud container clusters resize argocd-recce-poc --num-nodes=1 --region=europe-west3
  ```

## Next Steps

1. ✅ Infrastructure deployed
2. ✅ ArgoCD accessible
3. ✅ Recce application running
4. ⬜ Configure Recce with dbt project
5. ⬜ Set up PR-based deployments
6. ⬜ Integrate with CI/CD pipeline

## Support

- **ArgoCD**: https://argo-cd.readthedocs.io/
- **Recce**: https://docs.reccehq.com/
- **GKE**: https://cloud.google.com/kubernetes-engine/docs

For issues with this setup, check the main [README](README.md).
