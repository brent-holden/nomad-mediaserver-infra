# Nomad Media Server with CIFS/SMB CSI Plugin

This repository contains HashiCorp Nomad job specifications for running Plex and Jellyfin media servers with shared media storage via a CIFS/SMB CSI (Container Storage Interface) plugin.

## Overview

The setup uses the SMB CSI driver to mount a network file share containing media files, which is then made available to both Plex and Jellyfin containers. All jobs use Podman as the container runtime.

## Files

### CSI Plugin Jobs

**`cifs-csi-plugin-controller.nomad`**

Runs the SMB CSI plugin controller as a service job. The controller is responsible for volume lifecycle management (create, delete, etc.). Runs as a single instance using the Microsoft SMB CSI driver image (`mcr.microsoft.com/k8s/csi/smb-csi:v1.17.0`).

**`cifs-csi-plugin-node.nomad`**

Runs the SMB CSI plugin node service as a system job (runs on all Nomad clients). The node plugin handles mounting volumes on individual hosts. Runs in privileged mode with host networking to perform mount operations.

### Volume Definition

**`media-drive-volume.hcl`**

Defines the CSI volume that connects to the SMB/CIFS share. Configuration includes:
- Volume ID: `media-drive`
- Plugin: `smb`
- Access mode: `multi-node-multi-writer` (allows multiple nodes to mount simultaneously)
- Mount options for CIFS including SMB version 3.0
- Credentials for SMB authentication
- Source share path

### Media Server Jobs

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

### Utility Scripts

**`update-plex-version.sh`**

A bash script that:
1. Fetches the latest Plex version from the Plex API (PlexPass channel)
2. Updates the Nomad variable `nomad/jobs/plex` with the new version

## Prerequisites

- HashiCorp Nomad cluster
- Podman task driver configured on Nomad clients
- Directories created on Nomad clients for host volumes:
  ```bash
  sudo mkdir -p /opt/nomad/volumes/plex-config
  sudo mkdir -p /opt/nomad/volumes/plex-transcode
  sudo mkdir -p /opt/nomad/volumes/jellyfin-config
  sudo mkdir -p /opt/nomad/volumes/jellyfin-cache
  ```
- Host volumes configured in Nomad client configuration (`/etc/nomad.d/client.hcl`):
  ```hcl
  client {
    host_volume "plex-config" {
      path      = "/opt/nomad/volumes/plex-config"
      read_only = false
    }
    host_volume "plex-transcode" {
      path      = "/opt/nomad/volumes/plex-transcode"
      read_only = false
    }
    host_volume "jellyfin-config" {
      path      = "/opt/nomad/volumes/jellyfin-config"
      read_only = false
    }
    host_volume "jellyfin-cache" {
      path      = "/opt/nomad/volumes/jellyfin-cache"
      read_only = false
    }
  }
  ```
- Network access to the SMB share
- Consul (optional, for service discovery)

## Deployment Order

1. Deploy the CSI plugin controller:
   ```bash
   nomad job run cifs-csi-plugin-controller.nomad
   ```

2. Deploy the CSI plugin node service:
   ```bash
   nomad job run cifs-csi-plugin-node.nomad
   ```

3. Register the CSI volume:
   ```bash
   nomad volume create media-drive-volume.hcl
   ```

4. Set up Plex Nomad variables (if running Plex):
   ```bash
   nomad var put nomad/jobs/plex claim_token="your-claim-token" version="latest"
   ```

5. Deploy a media server (choose one):
   ```bash
   # For Plex:
   nomad job run plex.nomad

   # Or for Jellyfin:
   nomad job run jellyfin.nomad
   ```

## Notes

- Both media servers are configured with 16GB RAM and 16 CPU cores
- The SMB share is mounted with UID 1002 and GID 1001 to match the Plex user
- Timezone is set to America/New_York for both services
- **Performance Warning:** Running both Plex and Jellyfin simultaneously against the same CIFS/SMB mount point may cause performance issues due to concurrent file access, library scanning, and metadata operations competing for network I/O. It is recommended to run only one media server at a time.
