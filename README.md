# Nomad CIFS/SMB CSI Infrastructure for Media

This repository contains Ansible playbooks for setting up a CIFS/SMB CSI (Container Storage Interface) plugin on HashiCorp Nomad and deploying media servers (Plex or Jellyfin).

## Overview

The setup deploys:
- **Consul** - Service discovery and health checking
- **Nomad** - Container orchestration with Podman driver
- **CIFS CSI Plugin** - Controller and node plugins for mounting SMB/CIFS network shares
- **CSI Volumes** - Pre-configured volumes for media and backup storage
- **Dynamic Host Volumes** - Nomad-managed local storage for application configuration (requires Nomad 1.10+)
- **Media Server** - Plex or Jellyfin via Nomad Pack

## Architecture

This setup uses a **controller-based deployment model**:

- **Controller** (macOS workstation at `localhost`) - Runs Ansible and Nomad CLI commands
- **Target** (Linux server at `192.168.0.10`) - Runs Consul, Nomad, and containers
  - Secondary NIC on `10.100.0.0/30` network for NAS connectivity
  - Mounts SMB/CIFS shares from NAS at `10.100.0.1`

The controller uses `NOMAD_ADDR` to submit jobs to the remote Nomad cluster.

## Prerequisites

Before using this repository, you must have a NAS (Network Attached Storage) configured with the following SMB/CIFS shares:

| Share | Purpose |
|-------|---------|
| `/media` | Media library storage (movies, TV shows, music) |
| `/backups` | Backup storage for application configurations |

Configure your NAS credentials and share paths in `ansible/group_vars/all.yml`.

## Quick Start

1. Configure your settings in `ansible/group_vars/all.yml`
2. Update `ansible/inventory.ini` with your hosts
3. Run the ansible playbook:
   ```bash
   cd ansible

   # Deploy with Plex (default)
   ansible-playbook -i inventory.ini site.yml

   # Deploy with Jellyfin
   ansible-playbook -i inventory.ini site.yml -e media_server=jellyfin
   ```

## Configuration

Edit `ansible/group_vars/all.yml` to configure your deployment:

### Fileserver Settings
```yaml
fileserver_ip: "10.100.0.1"
fileserver_media_share: "media"
fileserver_backup_share: "backups"
fileserver_username: "<YOUR-USERNAME>"
fileserver_password: "<YOUR-PASSWORD>"
```

### Media Server Selection
```yaml
# Choose one: "plex" or "jellyfin"
media_server: "plex"

# Pack options
media_server_gpu_transcoding: true
media_server_enable_backup: true
media_server_enable_update: true
```

### Nomad Settings
```yaml
nomad_addr: "http://192.168.0.10:4646"
nomad_data_dir: "/opt/nomad/data"
nomad_config_dir: "/etc/nomad.d"
nomad_plugin_dir: "/opt/nomad/plugins"
```

### CSI Plugin Settings
```yaml
csi_smb_image: "mcr.microsoft.com/k8s/csi/smb-csi:v1.19.1"
csi_plugin_id: "smb"
csi_driver_name: "smb.csi.k8s.io"
csi_log_level: 5
csi_controller_cpu: 512
csi_controller_memory: 512
csi_node_cpu: 512
csi_node_memory: 512
```

### Dynamic Host Volume Paths
```yaml
# Paths for dynamic host volumes (created by mkdir plugin)
plex_config_dir: "/opt/plex/config"
plex_transcode_dir: "/opt/plex/transcode"
jellyfin_config_dir: "/opt/jellyfin/config"
jellyfin_cache_dir: "/opt/jellyfin/cache"
```

## Runtime Overrides

Override configuration at runtime:

```bash
# Deploy Jellyfin instead of Plex
ansible-playbook -i inventory.ini site.yml -e media_server=jellyfin

# Deploy without GPU transcoding
ansible-playbook -i inventory.ini site.yml -e media_server_gpu_transcoding=false

# Deploy without backup jobs
ansible-playbook -i inventory.ini site.yml -e media_server_enable_backup=false

# Combine options
ansible-playbook -i inventory.ini site.yml -e media_server=jellyfin -e media_server_gpu_transcoding=false
```

## Directory Structure

```
ansible/
├── group_vars/
│   └── all.yml                  # All configuration variables
├── playbooks/
│   ├── configure-consul.yml
│   ├── configure-nomad.yml
│   ├── deploy-csi-plugins.yml   # Deploys CSI controller and node plugins
│   ├── deploy-csi-volumes.yml   # Registers CSI volumes
│   ├── deploy-media-server.yml  # Deploys media server via Nomad Pack
│   ├── disable-firewall.yml
│   ├── install-consul.yml
│   ├── install-nomad.yml
│   ├── install-podman-driver.yml
│   └── setup-users.yml
├── templates/
│   ├── backup-drive-volume.hcl.j2
│   ├── cifs-csi-plugin-controller.nomad.j2
│   ├── cifs-csi-plugin-node.nomad.j2
│   ├── client.hcl.j2             # Includes dynamic host volume definitions
│   ├── consul.hcl.j2
│   ├── media-drive-volume.hcl.j2
│   ├── podman.hcl.j2
│   └── server.hcl.j2
├── inventory.ini
└── site.yml
```

## Ansible Playbooks

| Playbook | Description |
|----------|-------------|
| `site.yml` | Main playbook - runs all playbooks in order |
| `disable-firewall.yml` | Disables firewalld (RHEL) or ufw (Debian) |
| `install-consul.yml` | Installs Consul from HashiCorp repository |
| `configure-consul.yml` | Deploys Consul server configuration |
| `install-nomad.yml` | Installs Nomad from HashiCorp repository (Linux) or Homebrew (macOS) |
| `configure-nomad.yml` | Deploys Nomad server and client configuration (includes dynamic host volumes) |
| `install-podman-driver.yml` | Installs Podman and nomad-driver-podman |
| `setup-users.yml` | Creates users and groups for media server ownership |
| `deploy-csi-plugins.yml` | Deploys CSI controller and node plugins |
| `deploy-csi-volumes.yml` | Registers CSI volumes for media and backups |
| `deploy-media-server.yml` | Deploys Plex or Jellyfin via Nomad Pack (auto-installs via Homebrew on macOS) |

## CSI Plugins

The playbooks deploy two CSI plugin jobs:

| Job | Type | Description |
|-----|------|-------------|
| `cifs-csi-plugin-controller` | service | Volume lifecycle management (create, delete) |
| `cifs-csi-plugin-node` | system | Mounts volumes on each Nomad client node |

## CSI Volumes

| Volume | Purpose |
|--------|---------|
| `media-drive` | Shared media library (movies, TV shows, music) |
| `backup-drive` | Backup storage for application configurations |

## Dynamic Host Volumes

These volumes are defined in the Nomad client configuration (`client.hcl.j2`) using Nomad's dynamic host volume feature (requires Nomad 1.10+). The `mkdir` plugin automatically creates directories with the correct ownership and permissions when the Nomad client starts.

| Volume | Path | Purpose |
|--------|------|---------|
| `plex-config` | `/opt/plex/config` | Plex configuration and database |
| `plex-transcode` | `/opt/plex/transcode` | Temporary transcoding files |
| `jellyfin-config` | `/opt/jellyfin/config` | Jellyfin configuration and database |
| `jellyfin-cache` | `/opt/jellyfin/cache` | Jellyfin cache storage |

Volumes are registered automatically when the Nomad client starts. See [Nomad Dynamic Host Volumes](https://developer.hashicorp.com/nomad/docs/stateful-workloads/dynamic-host-volumes) for more information.

## Media Server Features

Both Plex and Jellyfin are deployed with:

| Feature | Description | Variable |
|---------|-------------|----------|
| GPU Transcoding | Hardware-accelerated transcoding via `/dev/dri` | `media_server_gpu_transcoding` |
| Backup Job | Daily backup of configuration (2am) | `media_server_enable_backup` |
| Update Job | Daily version check (3am) | `media_server_enable_update` |

## Switching Media Servers

To switch from one media server to another:

1. Stop the current media server:
   ```bash
   nomad job stop plex   # or jellyfin
   ```

2. Deploy the new media server:
   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-media-server.yml -e media_server=jellyfin
   ```

## Manual Infrastructure Setup

If not using Ansible for infrastructure, see the templates in `ansible/templates/` for configuration examples.

After infrastructure is set up, you can still use the media server playbook:

```bash
ansible-playbook -i inventory.ini playbooks/deploy-media-server.yml
```

Or deploy manually with Nomad Pack:

```bash
nomad-pack registry add mediaserver github.com/brent-holden/nomad-mediaserver-packs
nomad-pack run plex --registry=mediaserver -var gpu_transcoding=true
```

## Software Dependencies

### Controller (macOS)

The playbooks automatically install CLI tools on the controller via Homebrew:

| Tool | Installed By | Purpose |
|------|--------------|---------|
| Nomad CLI | `install-nomad.yml` | Submit jobs to remote Nomad cluster |
| Nomad Pack | `deploy-media-server.yml` | Deploy media server packs |

Both are installed from `hashicorp/tap` (e.g., `hashicorp/tap/nomad`).

### Target Server (Linux)

| Prerequisite | Installed By | Notes |
|--------------|--------------|-------|
| Consul | `install-consul.yml` | |
| Nomad 1.10+ | `install-nomad.yml` | Required for dynamic host volumes |
| Podman | `install-podman-driver.yml` | |

## Notes

- All configuration is managed through `ansible/group_vars/all.yml`
- Only one media server (Plex or Jellyfin) can be deployed at a time
- The SMB share is mounted with `user_uid` (1002) and `group_gid` (1001) for container access
- Backup volume uses `cache=none` and `nobrl` mount options for rsync compatibility
- GPU transcoding requires `/dev/dri` on the host
- CLI tools are installed locally; services run on the remote server
