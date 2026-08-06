packer {
  required_plugins {
    qemu = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "almalinux9" {
  qemu_binary       = "/usr/libexec/qemu-kvm"
  iso_url           = "https://vault.almalinux.org/9.4/isos/x86_64/AlmaLinux-9.4-x86_64-minimal.iso"
  iso_checksum      = "sha256:20123bb9f8319143e792b906137236bdcb0d10b023c36626ca2d8e9f62144eb9"
  
  # Output to your dedicated Pair A storage pool
  output_directory  = "/home/pool_a/packer_output"
  vm_name           = "almalinux9-golden.qcow2"
  
  # Disk and formatting
  disk_size         = "20G"
  format            = "qcow2"
  
  # Memory and CPU for the build process
  memory            = 2048
  cpus              = 2
  
  # UEFI Boot configuration
  machine_type      = "q35"
  firmware          = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  
  # Serve the kickstart file
  http_directory    = "."
  
  # Interrupt the boot process to inject the kickstart URL
  boot_wait         = "10s"
  boot_command      = [
    "<up><wait><tab>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/kickstart.cfg<enter>"
  ]
  
  # How Packer knows the install is finished
  ssh_username      = "ansible"
  ssh_password      = "ansible"
  ssh_timeout       = "30m"
  shutdown_command  = "echo 'ansible' | sudo -S shutdown -P now"
}

build {
  sources = ["source.qemu.almalinux9"]
}
