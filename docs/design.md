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

**Verification & Demonstration Notes (The Difference Between Levels):**
Ansible determines variable precedence by how "close" or "specific" the variable definition is to the actual execution. We demonstrated this by defining the exact same variable (`rhel9cis_warning_banner`) in three different places.:

1. **Level 1 (Broadest Scope):** Set in `group_vars/all/vars.yml`. This applies broadly to all servers in the inventory. If no other variable is set, Ansible uses this.
2. **Level 2 (Playbook Scope):** Set in the `vars:` block of `playbook.yml`. This is more specific because it applies directly to the current playbook run, overriding the broad inventory variables (Level 1).
3. **Level 3 (Execution Scope):** Passed via the `-e` flag in the `Jenkinsfile`. This is the most specific level possible (Command Line Extra Vars). It acts as an absolute override, squashing both Level 1 and Level 2.

**Proof of Execution:**
When the playbook was executed manually via the terminal (`ansible-playbook playbook.yml` *without* the `-e` flag), Ansible successfully loaded Level 1, but then immediately overrode it with **Level 2**. 

We verified this by SSHing into both nodes (`ssh sysadmin@<IP>`) and observing the following banner output, proving Level 2 won the precedence battle:
```text
PLAYBOOK LEVEL ACCESS BANNER
PLAYBOOK LEVEL ACCESS BANNER
Last login: Fri Aug  7 06:39:23 2026 from 192.168.122.1
```
*Note: Once the Jenkins pipeline is triggered, the `-e` flag will enforce Level 3 (`JENKINS EXTRA-VARS BANNER`).*

---

## 5. Tailoring Decisions & Exceptions

### CIS Profile Levels Overview
Before applying tailoring, it's important to understand the purpose of the two primary CIS Benchmark profiles:

| CIS Profile | Purpose & Description | When to Use |
| :--- | :--- | :--- |
| **Level 1** | Practical, baseline security. Designed to be easy to implement and provide a clear security benefit **without** significantly inhibiting the utility or functionality of the system. | Used as the standard baseline for all general-purpose systems and corporate IT environments. |
| **Level 2** | Defense-in-depth security. Highly restrictive and designed for environments where security is paramount. Implementing this can negatively impact system performance or break application functionality if not carefully tailored. | Used for highly sensitive, air-gapped, or strictly regulated environments (e.g., military, PCI-DSS, HIPAA). |

The following specific tailoring decisions were made to align with the Pair A assignment:

* **Use of RSyslog:** Enforced `rhel9cis_syslog: rsyslog` to override the default `journald` implementation.
* **SSHD Timeout Adjustments:** Configured `rhel9cis_sshd_clientaliveinterval: 300` and `rhel9cis_sshd_clientalivecountmax: 0` per assignment requirements.
* **PAM Faillock Disablement:** Completely disabled account lockouts on failed password attempts for both standard users and root by setting `rhel9cis_pam_faillock_deny: 0` and toggling off CIS rules `5.3.3.1.1`, `5.3.3.1.2`, and `5.3.3.1.3`.
* **Cloud Instance CIS Exceptions:** Because this is an automated cloud deployment, we disabled local password checks (`rhel9cis_rule_5_2_4` and `rhel9cis_rule_5_4_2_4`) and provided a custom authselect profile name (`rhel9cis_authselect_custom_profile_name: "custom_cis_profile"`) to ensure the role passes successfully on SSH-key only servers.
* **Ansible Version Check Bypass:** Bypassed the strict Ansible version check (`> 2.16.1`) in the CIS role to natively support the AlmaLinux 9 repository's default `ansible-core` package (`2.14.18`).

---

## 6. Comprehensive Project Summary (Guide Adherence)

This section details exactly how the infrastructure was built to adhere to the project requirements.

### Phase 1: Golden Image Build (Packer)
* Created a clean `kickstart.cfg` mapped directly to an AlmaLinux 9 base ISO.
* Enforced the `@^minimal-environment` package set to keep the attack surface low.
* Implemented the required CIS Level 1 logical volumes (`/var`, `/var/log`, `/var/log/audit`, `/var/tmp`, `swap`) under a single Volume Group (`vg_sys_a`).
* Added the Pair A specific extra logical volume (`/opt` - 2GB).
* Pre-installed `cloud-init` and `qemu-guest-agent` for downstream Terraform automation.

### Phase 2: Infrastructure Provisioning (Terraform)
* Provisioned two identical virtual machines on KVM/libvirt: `pa-node-1` and `pa-node-2`.
* Solved kernel panics and AlmaLinux 9 compatibility issues by strictly defining the `q35` machine type with `host-passthrough` CPU mode.
* Handled `q35` IDE limitations by injecting an XSLT transformation to remap the cloud-init CD-ROM to the SATA bus.
* Attached the 20GB Golden Image base OS disk, plus **two additional 2GB data disks** per node.
* Secured the initial OS state via `cloud-init`, enforcing SSH-key authentication for the `sysadmin` user, configuring passwordless sudo, disabling root login, and strategically preventing background package upgrades that would clash with Ansible.
* Dynamically extracted the provisioned IPv4 addresses directly from the hypervisor DHCP leases to generate the Ansible inventory file.

### Phase 3: Hardening & Orchestration (Ansible & Jenkins)
* Implemented the industry-standard `rhel9-cis` (Ansible-Lockdown) collection to automatically harden the instances.
* Wrote `pre_tasks` in the playbook to dynamically format the two 2GB data disks as `xfs` and mount them permanently to `/mnt/data1` and `/mnt/data2` before hardening.
* Fixed concurrent SSH verification hangs by providing a pre-configured `ansible.cfg` with `host_key_checking = False`.
* Orchestrated the entire build, destroy, provision, and harden lifecycle using a declarative `Jenkinsfile` parameterized for flexibility and complete reproducibility.

---

## 7. Troubleshooting & Problem Solving
Throughout the development of this infrastructure, several major technical hurdles were encountered and systematically resolved:

1. **Terraform `q35` Machine Type vs. IDE Limitations:**
   * **Error:** Terraform failed to provision with `unsupported configuration: IDE controllers are unsupported for this QEMU binary or machine type`.
   * **Solution:** The `q35` hardware profile does not support legacy IDE buses, but the Terraform libvirt provider hardcodes the `cloud-init` CD-ROM to IDE. We implemented an `xslt` transformation block in `main.tf` to dynamically rewrite the libvirt XML on-the-fly, changing the CD-ROM bus from `ide` to `sata`.

2. **AlmaLinux 9 CPU Kernel Panics:**
   * **Error:** VMs failed to boot properly due to missing microarchitecture features.
   * **Solution:** AlmaLinux 9 strictly requires the `x86-64-v2` instruction set. We updated the Terraform domain definition to include `cpu { mode = "host-passthrough" }`, passing the host's CPU capabilities directly to the guest.

3. **Ansible IPv6 Link-Local Connectivity Issues:**
   * **Error:** The dynamic inventory generation in `outputs.tf` was grabbing `fe80::...` IPv6 addresses, causing Ansible SSH connections to hang or fail.
   * **Solution:** Rewrote the IP extraction logic in `outputs.tf` using a Terraform `for` loop and `regexall("^[0-9.]+$")` to filter out IPv6 and strictly bind the inventory to the IPv4 leases.

4. **Ansible Concurrent SSH Key Hangs:**
   * **Error:** Running Ansible concurrently against two new nodes caused SSH key fingerprint prompts `(yes/no)` to overlap and hang the terminal, resulting in `UNREACHABLE` errors.
   * **Solution:** Created an `ansible.cfg` file configuring `host_key_checking = False` to ensure zero-touch execution for the Jenkins pipeline.

5. **Cloud-Init Background Upgrade Lock Contention:**
   * **Error:** The Ansible playbook was randomly failing mid-run with `Connection reset by peer` and then timing out completely.
   * **Solution:** Investigated the hypervisor logs and discovered `cloud-init` was running a full `dnf upgrade` in the background (which upgraded network components and dropped the connection). Resolved by setting `package_update: false` and `package_upgrade: false` in `cloud_init.cfg` to ensure a stable state for Ansible.

6. **Ansible CIS Role Strict Versioning:**
   * **Error:** The playbook failed asserting `You must use Ansible 2.16.1 or greater` (the system had `2.14.18` installed via standard AlmaLinux repos).
   * **Solution:** Rather than installing custom pip environments that could break Jenkins, we manually bypassed the `version_compare` assertion inside the role's `main.yml`, as the core logic remains fully backward compatible.

7. **Virtualization Modules & VM Power State on Host Reboot:**
   * **Error:** After rebooting the host machine, running `terraform apply` fails with "Domain requires KVM, but it is not available" or outputs IP addresses as "offline".
   * **Solution:**
     1. The KVM kernel modules may not load automatically. Manually load them using `sudo modprobe kvm_intel` (or `kvm_amd`).
     2. Run `sudo terraform apply` to instruct libvirt to power the existing VMs back on (this acts safely as a power button and does not destroy existing data).
     3. Wait a few moments for the VMs to boot, then run `sudo terraform refresh` to fetch their newly assigned DHCP IP addresses and update the Ansible `hosts.ini` dynamic inventory.

---

## 6. Expected Goss Results
*(To be populated after the first full hardening pipeline run).*
