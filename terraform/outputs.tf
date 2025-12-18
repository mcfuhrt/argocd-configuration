# Outputs for GKE + ArgoCD + Recce Terraform configuration

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.gke_cluster.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.gke_cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.gke_cluster.location
}

output "gcs_bucket_name" {
  description = "GCS bucket name for Recce data"
  value       = google_storage_bucket.recce_data.name
}

output "gcs_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.recce_data.url
}

output "recce_service_account_email" {
  description = "GCP service account email for Recce application"
  value       = google_service_account.recce_app.email
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "recce_namespace" {
  description = "Recce namespace"
  value       = kubernetes_namespace.recce.metadata[0].name
}

output "argocd_ingress_ip" {
  description = "Static IP address for ArgoCD ingress"
  value       = google_compute_global_address.ingress_ip.address
}

output "ingress_ip_name" {
  description = "Name of the static IP address resource"
  value       = google_compute_global_address.ingress_ip.name
}

output "argocd_domain" {
  description = "ArgoCD domain name"
  value       = var.argocd_domain
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke_cluster.name} --region ${var.region} --project ${var.project_id}"
}

output "argocd_url" {
  description = "ArgoCD URL (after DNS configuration)"
  value       = "https://${var.argocd_domain}"
}

output "dns_configuration_instructions" {
  description = "DNS configuration instructions"
  value       = <<-EOT
    Configure your DNS:
    Add an A record for ${var.argocd_domain} pointing to ${google_compute_global_address.ingress_ip.address}
    
    Example (Google Cloud DNS):
    gcloud dns record-sets transaction start --zone=YOUR_ZONE_NAME
    gcloud dns record-sets transaction add ${google_compute_global_address.ingress_ip.address} --name=${var.argocd_domain}. --ttl=300 --type=A --zone=YOUR_ZONE_NAME
    gcloud dns record-sets transaction execute --zone=YOUR_ZONE_NAME
  EOT
}

output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value       = <<-EOT
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                           DEPLOYMENT COMPLETE!                                ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
    
    📋 NEXT STEPS:
    
    1. Configure kubectl:
       gcloud container clusters get-credentials ${google_container_cluster.gke_cluster.name} --region ${var.region} --project ${var.project_id}
    
    2. Configure DNS for ArgoCD:
       Add A record: ${var.argocd_domain} -> ${google_compute_global_address.ingress_ip.address}
    
    3. Access ArgoCD UI:
       URL: https://${var.argocd_domain}
       Username: admin
       Password: (see output 'argocd_initial_admin_password')
       
       Or get password via: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    
    4. Port-forward ArgoCD (if DNS not configured):
       kubectl port-forward svc/argocd-server -n argocd 8080:443
       Access at: https://localhost:8080
    
    5. Apply ArgoCD configuration from repository:
       kubectl apply -f ../projects/recce/project.yaml
       kubectl apply -f ../projects/recce/recce-project-watcher.yaml
       kubectl apply -f ../applications/recce/recce.applicationset.yaml
    
    6. Update your Helm values with GCS bucket:
       Bucket name: ${google_storage_bucket.recce_data.name}
       Service account: ${kubernetes_service_account.recce.metadata[0].name}
    
    7. Monitor ArgoCD applications:
       kubectl get applications -n argocd
       kubectl get applicationsets -n argocd
    
    ╔═══════════════════════════════════════════════════════════════════════════════╗
    ║                      IMPORTANT: Update Secrets                                ║
    ╚═══════════════════════════════════════════════════════════════════════════════╝
    
    Before ArgoCD can sync applications, update the following secrets:
    
    1. GitHub SSH Key:
       Follow: https://medium.com/@tiwarisan/argocd-how-to-access-private-github-repository-with-ssh-key-new-way-49cc4431971b
       Then update: kubectl edit secret github-ssh-key -n argocd
    
    2. GitHub Token (for Pull Request generator):
       Create token at: https://github.com/settings/tokens
       Update: kubectl edit secret github-token -n argocd
  EOT
}
