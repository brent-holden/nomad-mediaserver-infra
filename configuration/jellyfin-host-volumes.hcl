client {
  host_volume "jellyfin-config" {
    path      = "/opt/jellyfin/config"  # adjust path as needed
    read_only = false
  }

  host_volume "jellyfin-cache" {
    path      = "/opt/jellyfin/cache"   # adjust path as needed
    read_only = false
  }
}
