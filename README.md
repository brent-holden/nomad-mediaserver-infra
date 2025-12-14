# Nomad CIFS/SMB CSI Infrastructure

This repository contains Ansible playbooks for setting up a CIFS/SMB CSI (Container Storage Interface) plugin on HashiCorp Nomad. It provides the infrastructure foundation for running containerized applications with shared network storage.

## Overview

The setup deploys:
- **Consul** - Service discovery and health checking
- **Nomad** - Container orchestration with Podman driver
- **CIFS CSI Plugin** - Controller and node plugins for mounting SMB/CIFS network shares
- **CSI Volumes** - Pre-configured volumes for media and backup storage
- **Host Volumes** - Local directories for application configuration

## Quick Start

1. Configure your fileserver credentials in `ansible/group_vars/all.yml`
2. Update `ansible/inventory.ini` with your hosts
3. Run the ansible playbook:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini site.yml
   ```

4. Deploy applications using [nomad-media-packs](https://github.com/brent-holden/nomad-media-packs):
   ```bash
   nomad-pack registry add media github.com/brent-holden/nomad-media-packs
   nomad-pack run plex --registry=media
   nomad-pack run jellyfin --registry=media
   ```

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

### CSI Plugin Settings
```yaml
csi_smb_image: "mcr.microsoft.com/k8s/csi/smb-csi:v1.17.0"
csi_plugin_id: "smb"
csi_driver_name: "smb.csi.k8s.io"
csi_log_level: 5
csi_controller_cpu: 512
csi_controller_memory: 512
csi_node_cpu: 512
csi_node_memory: 512
```

### Host Volume Directories
```yaml
plex_config_dir: "/opt/plex/config"
plex_transcode_dir: "/opt/plex/transcode"
jellyfin_config_dir: "/opt/jellyfin/config"
jellyfin_cache_dir: "/opt/jellyfin/cache"
```

## Directory Structure

```
ansible/
├── group_vars/
│   └── all.yml                  # Configuration variables
├── playbooks/
│   ├── configure-consul.yml
│   ├── configure-nomad.yml
│   ├── deploy-csi-plugins.yml   # Deploys CSI controller and node plugins
│   ├── deploy-csi-volumes.yml   # Registers CSI volumes
│   ├── disable-firewall.yml
│   ├── install-consul.yml
│   ├── install-nomad.yml
│   ├── install-podman-driver.yml
│   └── setup-directories.yml
├── templates/
│   ├── backup-drive-volume.hcl.j2
│   ├── cifs-csi-plugin-controller.nomad.j2
│   ├── cifs-csi-plugin-node.nomad.j2
│   ├── client.hcl.j2
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
| `install-nomad.yml` | Installs Nomad from HashiCorp repository |
| `configure-nomad.yml` | Deploys Nomad server and client configuration |
| `install-podman-driver.yml` | Installs Podman and nomad-driver-podman |
| `setup-directories.yml` | Creates host volume directories |
| `deploy-csi-plugins.yml` | Deploys CSI controller and node plugins |
| `deploy-csi-volumes.yml` | Registers CSI volumes for media and backups |

## CSI Plugins

The playbooks deploy two CSI plugin jobs:

| Job | Type | Description |
|-----|------|-------------|
| `cifs-csi-plugin-controller` | service | Volume lifecycle management (create, delete) |
| `cifs-csi-plugin-node` | system | Mounts volumes on each Nomad client node |

## CSI Volumes

The playbooks configure two CSI volumes:

| Volume | Purpose |
|--------|---------|
| `media-drive` | Shared media library (movies, TV shows, music) |
| `backup-drive` | Backup storage for application configurations |

## Host Volumes

Host volumes are configured for application-specific persistent storage:

| Volume | Path | Purpose |
|--------|------|---------|
| `plex-config` | `/opt/plex/config` | Plex configuration and database |
| `plex-transcode` | `/opt/plex/transcode` | Temporary transcoding files |
| `jellyfin-config` | `/opt/jellyfin/config` | Jellyfin configuration and database |
| `jellyfin-cache` | `/opt/jellyfin/cache` | Jellyfin cache storage |

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

6. **Create host volume directories**:
   ```bash
   # For Plex
   sudo groupadd -g 1001 plex
   sudo useradd -u 1002 -g plex -s /sbin/nologin -M plex
   sudo mkdir -p /opt/plex/config /opt/plex/transcode
   sudo chown -R plex:plex /opt/plex

   # For Jellyfin
   sudo mkdir -p /opt/jellyfin/config /opt/jellyfin/cache
   ```

7. **Configure Nomad** using templates from `ansible/templates/`

8. **Start Nomad**:
   ```bash
   sudo systemctl enable --now nomad
   ```

9. **Deploy CSI plugins** (generate from templates or use ansible):
   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-csi-plugins.yml
   ```

10. **Register CSI volumes**:
    ```bash
    ansible-playbook -i inventory.ini playbooks/deploy-csi-volumes.yml
    ```

## Deploying Media Servers

After the infrastructure is set up, use [nomad-media-packs](https://github.com/brent-holden/nomad-media-packs) to deploy media servers:

```bash
# Add the registry
nomad-pack registry add media github.com/brent-holden/nomad-media-packs

# Deploy Plex (with GPU transcoding, backup, and update jobs)
nomad-pack run plex --registry=media

# Deploy Jellyfin (with GPU transcoding, backup, and update jobs)
nomad-pack run jellyfin --registry=media

# View available options
nomad-pack info plex --registry=media
nomad-pack info jellyfin --registry=media
```

## Notes

- All configuration is managed through `ansible/group_vars/all.yml`
- The SMB share is mounted with UID 1002 and GID 1001 to match the Plex user
- Host volumes provide persistent local storage for application configuration
- CSI volumes enable shared network storage across multiple nodes
