# Nomad Media Server Infrastructure

Ansible playbooks for deploying a complete media server infrastructure on HashiCorp Nomad with Plex or Jellyfin.

## Overview

This repository provides automated deployment of:

- **Consul** - Service discovery and health checking
- **Nomad** - Container orchestration with Podman driver
- **CIFS/SMB CSI Plugin** - Network storage for media libraries via SMB/CIFS shares
- **Dynamic Host Volumes** - Nomad-managed local storage using the `mkdir` plugin (Nomad 1.10+)
- **Media Server** - Plex or Jellyfin deployed via Nomad Pack

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
│                                     │  - CSI Plugins          │  │
│  ┌─────────────────────────────────┐│  - Backup/Update Jobs   │  │
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
| `/media` | Media library (movies, TV shows, music) |
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
   # Edit ansible/group_vars/all.yml with your NAS credentials and settings
   ```

2. **Deploy everything:**
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini site.yml
   ```

3. **Access your media server:**
   - Plex: http://192.168.0.10:32400
   - Jellyfin: http://192.168.0.10:8096

## Playbooks

| Playbook | Description |
|----------|-------------|
| `site.yml` | Main playbook - deploys complete infrastructure |
| `deploy-media-server.yml` | Deploy/redeploy media server only |
| `restore-media-server.yml` | Restore configuration from backup |
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
```

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

**Note:** The `restore-plex` or `restore-jellyfin` job must be deployed first. Set `media_server_enable_restore=true` (enabled by default).

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

## Storage Architecture

### CSI Volumes (Network Storage)

CSI volumes provide access to network shares via the SMB/CIFS CSI plugin:

| Volume | Purpose | Mount Path |
|--------|---------|------------|
| `media-drive` | Media library | `/media` |
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

## Jobs Deployed

When you run `site.yml`, the following Nomad jobs are created:

| Job | Type | Description |
|-----|------|-------------|
| `cifs-csi-plugin-controller` | service | CSI volume lifecycle management |
| `cifs-csi-plugin-node` | system | Mounts CSI volumes on nodes |
| `plex` or `jellyfin` | service | Media server |
| `backup-plex` or `backup-jellyfin` | batch/periodic | Daily backup at 2am |
| `update-plex` or `update-jellyfin` | batch/periodic | Daily version check at 3am |
| `restore-plex` or `restore-jellyfin` | batch/parameterized | Manual restore job |

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
NOMAD_ADDR=http://192.168.0.10:4646 nomad job dispatch restore-plex

# With specific backup date
NOMAD_ADDR=http://192.168.0.10:4646 nomad job dispatch -meta backup_date=2025-01-15 restore-plex
```

### Manual Nomad Pack Deployment

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack registry add mediaserver github.com/brent-holden/nomad-mediaserver-packs
NOMAD_ADDR=http://192.168.0.10:4646 nomad-pack run plex --registry=mediaserver \
  -var gpu_transcoding=true \
  -var enable_backup=true \
  -var enable_update=true \
  -var enable_restore=true
```

## Troubleshooting

### Check Job Status

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad job status
NOMAD_ADDR=http://192.168.0.10:4646 nomad job status plex
```

### View Logs

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad alloc logs -job plex
NOMAD_ADDR=http://192.168.0.10:4646 nomad alloc logs -job backup-plex
```

### Check Volumes

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad volume status
NOMAD_ADDR=http://192.168.0.10:4646 nomad volume status -type host
```

### Check CSI Plugin Health

```bash
NOMAD_ADDR=http://192.168.0.10:4646 nomad plugin status smb
```

## Notes

- Only one media server (Plex or Jellyfin) can be deployed at a time
- GPU transcoding requires `/dev/dri` on the host
- Backups are stored in `/backups/{plex,jellyfin}/YYYY-MM-DD/`
- Backup retention is 14 days by default
- Dynamic host volumes require Nomad 1.10+

## Related Repositories

- [nomad-mediaserver-packs](https://github.com/brent-holden/nomad-mediaserver-packs) - Nomad Pack templates for Plex and Jellyfin
