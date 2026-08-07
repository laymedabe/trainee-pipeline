# Pair A: Architecture & Design Decisions

This document outlines the architectural decisions, deviations, and configurations made for the Pair A deployment pipeline.

---

## 1. Deviations & Reasoning
We deviated from the original project brief to accommodate hardware constraints on the physical host.

* **Deviation:** Allocated 1GB of RAM per virtual machine instead of the requested 2GB.
* **Reasoning:** The host laptop only had 3GB of available RAM. Provisioning 4GB total would exceed host capacity, trigger the OOM (Out of Memory) killer, and cause system instability.

---

## 2. Partition Layout
The VMs are provisioned with three disks on the `virtio` bus to separate the OS from application data:

1. **OS Disk (`vda`):** Cloned from the Packer golden image. Contains the LVM Volume Group (`vg_sys_a`) with the required partitions (including the extra `lv_opt` logical volume mounted on `/opt`).
2. **Data Disk 1 (`vdb` - 2GB):** Formatted dynamically as `xfs` during the Ansible run and mounted to `/mnt/data1`.
3. **Data Disk 2 (`vdc` - 2GB):** Formatted dynamically as `xfs` during the Ansible run and mounted to `/mnt/data2`.

---

## 3. Inventory Generation
Ansible inventory generation is completely dynamic, driven by Terraform outputs to ensure we never have stale IP addresses.

* **Mechanism:** We use Terraform's native `local_file` resource alongside the `templatefile` function in our `outputs.tf`. 
* **Process:** When Terraform creates the `libvirt_domain` resources, it automatically detects the IP addresses assigned by the KVM DHCP server. Terraform injects these IPs into our `inventory.tpl` template and writes the final output directly into `ansible/inventory/hosts.ini` during the apply phase.

---

## 4. Variable Precedence Table
To fulfill the requirement of demonstrating Ansible variable precedence, we track a single tailoring variable (`rhel9cis_warning_banner`) across three different precedence levels.

| Variable Name | Assigned Value | Where It Is Set | What It Overrides | Why It Wins |
| :--- | :--- | :--- | :--- | :--- |
| `rhel9cis_warning_banner` | `"AUTHORIZED ACCESS ONLY"` | **Level 1:** `group_vars/all/vars.yml` | Role Defaults (`defaults/main.yml`) | Inventory `group_vars` are loaded after the role's default variables, safely overriding them. |
| `rhel9cis_warning_banner` | `"PLAYBOOK LEVEL ACCESS BANNER"` | **Level 2:** `playbook.yml` (`vars:` block) | Group Vars (`group_vars/all/vars.yml`) | Play-level variables are more specific to the execution run and override inventory-level configurations. |
| `rhel9cis_warning_banner` | `"JENKINS EXTRA-VARS BANNER"` | **Level 3:** Jenkins Pipeline (`--extra-vars`) | Play Vars (`playbook.yml`) | Command-line extra variables (`-e` or `--extra-vars`) have the absolute highest precedence in Ansible and override all other variable definitions across the board. |

---

## 5. Tailoring Decisions & Exceptions
The following specific tailoring decisions were made to align with the Pair A assignment:

* **Use of RSyslog:** Enforced `rhel9cis_syslog: rsyslog` to override the default `journald` implementation.
* **SSHD Timeout Adjustments:** Configured `rhel9cis_sshd_clientaliveinterval: 300` and `rhel9cis_sshd_clientalivecountmax: 0` per assignment requirements.
* **PAM Faillock Disablement:** Completely disabled account lockouts on failed password attempts for both standard users and root by setting `rhel9cis_pam_faillock_deny: 0` and toggling off CIS rules `5.3.3.1.1`, `5.3.3.1.2`, and `5.3.3.1.3`.

---

## 6. Expected Goss Results
*(To be populated after the first full hardening pipeline run).*
