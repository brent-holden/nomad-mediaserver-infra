# Media Services on Nomad using SMB/CIFS CSI Plugin

This repository contains HashiCorp Nomad job specifications for running Plex and Jellyfin media servers with shared media storage via a CIFS/SMB CSI (Container Storage Interface) plugin.

## Overview

The setup uses the SMB CSI driver to mount a network file share containing media files, which is then made available to both Plex and Jellyfin containers. All jobs use Podman as the container runtime.

## Quick Start

1. Configure your fileserver and credentials in `ansible/group_vars/all.yml`
2. Update `ansible/inventory.ini` with your hosts
3. Run the ansible playbook:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini site.yml
   ```

This deploys Plex by default with automatic version updates and daily backups.

## Configuration

Edit `ansible/group_vars/all.yml` to configure your deployment:

### Fileserver Settings
```yaml
fileserver_ip: "10.100.0.1"
fileserver_media_share: "media"
fileserver_backup_share: "backups"
fileserver_username: "plex"
fileserver_password: "<YOUR-PASSWORD>"
```

### Media Server Selection
```yaml
media_server: "plex"      # Options: "plex", "jellyfin", or "both"
enable_updates: true      # Deploy update jobs (check for new versions at 3am)
enable_backups: true      # Deploy backup jobs (backup configs at 2am)
```

### Runtime Overrides
```bash
# Deploy Jellyfin instead of Plex
ansible-playbook -i inventory.ini site.yml -e media_server=jellyfin

# Deploy both media servers
ansible-playbook -i inventory.ini site.yml -e media_server=both

# Deploy without backup jobs
ansible-playbook -i inventory.ini site.yml -e enable_backups=false
```

## Directory Structure

```
├── ansible/                # Ansible playbooks for automated setup
│   ├── group_vars/
│   │   └── all.yml         # Configuration variables
│   ├── playbooks/
│   │   ├── configure-consul.yml
│   │   ├── configure-nomad.yml
│   │   ├── deploy-csi-volumes.yml
│   │   ├── deploy-media-jobs.yml
│   │   ├── disable-firewall.yml
│   │   ├── install-consul.yml
│   │   ├── install-nomad.yml
│   │   ├── install-podman-driver.yml
│   │   └── setup-directories.yml
│   ├── templates/
│   │   ├── backup-drive-volume.hcl.j2
│   │   ├── client.hcl.j2
│   │   ├── consul.hcl.j2
│   │   ├── jellyfin-host-volumes.hcl.j2
│   │   ├── media-drive-volume.hcl.j2
│   │   ├── plex-host-volumes.hcl.j2
│   │   ├── podman.hcl.j2
│   │   └── server.hcl.j2
│   ├── inventory.ini
│   └── site.yml
└── jobs/
    ├── periodic/           # Scheduled jobs (updates, backups)
    │   ├── backup-jellyfin.nomad
    │   ├── backup-plex.nomad
    │   ├── update-jellyfin.nomad
    │   └── update-plex.nomad
    ├── services/           # Media server jobs
    │   ├── jellyfin.nomad
    │   └── plex.nomad
    └── system/             # CSI plugin jobs
        ├── cifs-csi-plugin-controller.nomad
        └── cifs-csi-plugin-node.nomad
```

## Job Descriptions

### Service Jobs

| Job | Description |
|-----|-------------|
| `plex.nomad` | Plex Media Server with GPU transcoding, media mount, and Consul health checks |
| `jellyfin.nomad` | Jellyfin Media Server with media mount and Consul health checks |

### Periodic Jobs

| Job | Schedule | Description |
|-----|----------|-------------|
| `update-plex.nomad` | 3am daily | Fetches latest Plex version from Plex API and updates Nomad variable |
| `update-jellyfin.nomad` | 3am daily | Fetches latest Jellyfin version from GitHub and updates Nomad variable |
| `backup-plex.nomad` | 2am daily | Backs up Plex databases and preferences, keeps 14 days |
| `backup-jellyfin.nomad` | 2am daily | Backs up Jellyfin data and config, keeps 14 days |

### System Jobs

| Job | Description |
|-----|-------------|
| `cifs-csi-plugin-controller.nomad` | SMB CSI controller for volume lifecycle management |
| `cifs-csi-plugin-node.nomad` | SMB CSI node plugin for mounting volumes on hosts |

## Ansible Playbooks

| Playbook | Description |
|----------|-------------|
| `site.yml` | Main playbook - runs all playbooks in order |
| `disable-firewall.yml` | Disables firewalld (RHEL) or ufw (Debian) |
| `install-consul.yml` | Installs Consul from HashiCorp repository |
| `configure-consul.yml` | Deploys Consul server configuration |
| `install-nomad.yml` | Installs Nomad from HashiCorp repository |
| `configure-nomad.yml` | Deploys Nomad server and client configuration |
| `install-podman-driver.yml` | Installs Podman and nomad-driver-podman |
| `setup-directories.yml` | Creates host volume directories |
| `deploy-csi-volumes.yml` | Registers CSI volumes for media and backups |
| `deploy-media-jobs.yml` | Deploys media server, update, and backup jobs |

## Manual Deployment

If not using Ansible, deploy in this order:

1. **Deploy CSI plugins:**
   ```bash
   nomad job run jobs/system/cifs-csi-plugin-controller.nomad
   nomad job run jobs/system/cifs-csi-plugin-node.nomad
   ```

2. **Register CSI volumes** (use ansible templates as reference):
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini playbooks/deploy-csi-volumes.yml
   ```

3. **Set up Plex variables** (if running Plex):
   ```bash
   nomad var put nomad/jobs/plex claim_token="<YOUR-CLAIM-TOKEN>" version="latest"
   ```
   See [Finding an authentication token](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/) for how to obtain your claim token.

4. **Deploy media server:**
   ```bash
   # Plex
   nomad job run jobs/services/plex.nomad
   nomad job run jobs/periodic/update-plex.nomad
   nomad job run jobs/periodic/backup-plex.nomad

   # Or Jellyfin
   nomad job run jobs/services/jellyfin.nomad
   nomad job run jobs/periodic/update-jellyfin.nomad
   nomad job run jobs/periodic/backup-jellyfin.nomad
   ```

## Manual Infrastructure Setup

If not using Ansible, complete the following on each node:

1. **Install Consul** from [HashiCorp's repository](https://developer.hashicorp.com/consul/install)

2. **Configure and start Consul** (see `ansible/templates/consul.hcl.j2`):
   ```bash
   sudo mkdir -p /opt/consul/data
   sudo chown -R consul:consul /opt/consul
   sudo systemctl enable --now consul
   ```

3. **Install Nomad** from [HashiCorp's repository](https://developer.hashicorp.com/nomad/install)

4. **Install Podman**:
   ```bash
   sudo dnf install -y podman   # RHEL/CentOS
   sudo apt install -y podman   # Debian/Ubuntu
   sudo systemctl enable --now podman.socket
   ```

5. **Install nomad-driver-podman**:
   ```bash
   sudo dnf install -y nomad-driver-podman   # RHEL/CentOS
   sudo apt install -y nomad-driver-podman   # Debian/Ubuntu
   sudo mkdir -p /opt/nomad/plugins
   sudo ln -s /usr/bin/nomad-driver-podman /opt/nomad/plugins/
   ```

6. **Create directories** (for Plex):
   ```bash
   sudo groupadd -g 1001 plex
   sudo useradd -u 1002 -g plex -s /sbin/nologin -M plex
   sudo mkdir -p /opt/plex/config /opt/plex/transcode
   sudo chown -R plex:plex /opt/plex
   ```
   Or for Jellyfin:
   ```bash
   sudo mkdir -p /opt/jellyfin/config /opt/jellyfin/cache
   ```

7. **Configure Nomad** using templates from `ansible/templates/`

8. **Start Nomad**:
   ```bash
   sudo systemctl enable --now nomad
   ```

## Notes

- Both media servers are configured with 16GB RAM and 16 CPU cores
- The SMB share is mounted with UID 1002 and GID 1001 to match the Plex user
- Timezone is set to America/New_York for all scheduled jobs
- Backups are stored for 14 days before automatic cleanup
- **Performance Warning:** Running both Plex and Jellyfin simultaneously against the same CIFS/SMB mount point may cause performance issues. It is recommended to run only one media server at a time.
