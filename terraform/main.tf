# Main Terraform configuration for GKE + ArgoCD + Recce setup
# This creates a minimal, cost-optimized GKE cluster for proof of concept

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Configure Kubernetes provider (will be initialized after cluster creation)
provider "kubernetes" {
  host                   = "https://${google_container_cluster.gke_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate)
}

# Configure Helm provider (will be initialized after cluster creation)
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.gke_cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate)
  }
}

# Get current GCP client config
data "google_client_config" "default" {}

# Enable required GCP APIs
resource "google_project_service" "gcp_services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ])
  
  project = var.project_id
  service = each.key
  
  disable_on_destroy = false
}

# Create VPC for GKE
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
  
  depends_on = [google_project_service.gcp_services]
}

# Create subnet for GKE
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Create cost-optimized GKE cluster (Standard mode with small nodes)
resource "google_container_cluster" "gke_cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
  
  # Using regional cluster with single zone for cost optimization
  node_locations = ["${var.region}-a"]
  
  # Remove default node pool immediately
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
  
  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # Workload Identity for secure GCP service account access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Enable GCS Fuse CSI driver for bucket mounting
  addons_config {
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }
  
  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
  
  # Release channel
  release_channel {
    channel = "REGULAR"
  }
  
  depends_on = [
    google_project_service.gcp_services,
    google_compute_subnetwork.subnet
  ]
}

# Create a cost-optimized node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.gke_cluster.name
  project    = var.project_id
  
  # Single zone for cost optimization
  node_locations = ["${var.region}-a"]
  
  # Minimal node count for PoC
  initial_node_count = 1
  
  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  
  node_config {
    # Use cost-effective e2-standard-2 machine type
    machine_type = var.machine_type
    disk_size_gb = 20
    disk_type    = "pd-standard"
    
    # Use spot instances for maximum cost savings (acceptable for PoC)
    spot = var.use_spot_instances
    
    # Service account with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    metadata = {
      disable-legacy-endpoints = "true"
    }
    
    labels = {
      environment = "poc"
      managed-by  = "terraform"
    }
    
    tags = ["gke-node", "${var.cluster_name}"]
  }
  
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "Service Account for GKE nodes"
  project      = var.project_id
  
  depends_on = [google_project_service.gcp_services]
}

# IAM binding for GKE nodes
resource "google_project_iam_member" "gke_nodes" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Create GCS bucket for Recce data
resource "google_storage_bucket" "recce_data" {
  name          = "${var.project_id}-recce-data"
  location      = var.region
  project       = var.project_id
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  # Cost optimization: Standard storage class
  storage_class = "STANDARD"
  
  # Lifecycle rule to clean up old data (optional for PoC)
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    environment = "poc"
    managed-by  = "terraform"
  }
  
  depends_on = [google_project_service.gcp_services]
}

# Service account for Recce application (for Workload Identity)
resource "google_service_account" "recce_app" {
  account_id   = "${var.cluster_name}-recce"
  display_name = "Service Account for Recce application"
  project      = var.project_id
  
  depends_on = [google_project_service.gcp_services]
}

# Grant bucket access to Recce service account
resource "google_storage_bucket_iam_member" "recce_bucket_access" {
  bucket = google_storage_bucket.recce_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.recce_app.email}"
}

# Kubernetes namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name       = "argocd"
      managed-by = "terraform"
    }
  }
  
  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes namespace for Recce
resource "kubernetes_namespace" "recce" {
  metadata {
    name = "recce"
    labels = {
      name       = "recce"
      managed-by = "terraform"
    }
  }
  
  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes service account for Recce (in cluster)
resource "kubernetes_service_account" "recce" {
  metadata {
    name      = "datahub-dbt"
    namespace = kubernetes_namespace.recce.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.recce_app.email
    }
  }
  
  depends_on = [kubernetes_namespace.recce]
}

# Workload Identity binding
resource "google_service_account_iam_member" "recce_workload_identity" {
  service_account_id = google_service_account.recce_app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace.recce.metadata[0].name}/${kubernetes_service_account.recce.metadata[0].name}]"
}

# Reserve static IP for Ingress
resource "google_compute_global_address" "ingress_ip" {
  name    = "${var.cluster_name}-ingress-ip"
  project = var.project_id
  
  depends_on = [google_project_service.gcp_services]
}

# ArgoCD will be installed via the initialize.sh script using kubectl
# This allows us to use the standard installation manifest
