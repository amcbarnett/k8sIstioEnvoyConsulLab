# add a default value that is at least 16 characters
variable "masterAuthPass" {
  type = "string"
  default ="my"
}

variable "masterAuthUser" {
  type = "string"
}

variable "serviceAccount" {
  type = "string"
}

variable "project" {
  type = "string"
}

variable "region" {
  type = "string"
}

variable "zone" {
  type = "string"
}

variable "cluster_name" {
  type = "string"
}

variable "node_count" {
  type = "string"
  default = "4"
}

provider "google" {
  # OSS, so use this
  #credentials = "${file("/some/path/to/your/auth.json")}"
  #credentials = "${var.serviceAccount}"
  # change this name to your project
  project = "${var.project}"
  region  = "${var.region}"
  zone    = "${var.zone}"
}

resource "google_container_cluster" "k8s" {
  name               = "${var.cluster_name}"
  zone               = "${var.zone}"
  # we need 4 of these for the demo
  initial_node_count =  "${var.node_count}"

  # this is going to be your project
  project = "${var.project}"

  master_auth {
    username = "${var.masterAuthUser}"
    password = "${var.masterAuthPass}"
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels {
      env = "sandbox"
    }

    tags = ["k8s", "se-training", "sandbox"]
  }
}

# The following outputs allow authentication and connectivity to the GKE Cluster.
output "client_certificate" {
  value = "${google_container_cluster.k8s.master_auth.0.client_certificate}"
}

output "client_key" {
  value = "${google_container_cluster.k8s.master_auth.0.client_key}"
}

output "cluster_ca_certificate" {
  value = "${google_container_cluster.k8s.master_auth.0.cluster_ca_certificate}"
}
