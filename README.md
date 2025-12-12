# Nomad Media Server with CIFS/SMB CSI Plugin

This repository contains HashiCorp Nomad job specifications for running Plex and Jellyfin media servers with shared media storage via a CIFS/SMB CSI (Container Storage Interface) plugin.

## Overview

The setup uses the SMB CSI driver to mount a network file share containing media files, which is then made available to both Plex and Jellyfin containers. All jobs use Podman as the container runtime.

## Directory Structure

```
├── ansible/                # Ansible playbooks for automated setup
│   ├── group_vars/
│   │   └── all.yml
│   ├── playbooks/
│   │   ├── configure-consul.yml
│   │   ├── configure-nomad.yml
│   │   ├── install-consul.yml
│   │   ├── install-nomad.yml
│   │   ├── install-podman-driver.yml
│   │   └── setup-directories.yml
│   ├── templates/
│   │   ├── client.hcl.j2
│   │   ├── consul.hcl.j2
│   │   ├── jellyfin-host-volumes.hcl.j2
│   │   ├── plex-host-volumes.hcl.j2
│   │   ├── podman.hcl.j2
│   │   └── server.hcl.j2
│   ├── inventory.ini
│   └── site.yml
├── configuration/          # Example Consul and Nomad configuration files
├── jobs/
│   ├── services/           # Media server job definitions
│   │   ├── jellyfin.nomad
│   │   └── plex.nomad
│   └── system/             # CSI plugin and volume definitions
│       ├── cifs-csi-plugin-controller.nomad
│       ├── cifs-csi-plugin-node.nomad
│       └── media-drive-volume.hcl
└── scripts/                # Utility scripts
    └── update-plex-version.sh
```

## Files

### System Jobs (`jobs/system/`)

**`cifs-csi-plugin-controller.nomad`**

Runs the SMB CSI plugin controller as a service job. The controller is responsible for volume lifecycle management (create, delete, etc.). Runs as a single instance using the Microsoft SMB CSI driver image (`mcr.microsoft.com/k8s/csi/smb-csi:v1.17.0`).

**`cifs-csi-plugin-node.nomad`**

Runs the SMB CSI plugin node service as a system job (runs on all Nomad clients). The node plugin handles mounting volumes on individual hosts. Runs in privileged mode with host networking to perform mount operations.

**`media-drive-volume.hcl`**

Defines the CSI volume that connects to the SMB/CIFS share. Configuration includes:
- Volume ID: `media-drive`
- Plugin: `smb`
- Access mode: `multi-node-multi-writer` (allows multiple nodes to mount simultaneously)
- Mount options for CIFS including SMB version 3.0
- Credentials for SMB authentication
- Source share path

### Service Jobs (`jobs/services/`)

**`plex.nomad`**

Runs the Plex Media Server with:
- Media library mounted from the CSI volume at `/media`
- Host volumes for config (`plex-config`) and transcoding (`plex-transcode`)
- GPU passthrough via `/dev/dri` for hardware transcoding
- Host networking on port 32400
- Plex claim token and version pulled from Nomad variables
- Consul service registration with health checks

**`jellyfin.nomad`**

Runs the Jellyfin Media Server with:
- Media library mounted from the CSI volume at `/media`
- Host volumes for config (`jellyfin-config`) and cache (`jellyfin-cache`)
- Host networking on ports 8096 (HTTP) and 7359 (discovery)
- Consul service registration with health checks

### Scripts (`scripts/`)

**`update-plex-version.sh`**

A bash script that:
1. Fetches the latest Plex version from the Plex API (PlexPass channel)
2. Updates the Nomad variable `nomad/jobs/plex` with the new version

## Automated Setup with Ansible

The `ansible/` directory contains playbooks to automate the complete setup on CentOS Stream 10 or Ubuntu 25.10.

### Playbooks

| Playbook | Description |
|----------|-------------|
| `install-consul.yml` | Installs Consul from HashiCorp's official repository |
| `configure-consul.yml` | Deploys Consul server configuration |
| `install-nomad.yml` | Installs Nomad from HashiCorp's official repository |
| `configure-nomad.yml` | Deploys Nomad server and client configuration files |
| `install-podman-driver.yml` | Installs Podman and the nomad-driver-podman plugin |
| `setup-directories.yml` | Creates host volume directories and deploys volume configuration |
| `site.yml` | Main playbook that runs all of the above in order |

### Usage

1. Edit the inventory file with your hosts:
   ```bash
   cd ansible
   vi inventory.ini
   ```

2. Configure variables in `group_vars/all.yml`:
   - Set `media_server` to `plex`, `jellyfin`, or `both`
   - Adjust versions and paths as needed

3. Run the complete setup:
   ```bash
   ansible-playbook -i inventory.ini site.yml
   ```

   Or run individual playbooks:
   ```bash
   ansible-playbook -i inventory.ini playbooks/install-nomad.yml
   ```

## Prerequisites

> **Tip:** Use the [Ansible playbooks](#automated-setup-with-ansible) to automate all of these prerequisites on CentOS Stream 10 or Ubuntu 25.10.

### Required Infrastructure
- Network access to the SMB/CIFS share

### Manual Setup

If not using Ansible, complete the following on each node:

1. **Install Consul** from [HashiCorp's repository](https://developer.hashicorp.com/consul/install)

2. **Configure and start Consul**:
   ```bash
   sudo cp configuration/consul.hcl /etc/consul.d/
   sudo mkdir -p /opt/consul/data
   sudo chown -R consul:consul /opt/consul
   sudo systemctl enable --now consul
   ```

3. **Install Nomad** from [HashiCorp's repository](https://developer.hashicorp.com/nomad/install)

4. **Install Podman** and enable the socket:
   ```bash
   sudo dnf install -y podman
   sudo systemctl enable --now podman.socket
   ```

5. **Install nomad-driver-podman** to the plugin directory:
   ```bash
   sudo mkdir -p /opt/nomad/plugins
   # Download from https://releases.hashicorp.com/nomad-driver-podman/
   sudo unzip nomad-driver-podman_*.zip -d /opt/nomad/plugins/
   ```

6. **Create host volume directories** (for Plex):
   ```bash
   sudo mkdir -p /opt/plex/config
   sudo mkdir -p /opt/plex/transcode
   ```
   Or for Jellyfin:
   ```bash
   sudo mkdir -p /opt/jellyfin/config
   sudo mkdir -p /opt/jellyfin/cache
   ```

7. **Configure Nomad** with the files from `configuration/`:
   - Copy `server.hcl` and `client.hcl` to `/etc/nomad.d/`
   - Copy `podman.hcl` to `/etc/nomad.d/`
   - Copy `plex-host-volumes.hcl` or `jellyfin-host-volumes.hcl` to `/etc/nomad.d/`

8. **Start Nomad**:
   ```bash
   sudo systemctl enable --now nomad
   ```

## Deployment Order

1. Deploy the CSI plugin controller:
   ```bash
   nomad job run jobs/system/cifs-csi-plugin-controller.nomad
   ```

2. Deploy the CSI plugin node service:
   ```bash
   nomad job run jobs/system/cifs-csi-plugin-node.nomad
   ```

3. Register the CSI volume:
   ```bash
   nomad volume create jobs/system/media-drive-volume.hcl
   ```

4. Set up Plex Nomad variables (if running Plex):
   ```bash
   nomad var put nomad/jobs/plex claim_token="<YOUR-CLAIM-TOKEN>" version="latest"
   ```
   See [Finding an authentication token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/) for how to obtain your claim token.

5. Deploy a media server (choose one):
   ```bash
   # For Plex:
   nomad job run jobs/services/plex.nomad

   # Or for Jellyfin:
   nomad job run jobs/services/jellyfin.nomad
   ```

## Notes

- Both media servers are configured with 16GB RAM and 16 CPU cores
- The SMB share is mounted with UID 1002 and GID 1001 to match the Plex user
- Timezone is set to America/New_York for both services
- **Performance Warning:** Running both Plex and Jellyfin simultaneously against the same CIFS/SMB mount point may cause performance issues due to concurrent file access, library scanning, and metadata operations competing for network I/O. It is recommended to run only one media server at a time.
