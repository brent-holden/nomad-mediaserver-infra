client {

  host_volume "plex-config" {
    path = "/opt/plex/config"
    read_only = false
  }

  host_volume "plex-transcode" {
    path = "/opt/plex/transcode"
    read_only = false
  }

}
