# This job periodically backs up Jellyfin configuration to a network share.
job "backup-jellyfin" {
  datacenters = ["dc1"]
  type        = "batch"

  # Run daily at 2am
  periodic {
    crons            = ["0 2 * * *"]
    time_zone        = "America/New_York"
    prohibit_overlap = true
  }

  group "backup" {
    count = 1

    # Limit restarts to avoid excessive retries on persistent failures
    restart {
      attempts = 2
      interval = "5m"
      delay    = "30s"
      mode     = "fail"
    }

    # Don't reschedule batch jobs - let them fail and retry next period
    reschedule {
      attempts  = 0
      unlimited = false
    }

    # Mount the Jellyfin config directory (source of backups)
    # This host volume declaration constrains the job to run on nodes
    # that have jellyfin-config configured (same node as the Jellyfin service)
    volume "jellyfin-config" {
      type      = "host"
      source    = "jellyfin-config"
      read_only = true
    }

    # Mount the backup drive (destination for backups)
    volume "backup-drive" {
      type            = "csi"
      source          = "backup-drive"
      access_mode     = "multi-node-multi-writer"
      attachment_mode = "file-system"
    }

    task "backup" {
      driver = "podman"

      config {
        image = "docker.io/debian:bookworm-slim"
        args  = ["/bin/sh", "-c", "sleep 1 && /bin/sh /local/backup-jellyfin.sh"]
      }

      volume_mount {
        volume      = "jellyfin-config"
        destination = "/jellyfin-config"
        read_only   = true
      }

      volume_mount {
        volume      = "backup-drive"
        destination = "/backups"
      }

      template {
        data = <<EOF
#!/bin/sh
set -e

echo "Starting Jellyfin backup job..."

# Install rsync
echo "Installing rsync..."
apt-get update -qq && apt-get install -y -qq rsync > /dev/null 2>&1

# Source directories (Jellyfin stores important data here)
JELLYFIN_DATA_DIR="/jellyfin-config/data"
JELLYFIN_CONFIG_DIR="/jellyfin-config/config"

# Destination directory
BACKUP_DIR="/backups/jellyfin"
DATE=$(date +%Y-%m-%d)
BACKUP_DEST="$BACKUP_DIR/$DATE"

# Create backup directory structure
echo "Creating backup directory: $BACKUP_DEST"
mkdir -p "$BACKUP_DEST/data" "$BACKUP_DEST/config"

# Backup data directory (contains jellyfin.db and library data)
if [ -d "$JELLYFIN_DATA_DIR" ]; then
    echo "Backing up Jellyfin data directory..."
    rsync -av --progress "$JELLYFIN_DATA_DIR/" "$BACKUP_DEST/data/"
    echo "Data backup complete."
else
    echo "Warning: Jellyfin data directory not found at $JELLYFIN_DATA_DIR"
fi

# Backup config directory (contains configuration files)
if [ -d "$JELLYFIN_CONFIG_DIR" ]; then
    echo "Backing up Jellyfin config directory..."
    rsync -av --progress "$JELLYFIN_CONFIG_DIR/" "$BACKUP_DEST/config/"
    echo "Config backup complete."
else
    echo "Warning: Jellyfin config directory not found at $JELLYFIN_CONFIG_DIR"
fi

# Clean up old backups (keep last 14 days)
echo "Cleaning up old backups (keeping last 14 days)..."
find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" -mtime +14 -exec rm -rf {} \; 2>/dev/null || true

# Show backup size
echo "Backup complete. Size:"
du -sh "$BACKUP_DEST"

echo "Successfully backed up Jellyfin to $BACKUP_DEST"
EOF
        destination = "local/backup-jellyfin.sh"
        perms       = "0755"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
