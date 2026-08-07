terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.1"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# Storage Pool for Pair A
resource "libvirt_pool" "pool_a" {
  name = "pool_a"
  type = "dir"
  path = "/home/pool_a"
}

# Base OS image volume
resource "libvirt_volume" "os_base" {
  name   = "almalinux9-base.qcow2"
  pool   = libvirt_pool.pool_a.name
  source = var.os_image_path
  format = "qcow2"
}

# OS Volumes for each VM (cloned from base)
resource "libvirt_volume" "os_disk" {
  count          = var.vm_count
  name           = "${var.hostname_prefix}-${count.index + 1}-os.qcow2"
  pool           = libvirt_pool.pool_a.name
  base_volume_id = libvirt_volume.os_base.id
  format         = "qcow2"
}

# Data Disks for each VM (2 disks per VM, 2G each)
resource "libvirt_volume" "data_disk_1" {
  count  = var.vm_count
  name   = "${var.hostname_prefix}-${count.index + 1}-data1.qcow2"
  pool   = libvirt_pool.pool_a.name
  format = "qcow2"
  size   = 2147483648 # 2G
}

resource "libvirt_volume" "data_disk_2" {
  count  = var.vm_count
  name   = "${var.hostname_prefix}-${count.index + 1}-data2.qcow2"
  pool   = libvirt_pool.pool_a.name
  format = "qcow2"
  size   = 2147483648 # 2G
}

# Cloud-Init for each VM
resource "libvirt_cloudinit_disk" "commoninit" {
  count     = var.vm_count
  name      = "${var.hostname_prefix}-${count.index + 1}-commoninit.iso"
  pool      = libvirt_pool.pool_a.name
  user_data = templatefile("${path.module}/cloud_init.cfg", {
    hostname       = "${var.hostname_prefix}-${count.index + 1}"
    ssh_public_key = file(var.ssh_public_key)
  })
}

# VMs
resource "libvirt_domain" "pa_node" {
  count  = var.vm_count
  name   = "${var.hostname_prefix}-${count.index + 1}"
  memory = "1024" # Deviation: 1GB instead of 2GB
  vcpu   = 2

  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  # UEFI boot settings
  machine = "q35"
  firmware = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  nvram {
    file     = "/var/lib/libvirt/qemu/nvram/${var.hostname_prefix}-${count.index + 1}_VARS.fd"
    template = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  # OS Disk
  disk {
    volume_id = libvirt_volume.os_disk[count.index].id
  }

  # Data Disk 1
  disk {
    volume_id = libvirt_volume.data_disk_1[count.index].id
  }

  # Data Disk 2
  disk {
    volume_id = libvirt_volume.data_disk_2[count.index].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
