# Nomad Media Server Infrastructure

Ansible playbooks for deploying a complete media server infrastructure on HashiCorp Nomad with Plex or Jellyfin, plus the full *arr stack for media automation.

## Overview

This repository provides automated deployment of:

- **Consul** - Service discovery and health checking
- **Nomad** - Container orchestration with Podman driver
- **CIFS/SMB CSI Plugin** - Network storage for media libraries via SMB/CIFS shares
- **Dynamic Host Volumes** - Nomad-managed local storage using the `mkdir` plugin (Nomad 1.10+)
- **Media Server** - Plex or Jellyfin deployed via Nomad Pack
- **Media Automation** - Radarr, Sonarr, Lidarr, Prowlarr, Overseerr, Tautulli

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Controller (macOS)                          │
│  - Ansible playbooks                                            │
│  - Nomad CLI / Nomad Pack                                       │
│  - Submits jobs via NOMAD_ADDR                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Target Server (192.168.0.10)                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Consul    │  │    Nomad    │  │   Podman Containers     │  │
│  └─────────────┘  └─────────────┘  │  - Plex/Jellyfin        │  │
│                                     │  - Radarr/Sonarr/etc    │  │
│  ┌─────────────────────────────────┐│  - CSI Plugins          │  │
│  │  Secondary NIC (10.100.0.0/30)  │└─────────────────────────┘  │
│  │  └─► NAS at 10.100.0.1          │                             │
│  │      - /media (SMB share)       │                             │
│  │      - /backups (SMB share)     │                             │
│  └─────────────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### NAS Configuration

Configure your NAS with SMB/CIFS shares:

| Share | Purpose |
|-------|---------|
| `/media` | Media library (movies, TV shows, music, downloads) |
| `/backups` | Backup storage for application configurations |

### Software Requirements

| Component | Controller (macOS) | Target (Linux) |
|-----------|-------------------|----------------|
| Ansible | Required | - |
| Homebrew | Required | - |
| Nomad | Auto-installed | Auto-installed |
| Nomad Pack | Auto-installed | - |
| Consul | - | Auto-installed |
| Podman | - | Auto-installed |

## Quick Start

1. **Configure settings:**
   ```bash
   cd ansible
   cp group_vars/all.yml.example group_vars/all.yml
   # Edit group_vars/all.yml with your NAS credentials and settings
   ```

2. **Deploy everything:**
   ```bash
   ansible-playbook -i inventory.ini site.yml
   ```

3. **Deploy the *arr stack:**
   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-arr-stack.yml
   ```

4. **Access your services:**

   | Service | URL |
   |---------|-----|
   | Plex | http://192.168.0.10:32400 |
   | Jellyfin | http://192.168.0.10:8096 |
   | Radarr | http://192.168.0.10:7878 |
   | Sonarr | http://192.168.0.10:8989 |
   | Lidarr | http://192.168.0.10:8686 |
   | Prowlarr | http://192.168.0.10:9696 |
   | Overseerr | http://192.168.0.10:5055 |
   | Tautulli | http://192.168.0.10:8181 |
   | SABnzbd | http://192.168.0.10:8080 |

## Playbooks

| Playbook | Description |
|----------|-------------|
| `site.yml` | Main playbook - deploys complete infrastructure and media server |
| `deploy-media-server.yml` | Deploy/redeploy Plex or Jellyfin only |
| `deploy-arr-stack.yml` | Deploy *arr services (Radarr, Sonarr, etc.) |
| `restore-media-server.yml` | Restore media server configuration from backup |
| `deploy-csi-plugins.yml` | Deploy CSI controller and node plugins |
| `deploy-csi-volumes.yml` | Register CSI volumes |
| `setup-users.yml` | Create users/groups for media server |

### Deploying Media Servers

```bash
# Deploy Plex (default)
ansible-playbook -i inventory.ini site.yml

# Deploy Jellyfin
ansible-playbook -i inventory.ini site.yml -e media_server=jellyfin

# Deploy without GPU transcoding
ansible-playbook -i inventory.ini site.yml -e media_server_gpu_transcoding=false

# Deploy without backup jobs
ansible-playbook -i inventory.ini site.yml -e media_server_enable_backup=false

# Redeploy media server only (after initial setup)
ansible-playbook -i inventory.ini playbooks/deploy-media-server.yml
```

### Deploying the *arr Stack

The `deploy-arr-stack.yml` playbook deploys all media automation services:

```bash
# Deploy all *arr services
ansible-playbook -i inventory.ini playbooks/deploy-arr-stack.yml

# Deploy specific services only
ansible-playbook -i inventory.ini playbooks/deploy-arr-stack.yml \
  -e "arr_services=['radarr','sonarr','prowlarr']"

# Deploy without backup jobs
ansible-playbook -i inventory.ini playbooks/deploy-arr-stack.yml \
  -e arr_enable_backup=false
```

**Available services:** `radarr`, `sonarr`, `lidarr`, `prowlarr`, `overseerr`, `tautulli`

### Restoring from Backup

The restore playbook handles the complete restore workflow automatically:

```bash
# Restore from latest backup
ansible-playbook -i inventory.ini playbooks/restore-media-server.yml

# Restore from a specific date
ansible-playbook -i inventory.ini playbooks/restore-media-server.yml -e backup_date=2025-01-15
```

The restore playbook:
1. Stops the media server
2. Dispatches the restore job
3. Waits for restore to complete
4. Restarts the media server

**Note:** The `plex-restore` or `jellyfin-restore` job must be deployed first. Set `media_server_enable_restore=true` (enabled by default).

## Configuration

All settings are in `ansible/group_vars/all.yml`:

### Fileserver Settings

```yaml
fileserver_ip: "10.100.0.1"
fileserver_media_share: "media"
fileserver_backup_share: "backups"
fileserver_username: "<YOUR-USERNAME>"
fileserver_password: "<YOUR-PASSWORD>"
```

### Media Server Settings

```yaml
# Choose one: "plex" or "jellyfin"
media_server: "plex"

# Pack options (passed to nomad-pack)
media_server_gpu_transcoding: true    # Enable GPU transcoding
media_server_enable_backup: true      # Enable periodic backup job
media_server_enable_update: true      # Enable periodic update job
media_server_enable_restore: true     # Enable restore job (for manual dispatch)
```

### User/Group Settings

```yaml
# Used for volume permissions and container user mapping
user_uid: 1002
group_gid: 1001
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
# CSI plugin configuration
csi_smb_image: "registry.k8s.io/sig-storage/smbplugin:v1.19.1"  # Kubernetes SIG Storage SMB CSI driver
csi_plugin_id: "cifs"                                            # Plugin ID used in Nomad (volumes reference this)
csi_driver_name: "smb.csi.k8s.io"                                # Driver name (from upstream)
```

**Note:** The plugin ID is `cifs` for clarity, while the underlying driver uses the `smb.csi.k8s.io` implementation. Volumes reference the plugin by `csi_plugin_id` (i.e., `plugin_id = "cifs"`).

For standalone CSI plugin deployment without Ansible, see [nomad-csi-cifs](https://github.com/brent-holden/nomad-csi-cifs).

## Storage Architecture

### CSI Volumes (Network Storage)

CSI volumes provide access to network shares via the SMB/CIFS CSI plugin:

| Volume | Purpose | Mount Path |
|--------|---------|------------|
| `media-drive` | Media library and downloads | `/media` |
| `backup-drive` | Backup storage | `/backups` |

### Dynamic Host Volumes (Local Storage)

Dynamic host volumes are created automatically by Nomad using the `mkdir` plugin. The Nomad client is configured with:

```hcl
client {
  host_volumes_dir = "/opt/nomad/volumes"
}
```

When jobs request host volumes, Nomad creates them on-demand with the specified ownership and permissions.

| Volume | Purpose | Created By |
|--------|---------|------------|
| `plex-config` | Plex configuration and database | `deploy-media-server.yml` |
| `jellyfin-config` | Jellyfin configuration and database | `deploy-media-server.yml` |
| `radarr-config` | Radarr configuration and database | `deploy-arr-stack.yml` |
| `sonarr-config` | Sonarr configuration and database | `deploy-arr-stack.yml` |
| `lidarr-config` | Lidarr configuration and database | `deploy-arr-stack.yml` |
| `prowlarr-config` | Prowlarr configuration and database | `deploy-arr-stack.yml` |
| `overseerr-config` | Overseerr configuration and database | `deploy-arr-stack.yml` |
| `tautulli-config` | Tautulli configuration and database | `deploy-arr-stack.yml` |
| `sabnzbd-config` | SABnzbd configuration and database | `deploy-arr-stack.yml` |

**Access Mode:** Host volumes are created with `single-node-multi-writer` access mode, which allows the backup and restore jobs to access the config volume while the main service is running.

## Jobs Deployed

### Media Server Jobs

| Job | Type | Description |
|-----|------|-------------|
| `cifs-csi-plugin-controller` | service | CSI volume lifecycle management |
| `cifs-csi-plugin-node` | system | Mounts CSI volumes on nodes |
| `plex` or `jellyfin` | service | Media server |
| `plex-backup` or `jellyfin-backup` | batch/periodic | Daily backup at 2am |
| `plex-update` or `jellyfin-update` | batch/periodic | Daily version check at 3am |
| `plex-restore` or `jellyfin-restore` | batch/parameterized | Manual restore job |

### *arr Stack Jobs

Each *arr service creates multiple jobs:

| Service | Main Job | Backup Job | Update Job |
|---------|----------|------------|------------|
| Radarr | `radarr` | `radarr-backup` | `radarr-update` |
| Sonarr | `sonarr` | `sonarr-backup` | `sonarr-update` |
| Lidarr | `lidarr` | `lidarr-backup` | `lidarr-update` |
| Prowlarr | `prowlarr` | `prowlarr-backup` | `prowlarr-update` |
| Overseerr | `overseerr` | `overseerr-backup` | `overseerr-update` |
| Tautulli | `tautulli` | `tautulli-backup` | `tautulli-update` |
| SABnzbd | `sabnzbd` | `sabnzbd-backup` | `sabnzbd-update` |

## *arr Stack Setup

After deploying the *arr stack, configure the services to work together:

### Recommended Configuration Order

1. **SABnzbd** - Configure download client first
2. **Prowlarr** - Configure indexers
3. **Radarr/Sonarr/Lidarr** - Add Prowlarr as indexer source, SABnzbd as download client
4. **Overseerr** - Connect to Plex and Radarr/Sonarr
5. **Tautulli** - Connect to Plex

### Service Connections

| Service | Connects To | Configuration Path |
|---------|-------------|-------------------|
| Prowlarr | Radarr, Sonarr, Lidarr | Settings → Apps |
| Radarr | Prowlarr, Download Client | Settings → Indexers, Settings → Download Clients |
| Sonarr | Prowlarr, Download Client | Settings → Indexers, Settings → Download Clients |
| Lidarr | Prowlarr, Download Client | Settings → Indexers, Settings → Download Clients |
| Overseerr | Plex, Radarr, Sonarr | Settings → Plex, Settings → Radarr/Sonarr |
| Tautulli | Plex | Settings → Plex Media Server |

### Media Path Configuration

All *arr apps and SABnzbd mount the media volume at `/media`. Configure paths as:

| Service | Root Folder | Download Path |
|---------|-------------|---------------|
| SABnzbd | N/A | `/media/downloads` |
| Radarr | `/media/movies` | `/media/downloads/complete/movies` |
| Sonarr | `/media/tv` | `/media/downloads/complete/tv` |
| Lidarr | `/media/music` | `/media/downloads/complete/music` |

**SABnzbd Categories:** Configure categories in SABnzbd (Config → Categories) to sort downloads:
- `movies` → `/media/downloads/complete/movies`
- `tv` → `/media/downloads/complete/tv`
- `music` → `/media/downloads/complete/music`

### API Keys

Each *arr app generates an API key on first run. Find it at:
- **Settings → General → Security → API Key**

You'll need these API keys when connecting services (e.g., adding Radarr to Prowlarr or Overseerr).

## Directory Structure

```
ansible/
├── ansible.cfg                      # Ansible configuration
├── inventory.ini                    # Host inventory
├── site.yml                         # Main playbook
├── group_vars/
│   └── all.yml                      # All configuration variables
├── playbooks/
│   ├── configure-consul.yml
│   ├── configure-nomad.yml
│   ├── deploy-arr-stack.yml         # Deploy *arr services
│   ├── deploy-csi-plugins.yml
│   ├── deploy-csi-volumes.yml
│   ├── deploy-media-server.yml
│   ├── restore-media-server.yml     # Restore from backup
│   ├── disable-firewall.yml
│   ├── install-consul.yml
│   ├── install-nomad.yml
│   ├── install-podman-driver.yml
│   └── setup-users.yml
└── templates/
    ├── backup-drive-volume.hcl.j2
    ├── cifs-csi-plugin-controller.nomad.j2
    ├── cifs-csi-plugin-node.nomad.j2
    ├── client.hcl.j2
    ├── consul.hcl.j2
    ├── media-drive-volume.hcl.j2
    ├── podman.hcl.j2
    └── server.hcl.j2
```

## Manual Operations

### Switching Media Servers

```bash
# Stop current server
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack destroy plex --registry=mediaserver

# Deploy new server
ansible-playbook -i inventory.ini playbooks/deploy-media-server.yml -e media_server=jellyfin
```

### Manual Restore

```bash
# Dispatch restore job directly
NOMAD_ADDR=http://192.168.0.10:4646 nomad job dispatch plex-restore

# With specific backup date
NOMAD_ADDR=http://192.168.0.10:4646 nomad job dispatch -meta backup_date=2025-01-15 plex-restore
```

### Manual Nomad Pack Deployment

```bash
# Add registry
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack registry add mediaserver github.com/brent-holden/nomad-mediaserver-packs

# Deploy Plex
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack run plex --registry=mediaserver \
  --var gpu_transcoding=true \
  --var enable_backup=true \
  --var enable_update=true \
  --var enable_restore=true

# Deploy *arr services
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack run radarr --registry=mediaserver
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack run sonarr --registry=mediaserver
```

### Trigger Manual Backup

```bash
# Trigger backup for any service
NOMAD_ADDR=http://192.168.0.10:4646 nomad job periodic force plex-backup
NOMAD_ADDR=http://192.168.0.10:4646 nomad job periodic force radarr-backup
```

## Troubleshooting

### Check Job Status

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad job status
NOMAD_ADDR=http://192.168.0.10:4646 nomad job status plex
NOMAD_ADDR=http://192.168.0.10:4646 nomad job status radarr
```

### View Logs

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad alloc logs -job plex
NOMAD_ADDR=http://192.168.0.10:4646 nomad alloc logs -job plex-backup
NOMAD_ADDR=http://192.168.0.10:4646 nomad alloc logs -job radarr
```

### Check Volumes

```bash
# List all volumes
NOMAD_ADDR=http://192.168.0.10:4646 nomad volume status

# List host volumes only
NOMAD_ADDR=http://192.168.0.10:4646 nomad volume status -type host

# List CSI volumes only
NOMAD_ADDR=http://192.168.0.10:4646 nomad volume status -type csi
```

### Check CSI Plugin Health

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad plugin status cifs
```

### Refresh Nomad Pack Registry

If new packs have been added to the upstream repository:

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack registry delete mediaserver
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack registry add mediaserver github.com/brent-holden/nomad-mediaserver-packs
```

## Notes

- Only one media server (Plex or Jellyfin) should be deployed at a time
- GPU transcoding requires `/dev/dri` on the host
- Backups are stored in `/backups/{service}/YYYY-MM-DD/`
- Backup retention is 14 days by default
- Dynamic host volumes require Nomad 1.10+
- Job naming convention: `{service}-{type}` (e.g., `plex-backup`, `radarr-update`)

## Alternative: Existing Nomad Cluster

If you already have a working Nomad cluster with the CSI plugin deployed, you can use the `setup.sh` script from the packs repository instead:

```bash
git clone https://github.com/brent-holden/nomad-mediaserver-packs.git
cd nomad-mediaserver-packs
NOMAD_ADDR=http://192.168.0.10:4646 FILESERVER_PASSWORD=secret ./setup.sh plex
```

This creates volumes and deploys the media server without the full Ansible infrastructure setup.

## Related Repositories

- [nomad-mediaserver-packs](https://github.com/brent-holden/nomad-mediaserver-packs) - Nomad Pack templates for Plex, Jellyfin, and *arr services
- [nomad-csi-cifs](https://github.com/brent-holden/nomad-csi-cifs) - Standalone CSI CIFS/SMB plugin deployment for Nomad
