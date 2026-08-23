# Cisco Catalyst SD-WAN Infrastructure-as-Code Repository

This repository implements an enterprise-grade Infrastructure-as-Code (IaC) configuration for Cisco Catalyst SD-WAN (v20.15.6) using the **Cisco Network as Code (NaC)** framework and Terraform.

It automates the configuration of a dual-datacenter fabric (Location A & B) and 5 remote branches with high-availability dual-router topologies.

---

## 1. Network Topology & Hardware Models

The fabric is organized around a dual-router design at all locations:

* **Data Centers (DC A & B)**: High-performance aggregation using dual **Catalyst C8500-12X4QC** platforms.
* **Medium Branches (Sites 101 & 102)**: Cost-effective dual **Catalyst C8235-G2** secure routers.
* **Large Branches (Sites 103 & 104)**: High-density dual **Catalyst C8355-G2** secure routers.
* **Extra-Large Branch (Site 105)**: Enterprise-scale aggregation using dual **Catalyst C8475-G2** secure routers.

### LAN Routing & Segmentation
To segregate business systems, the overlay network defines three service VRFs (VPNs) across all branches and datacenters:
1. **Corp (VPN 10)**: Enterprise operations and corporate resources.
2. **Guest (VPN 20)**: Isolated guest internet access.
3. **IoT (VPN 30)**: Building management, cameras, and IoT devices.

Local routing interfaces redistribute traffic dynamically:
* **Datacenters**: Routers establish **eBGP** peerings with local Nexus core switches within each service VPN to scale data center route advertising.
* **Branches**: Routers run **OSPF** within each service VPN towards local border switches/Catalyst Center SD-Access fabrics.
* **Service Redundancy**: Dual routers run VRRP/HSRP on service LAN segments to provide local default gateway redundancy.

---

## 2. Directory Layout & Environments

To limit the blast radius of changes, the repository is split into isolated environments:

```text
IaC-Cisco-SD-WAN/
├── .github/workflows/             # GitHub Actions validation & deploy pipelines
├── environments/
│   ├── dev/                       # Sandbox environment (runs on Cisco CML)
│   │   ├── data/                  # Declarative NaC YAML models
│   │   │   ├── defaults.nac.yaml  # DNS, NTP, Org defaults
│   │   │   ├── feature_profiles/  # Profile templates (System, Transport, Service, Mgmt)
│   │   │   ├── configuration_groups/ # Device profile binding groups
│   │   │   ├── policies/          # Centralized control/AAR/DIA policies
│   │   │   └── sites/             # Node allocations (DC A/B, Sites 101-105)
│   │   ├── main.tf                # Roots NaC Terraform module
│   │   ├── providers.tf           # Provider auth & Terraform Cloud workspace mapping
│   │   ├── variables.tf           # Input definitions
│   │   ├── versions.tf            # Provider version locks
│   │   └── terraform.tfvars       # Environment overrides
│   ├── stage/                     # Staging environment (physical lab)
│   └── prod/                      # Production environment (physical dual-DC & branches)
```

---

## 3. Terraform State & Workspace Management

To isolate environments and control the blast radius, this repository implements **environment isolation with separate state files**:

* **State Isolation**: Each environment (`dev`, `stage`, `prod`) maintains its own independent state file. A change applied in the `dev` directory cannot modify or corrupt the `stage` or `prod` configurations.
* **Terraform Cloud/Enterprise Backend**: State files are hosted remotely in Terraform Cloud or your private **Terraform Enterprise (TFE)** instance (configured via the `hostname` parameter in `providers.tf`).
* **Workspace Mapping**:
  * `environments/dev/` -> TFE Workspace: `sdwan-netops-dev`
  * `environments/stage/` -> TFE Workspace: `sdwan-netops-stage`
  * `environments/prod/` -> TFE Workspace: `sdwan-netops-prod`
* **On-Premises Runner Execution**: Because the Catalyst SD-WAN Manager APIs are typically deployed on private subnets, execution is configured to run via a **self-hosted on-premises agent** associated with each workspace, rather than using standard public cloud runners.


---

## 4. Reserved VPN Mappings

Cisco Catalyst SD-WAN reserves specific VPN IDs for transport and management:
* **VPN 0 (Transport)**: Handles WAN links (MPLS and Business Internet). This VPN hosts the DTLS control tunnels to vBond, vManage, and vSmart.
* **VPN 512 (OOB Management)**: Reserved strictly for local Out-of-Band (OOB) switch access. Physical management ports are locked into this VRF, providing a backdoor console path that remains functional regardless of the overlay or WAN status.

---

## 5. Operational Playbooks (Day 2)

### Onboarding a New Site
To onboard a new branch (e.g. `site_106`):
1. Create a new site file `environments/<env>/data/sites/site_106.nac.yaml` specifying hostnames, serials, system IPs, and LAN routing parameters.
2. Push your changes to a Git branch and open a Pull Request.
3. Verify the `terraform plan` output generated in the PR comment.
4. Merge the PR. Terraform Cloud applies the changes to SD-WAN Manager.
5. Power on the new hardware on-site. It boots, contacts vBond, and automatically downloads its config via Plug-and-Play.

### Modifying Existing Configs
1. Modify the shared values in `defaults.nac.yaml` or feature profiles under `feature_profiles/`.
2. Commit and run the validation pipeline via a PR.
3. Merge the changes to trigger `terraform apply`. Terraform updates the feature profile in SD-WAN Manager, which pushes the configurations non-disruptively to all affected active routers.

### Decommissioning a Site
1. Delete the site's YAML file from the `data/sites/` folder.
2. Commit and merge the deletion. Terraform detaches the device templates and removes the device entries.
3. Access SD-WAN Manager GUI and set the decommissioned device's certificate status to `Deauthorized` to release its license.

---

## 6. Development & Testing using Cisco Modeling Labs (CML)

Since testing SD-WAN changes on production or staging hardware is difficult, the `dev/` environment is designed to target a virtualized instance in **Cisco Modeling Labs (CML)**.


1. **Import CML Topology**: Load the SD-WAN virtual sandbox containing Catalyst 8000V nodes, vManage, vSmart, and vBond.
2. **Configure local CI Runner**: Deploy your self-hosted GitHub Actions runner inside the virtualization network containing the CML vManage API.
3. **Execute Plans locally**: Run `terraform plan` and `terraform apply` targeting the CML controllers to validate changes before merging into `stage` or `prod` branches.

### Detailed Local Execution Runbook (Bypassing TFE)
If you want to run and test these configurations on a local machine using a sandbox CML instance (running on a different PC on your network):

1. **Verify Network Connectivity**:
   Ensure that the machine running your Terraform command can reach the CML server IP. The virtual vManage must be exposed using a CML **External Connector (Bridge mode)** so that it is routable on your physical local LAN. Verify with:
   ```bash
   ping <cml-vmanage-ip>
   curl -k https://<cml-vmanage-ip>:8443/dataservice/system/device
   ```

2. **Temporarily Disable TFE Integration**:
   Open [`providers.tf`](file:///environments/dev/providers.tf) and temporarily comment out the `cloud` block. This forces Terraform to store state locally on your machine rather than attempting to connect to a private TFE workspace:
   ```hcl
   terraform {
     # cloud {
     #   hostname     = "tfe.enterprise.local"
     #   organization = "Enterprise-NetOps"
     #   workspaces {
     #     name = "sdwan-netops-dev"
     #   }
     # }
   }
   ```

3. **Export CML Environment Variables**:
   In your shell terminal, load the credentials for the CML vManage instance:
   ```bash
   export SDWAN_URL="https://<cml-vmanage-ip>"
   export SDWAN_USERNAME="admin"
   export SDWAN_PASSWORD="<cml-vmanage-password>"
   ```

4. **Initialize and Plan**:
   Run the initialization and dry-run comparison to verify your configurations:
   ```bash
   cd environments/dev
   terraform init
   terraform plan -var-file=terraform.tfvars
   ```
   *Verify that the output displays the proposed additions without warnings.*

5. **Apply Configuration to CML**:
   Push the profiles and configuration groups to your sandbox vManage:
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```
   *Type `yes` when prompted. After completion, check the vManage GUI to verify the configuration templates are present.*

6. **Verify within the CML Sandbox**:
   To confirm that the virtual devices have successfully connected and are passing traffic in your CML environment:
   - **Check CML Topology Canvas**: Ensure all interfaces (representing MPLS/Internet link lines) are active (green).
   - **Verify Control Connections**: In vManage, go to **Monitor > Devices** (pointing to your CML vManage IP) and verify that the virtual Catalyst 8000V nodes show green control connections.
   - **Validate Router Console OMP routing**: In the CML interface, open the **Console** tab of a branch router (e.g. `br101-c8235-1`) and execute:
     ```ios
     show sdwan control connections
     show sdwan omp peers
     ```
     *Confirm that active control connections and OMP peer sessions are established with the virtual vSmart controllers.*
   - **Test Data Plane (VRF Ping Check)**: Test end-to-end user traffic routing across your virtual CML MPLS/Internet clouds. From the console of `br101-c8235-1` (Branch 1), ping the LAN gateway of your Data Center (DC A Router 1) inside the Corporate VRF (VPN 10):
     ```ios
     ping vrf 10 10.10.10.2
     ```
     *Confirm that the ping completes successfully. This verifies that IPsec tunnels are passing traffic over your virtualized WAN.*

---


## 7. Software & Hardware Compatibility Matrix

To ensure successful provisioning and configuration group parsing, verify that your software and hardware match the compatibility matrix below:

| Component | Target Version | Compatible Releases / Ranges | Notes |
| :--- | :--- | :--- | :--- |
| **SD-WAN Manager (vManage)** | `v20.15.6` | `20.15.x` | Mandatory for Configuration Groups & Feature Profiles. |
| **vSmart Controller** | `v20.15.6` | `20.15.x` | Matches SD-WAN Manager version. |
| **vBond Orchestrator** | `v20.15.6` | `20.15.x` | Matches SD-WAN Manager version. |
| **Catalyst Core Routers (C8500)** | **C8500-12X4QC** | IOS-XE SD-WAN `17.15.1a` or later | DC WAN Edge / Aggregation platform. |
| **Large Branch Routers (C8300)** | **C8355-G2** | IOS-XE SD-WAN `17.15.1a` or later | Branch WAN Edge platform. |
| **Medium Branch Routers (C8200)** | **C8235-G2** | IOS-XE SD-WAN `17.15.1a` or later | Branch WAN Edge platform. |
| **X-Large Branch Routers (C8400)** | **C8475-G2** | IOS-XE SD-WAN `17.15.1a` or later | Branch WAN Edge platform. |
| **Terraform Core CLI** | `1.5.0` | `1.5.0` to `1.8.x` | Used by CI runner to parse configurations. |
| **ciscoen/sdwan Provider** | `0.3.0` | `>= 0.3.0` | Terraform provider communicating with SD-WAN Manager. |
| **netascode/nac-sdwan Module**| `0.1.0` | `>= 0.1.0` | Base NaC module reading YAML files. |

---

## 8. First-Time Provisioning Guide (Day 1 Fabric Build)

This step-by-step runbook guides a network engineer through using this repository to build and provision the SD-WAN fabric from scratch for the first time.

### Step 1: Controller Pre-requisites (Day 0 - Manual)
Before running Terraform, ensure the following controller pre-requisites are met:
1. Deploys vManage, vSmart, and vBond controllers on ESXi/KVM/Cloud.
2. Bootstrap basic system parameters via CLI console on all controllers (system IP, site ID, vBond address, admin password).
3. Generate CSR certificates, sign them with your enterprise CA, and install the certificate chain on all three controllers. Control connections between controllers must show as `up`.
4. Log into Cisco Smart Account, generate the WAN Edge provisioning file (serial number list), and upload it to vManage under **Configuration > Devices**.

### Step 2: Configure Terraform Cloud & CI Secrets
1. Set up a Terraform Cloud (TFC) organization (e.g. `Enterprise-NetOps`).
2. Create the workspace `sdwan-netops-dev` and set execution mode to **Agent** (linking to your on-premises runner).
3. Inside the workspace, navigate to **Variables** and define the environment credentials:
   - `SDWAN_URL` = `https://<vmanage-ip-or-fqdn>`
   - `SDWAN_USERNAME` = `admin`
   - `SDWAN_PASSWORD` = `<secure-password>`
4. Retrieve the TFC API token (`TF_API_TOKEN`) and map it into your GitHub Actions Secrets.

### Step 3: Populate Declarative Intent (YAML)
Edit the YAML configuration files in the repository using the GitHub web interface:
1. Open [`defaults.nac.yaml`](file:///environments/dev/data/defaults.nac.yaml) and update your organization name, DNS servers, and NTP servers.
2. Review [`service.nac.yaml`](file:///environments/dev/data/feature_profiles/service.nac.yaml) to ensure the Corp (VPN 10), Guest (VPN 20), and IoT (VPN 30) configurations match your segment guidelines.
3. Open files under [`sites/`](file:///environments/dev/data/sites/) and edit details for your dual DC routers (`dc_a.nac.yaml`, `dc_b.nac.yaml`) and Branch 1-5 routers. Update the hostnames, system IPs, static WAN IPs, and LAN virtual gateway IPs to reflect your physical plan.

### Step 4: Run Initial Deployment
1. Propose your changes by committing them to a new branch and opening a Pull Request.
2. Verify the `terraform plan` summary posted in the PR comment.
3. Merge the Pull Request. The GitHub Actions runner executes `terraform apply`, pushing all feature profiles, configuration groups, and device variables to vManage.
4. Verify on vManage GUI under **Configuration > Configuration Groups** that the `DC_Cluster_Group` and branch groups are created.

### Step 5: Physical Device Activation & Onboarding
1. Rack the physical Catalyst 8000 routers at the sites.
2. Connect their WAN interfaces (e.g. `GigabitEthernet1` for MPLS or `GigabitEthernet2` for Internet).
3. Connect local border switches/core switches to LAN interfaces `GigabitEthernet3` (Corp), `GigabitEthernet4` (Guest), and `GigabitEthernet5` (IoT).
4. Power on the routers. They boot, pull DHCP or contact the Cisco Plug-and-Play portal (`devicehelper.cisco.com`), resolve the vBond IP, authenticate, and download their configuration groups from vManage.
5. In vManage, verify that all devices show as `In Sync` and OMP tunnels are established.

---

## 9. Day 2 Operations Guide (Continuous Management)

Once the fabric is built, follow these procedures to perform ongoing operations:

### Adding a New Site (e.g. Site 106)
1. Navigate to `environments/dev/data/sites/` on the GitHub website.
2. Click on an existing site file (e.g., `site_101.nac.yaml`) and copy the text.
3. Create a new file in the folder named `site_106.nac.yaml`.
4. Paste the text, update the variables (site ID, hostname, serials, system IPs, WAN/LAN interfaces), and select **"Create a new branch and start a pull request"**.
5. Once the pipeline plan completes and prints the diff comment, verify the details and click **Merge pull request** to push configurations.

### Modifying Shared Profile Settings (e.g. DNS or NTP Update)
1. Edit [`defaults.nac.yaml`](file:///environments/dev/data/defaults.nac.yaml) directly in your browser.
2. Change the DNS or NTP server IP address.
3. Propose changes in a new branch and submit.
4. Review the plan comment listing the routers that will receive the updated settings.
5. Merge the PR. Terraform updates the profile inside vManage, which pushes the update over the Netconf control plane to all active routers.

### Decommissioning a Site
1. Delete the site's YAML file (e.g., `site_101.nac.yaml`) from the `data/sites/` folder.
2. Commit the deletion and submit a Pull Request.
3. Merge the PR. Terraform detaches the configurations and deletes the device entries from vManage.
4. Log into vManage, navigate to the device certificate list, and change the device status to **Deauthorized** to release the serial license.

---

## 10. Verification Guide (Checking Configuration Delivery)

Once a change has been applied via the pipeline, use this guide to verify that the configurations are active in the fabric and operating correctly.

### A. Verifying via the SD-WAN Manager (vManage) GUI

1. **Verify Task Execution Logs**:
   - In vManage, click the **Task Console** icon in the top right header.
   - Verify that the last deployment task pushed by Terraform shows a status of `Success`. If a task failed, click on the task to inspect the exact Netconf validation error.

2. **Verify Device Synchronization State**:
   - Navigate to **Configuration > Devices**.
   - Search for your target hostname (e.g. `br101-c8235-1`).
   - Confirm that the **Config Status** shows as `In Sync` and the **Control Status** shows `Connected` (with green icons).

3. **Verify Configuration Group Associations**:
   - Navigate to **Configuration > Configuration Groups**.
   - Click on the group (e.g. `Branch_Medium_Group`).
   - Click **Devices** and verify that your router hostname is listed under the attached devices with a `Success` state.

---

### B. Verifying via the Router Command Line (CLI)

Log in to the router via SSH using the Out-of-Band (VPN 512) management IP or console connection, and execute the following verification commands:

1. **Check Basic Fabric Settings**:
   ```ios
   show sdwan system status
   ```
   *Verify that the Loopback System IP, Site ID, Org Name, and vBond IP match your YAML site variables, and that the device mode is configured as `controller-managed`.*

2. **Verify Control Connections**:
   ```ios
   show sdwan control connections
   ```
   *Verify that active DTLS/TLS control connections show as `up` to vManage and vSmart controllers over both `mpls` and `biz-internet` colors.*

3. **Verify OMP Routing Overlay**:
   ```ios
   show sdwan omp peers
   ```
   *Verify that active OMP peer sessions are established with the vSmart controllers.*

4. **Verify LAN VRRP Default Gateway Redundancy**:
   ```ios
   show vrrp brief
   ```
   *On Router 1, verify the state is `MASTER` for VPN interface groups (10, 20, 30). On Router 2, verify the state is `BACKUP`.*

5. **Verify Service VRF Routing Protocols (OSPF/BGP)**:
   - For Branch Routers (Checking OSPF state with local switches):
     ```ios
     show ip ospf neighbor
     show ip route vrf Corp
     ```
     *Confirm that OSPF neighbor adjacencies are established on interface GigabitEthernet3 and that local LAN prefixes are learned.*
   - For DC Routers (Checking BGP state with DC Core switches):
     ```ios
     show ip bgp vpnv4 unicast summary
     show ip route vrf Corp
     ```
     *Confirm that eBGP peer sessions are established with the DC Core switches and routes are being exchanged.*

---

## 11. Terraform Enterprise (TFE) & GitHub Enterprise (GHE) Integration

To deploy this repository within an enterprise environment, your private **Terraform Enterprise (TFE)** instance integrates with **GitHub Enterprise (GHE)** using one of two primary design patterns:

### Pattern A: VCS-Driven Integration (TFE Native Run Orchestration)
TFE connects directly to GitHub Enterprise via OAuth to automate runs without relying on GHE Actions execution.
1. **OAuth Connection**: In TFE, navigate to **User Settings > VCS Providers** and configure a connection to your GitHub Enterprise instance using a GitHub App or OAuth client.
2. **Workspace Association**: Link your TFE workspaces (`sdwan-netops-dev`, etc.) directly to this Git repository.
3. **Webhook Triggers**:
   - When a Pull Request is opened in GHE, GHE notifies TFE via webhooks. TFE automatically executes a speculative run (`terraform plan`) and returns the pass/fail commit status directly to the GHE PR interface.
   - When the PR is merged into `main`, TFE triggers a deploy run (`terraform apply`).
4. **Execution Location**: In this pattern, the TFE workspace execution mode is set to **Agent**, routing configuration commands through an **on-premises TFE agent pool** running in your local datacenter (which can access the private vManage APIs).

### Pattern B: CLI/API-Driven Integration (GHE Actions Orchestration)
In this pattern, **GitHub Enterprise Actions** manages the pipeline steps (using our [`sdwan-ci-cd.yml`](file:///.github/workflows/sdwan-ci-cd.yml) workflow), and calls TFE only for state management and execution.
1. **Self-Hosted GHE Runners**: Deploy self-hosted GHE Actions runners on-premises so they have direct routing access to the vManage API.
2. **Configure API Token**: Store a TFE Organization or User API token as a GHE Actions Secret (`TF_API_TOKEN`).
3. **Pipeline Workflow**:
   - The GHE runner executes the job steps, logging in via the HashiCorp `setup-terraform` Action.
   - Running `terraform plan` or `terraform apply` on the GHE runner streams logs to TFE.
   - Since the `cloud` block is active in `providers.tf`, TFE locks the state file and records the run history, while the actual API execution runs securely via your on-premises GHE runner.

---

## 12. CI/CD Pipeline Pause Status

> [!WARNING]
> The GitHub Actions CI/CD validation and deployment pipeline ([`sdwan-ci-cd.yml.disabled`](file:///.github/workflows/sdwan-ci-cd.yml.disabled)) is currently **temporarily paused** by suffixing the file with `.disabled`. This prevents automated workflow runs from triggering or failing while the on-premises self-hosted runner (`on-prem-netops`) is offline.

### How to Re-enable the Pipeline:
Once your on-premises GitHub runner is online and registered to target this repository, you can re-enable the pipeline by running:
```bash
git mv .github/workflows/sdwan-ci-cd.yml.disabled .github/workflows/sdwan-ci-cd.yml
git commit -m "Re-enable GitHub Actions CI/CD Pipeline"
git push origin main
```
