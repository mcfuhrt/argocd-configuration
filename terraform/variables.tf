# Variables for GKE + ArgoCD + Recce Terraform configuration

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "sikwel-playground"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west3"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "argocd-recce-poc"
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "use_spot_instances" {
  description = "Use spot instances for cost savings (recommended for PoC)"
  type        = bool
  default     = true
}

variable "argocd_domain" {
  description = "Domain for ArgoCD ingress (e.g., argocd.example.com)"
  type        = string
  default     = "argocd.example.com"
}

variable "github_ssh_private_key" {
  description = "GitHub SSH private key for repository access (base64 encoded or plain text)"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_YOUR_SSH_KEY"
}

variable "github_token" {
  description = "GitHub Personal Access Token for Pull Request generator"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_YOUR_GITHUB_TOKEN"
}

variable "recce_image_repository" {
  description = "Container image repository for Recce"
  type        = string
  default     = "sikwel/recce"
}

variable "recce_image_tag" {
  description = "Container image tag for Recce"
  type        = string
  default     = "latest"
}
