# Cluster settings
variable cluster_prefix {}
variable kubenow_image {}
variable ssh_key {}
variable external_network_uuid {}
variable dns_nameservers { default="8.8.8.8,8.8.4.4" }
variable floating_ip_pool {}
variable kubeadm_token {}
variable kube_repo_prefix { default="gcr.io/google_containers" }
variable kubernetes_version {}
variable swift_bucket { default="" }

variable create_new_internal_network { default = false }
variable reuse_internal_network_name {}
variable reuse_secgroup_name {}

# Master settings
variable master_count { default = 1 }
variable master_flavor {}
variable master_flavor_id { default = ""}

# Nodes settings
variable node_count {}
variable node_flavor {}
variable node_flavor_id { default = ""}

# Upload SSH key to OpenStack
module "keypair" {
  source = "./keypair"
  public_key = "${var.ssh_key}"
  name_prefix = "${var.cluster_prefix}"
}

# Network
module "network" {
  source = "./network"
  count = "${var.create_new_internal_network ? 1 : 0 }"
  external_net_uuid = "${var.external_network_uuid}"
  name_prefix = "${var.cluster_prefix}"
  dns_nameservers = "${var.dns_nameservers}"
}

module "master" {
  # Core settings
  source = "./node"
  count = "${var.master_count}"
  name_prefix = "${var.cluster_prefix}-master"
  flavor_name = "${var.master_flavor}"
  flavor_id = "${var.master_flavor_id}"
  image_name = "${var.kubenow_image}"
  # SSH settings
  keypair_name = "${module.keypair.keypair_name}"
  # Network settings
  network_name = "${var.create_new_internal_network ? module.network.network_name : var.reuse_internal_network_name}"
  secgroup_name = "${var.create_new_internal_network ? module.network.secgroup_name : var.reuse_secgroup_name}"

 # network_name = "${var.reuse_internal_network_name}"
 # secgroup_name = "${var.reuse_secgroup_name}"

  assign_floating_ip = "false"
  floating_ip_pool = "${var.floating_ip_pool}"
  # Disk settings
  extra_disk_size = "0"
  # Bootstrap settings
  bootstrap_file = "bootstrap/initialize_master.sh"
  kube_repo_prefix = "${var.kube_repo_prefix}"
  kubernetes_version = "${var.kubernetes_version}"
  kubeadm_token = "${var.kubeadm_token}"
  node_labels = [""]
  node_taints = [""]
  master_ip = ""
  swift_bucket = "${var.swift_bucket}"
}

module "node" {
  # Core settings
  source = "./node"
  count = "${var.node_count}"
  name_prefix = "${var.cluster_prefix}-node"
  flavor_name = "${var.node_flavor}"
  flavor_id = "${var.node_flavor_id}"
  image_name = "${var.kubenow_image}"
  # SSH settings
  keypair_name = "${module.keypair.keypair_name}"
  # Network settings
  network_name = "${var.create_new_internal_network ? module.network.network_name : var.reuse_internal_network_name}"
  secgroup_name = "${var.create_new_internal_network ? module.network.secgroup_name : var.reuse_secgroup_name}"

 # network_name = "${var.reuse_internal_network_name}"
 # secgroup_name = "${var.reuse_secgroup_name}"

  assign_floating_ip = "false"
  floating_ip_pool = ""
  # Disk settings
  extra_disk_size = "0"
  # Bootstrap settings
  bootstrap_file = "bootstrap/initialize_node.sh"
  kubeadm_token = "${var.kubeadm_token}"
  node_labels = ["role=node"]
  node_taints = [""]
  master_ip = "${element(module.master.local_ip_v4, 0)}"
  swift_bucket = "${var.swift_bucket}"
}

# Generate Ansible inventory (identical for each cloud provider)
resource "null_resource" "generate-inventory" {

  # Changes to any node IP trigger inventory rewrite
  triggers {
    master_ips = "${join(",", module.master.local_ip_v4)}"
    node_ips = "${join(",", module.node.local_ip_v4)}"
  }

  # Write master
  provisioner "local-exec" {
    command =  "echo \"[master]\" > inventory"
  }
  # output the lists formated
  provisioner "local-exec" {
    # command =  "echo \"${join("\n",formatlist("%s ansible_ssh_host=%s ansible_ssh_user=root", module.master.hostnames, module.master.public_ip))}\" >> inventory"
    command =  "echo \"${join("\n",formatlist("%s ansible_ssh_host=%s ansible_ssh_user=root", module.master.hostnames, module.master.local_ip_v4))}\" >> inventory"

  }

  # Write other variables
  provisioner "local-exec" {
    command =  "echo \"[master:vars]\" >> inventory"
  }
  provisioner "local-exec" {
    command =  "echo \"nodes_count=${1 + var.node_count} \" >> inventory"
  }

  # Write nodes
  provisioner "local-exec" {
    command =  "echo \"[node]\" >> inventory"
  }
  provisioner "local-exec" {
    command =  "echo \"${join("\n",formatlist("%s ansible_ssh_host=%s ansible_ssh_user=root", module.node.hostnames, module.node.local_ip_v4))} \" >> inventory"
  }

}
