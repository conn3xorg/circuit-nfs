variable "port" {
  type    = number
  default = 2222
}

module "nfs" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  exports = {
    # Read-write for one client. Its root user is squashed to nobody, who
    # owns the folder, so it can write.
    "/srv/nfs/projects" = {
      clients = [{ host = "10.89.63.10", options = ["rw", "sync", "no_subtree_check"] }]
      owner   = "nobody"
    }
    # Read-only for the whole network.
    "/srv/nfs/public" = {
      clients = [{ host = "10.89.63.0/24", options = ["ro", "no_subtree_check"] }]
    }
  }
}
