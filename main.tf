# [START vpc_shared_vpc_host_project_enable]
resource "google_compute_shared_vpc_host_project" "host" {
  project = var.project
}
# [END vpc_shared_vpc_host_project_enable]

# [START vpc_shared_vpc_service_project_attach]
resource "google_compute_shared_vpc_service_project" "service1" {
  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = var.service_project
}
# [END vpc_shared_vpc_service_project_attach]

# [START compute_shared_data_network]
resource "google_compute_network" "network" {
  name                    = "rj-oam"
  project                 = var.project
  auto_create_subnetworks = false
  mtu                     = 1460
}
# [END compute_shared_data_network]

# [START compute_shared_data_subnet]
resource "google_compute_subnetwork" "subnet" {
  name          = "rj-oam-mgmt"
  ip_cidr_range = "10.7.7.0/24"
  network       = google_compute_network.network.self_link
  region        = "asia-south1"
}
# [END compute_shared_data_subnet]

# ✅ Share only the rj-oam-mgmt subnet with the service project
resource "google_compute_subnetwork_iam_member" "share_subnet" {
  project    = var.project
  region     = "asia-south1"
  subnetwork = google_compute_subnetwork.subnet.name

  role   = "roles/compute.networkUser"
  member = "serviceAccount:service-${var.service_project_number}@compute-system.iam.gserviceaccount.com"
}

# [START compute_shared_internal_ip_create]
resource "google_compute_address" "internal" {
  project      = var.service_project
  region       = "asia-south1"
  name         = "int-ip"
  address_type = "INTERNAL"
  address      = "10.7.7.8"
  subnetwork   = google_compute_subnetwork.subnet.self_link
}
# [END compute_shared_internal_ip_create]

# [START compute_shared_instance_with_reserved_ip_create]
resource "google_compute_instance" "reserved_ip" {
  project      = var.service_project
  zone         = "asia-south1-a"
  name         = "reserved-ip-instance"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20250610"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    network_ip = google_compute_address.internal.address
  }
}
# [END compute_shared_instance_with_reserved_ip_create]

# [START compute_shared_instance_with_ephemeral_ip_create]
resource "google_compute_instance" "ephemeral_ip" {
  project      = var.service_project
  zone         = "asia-south1-a"
  name         = "my-vm"
  machine_type = "e2-medium"
  boot_disk {
    initialize_params {
      image = "projects/debian-cloud/global/images/debian-12-bookworm-v20250610"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
  }
}
# [END compute_shared_instance_with_ephemeral_ip_create]

# [START compute_shared_instance_template_create]
resource "google_compute_instance_template" "default" {
  project      = var.service_project
  name         = "appserver-template"
  description  = "This template is used to create app server instances."
  machine_type = "n1-standard-1"
  disk {
    source_image = "projects/debian-cloud/global/images/debian-12-bookworm-v20250610"
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
  }
  
  metadata = {
    startup-script = file("${path.module}/startup.sh")
  }

}
# [END compute_shared_instance_template_create]

resource "google_compute_region_health_check" "default" {
  project = var.service_project
  name    = "l4-ilb-hc"
  region  = "asia-south1"
  http_health_check {
    port = "80"
  }
}

resource "google_compute_region_backend_service" "default" {
  project               = var.service_project
  name                  = "l4-ilb-backend-subnet"
  region                = "asia-south1"
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  health_checks         = [google_compute_region_health_check.default.id]
}

# [START compute_shared_forwarding_rule_l4_ilb]
resource "google_compute_forwarding_rule" "default" {
  project               = var.service_project
  name                  = "l4-ilb-forwarding-rule"
  backend_service       = google_compute_region_backend_service.default.id
  region                = "asia-south1"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
  network               = google_compute_network.network.self_link
  subnetwork            = google_compute_subnetwork.subnet.self_link
}
# [END compute_shared_forwarding_rule_l4_ilb]
