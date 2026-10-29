variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "centos", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel, centos or fedora."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "exports" {
  type = map(object({
    clients = list(object({
      host    = string
      options = optional(list(string), ["ro"])
    }))
    owner = optional(string)
    group = optional(string)
    mode  = optional(string, "0755")
  }))
  default     = {}
  description = "Exports, by path, such as { \"/srv/nfs/media\" = { clients = [{ host = \"192.168.1.0/24\", options = [\"rw\"] }] } }. The circuit creates each path with owner, group and mode."

  validation {
    condition     = alltrue([for p in keys(var.exports) : can(regex("^/[A-Za-z0-9_./-]*[A-Za-z0-9_.-]$", p)) && !strcontains(p, "..") && !contains(["/", "/etc", "/usr", "/var", "/root", "/boot", "/home", "/proc", "/sys", "/dev"], p)])
    error_message = "An export's path must be an absolute path of letters, digits, ., -, _ and /, with no trailing slash or .., and not a system directory such as / or /etc."
  }

  validation {
    condition     = alltrue([for e in values(var.exports) : length(e.clients) > 0])
    error_message = "Each export needs at least one client."
  }

  validation {
    condition     = alltrue(flatten([for e in values(var.exports) : [for c in e.clients : can(regex("^(@[A-Za-z0-9_.-]+|[A-Za-z0-9*?_.:-]+(/[0-9]{1,3})?)$", c.host))]]))
    error_message = "A client's host is a host name, a wildcard such as *.lan, an IP address or network such as 192.168.1.0/24, or @netgroup."
  }

  validation {
    condition     = alltrue(flatten([for e in values(var.exports) : [for c in e.clients : length(c.options) > 0 && alltrue([for o in c.options : can(regex("^[a-z_0-9]+(=[A-Za-z0-9_:./@-]+)?$", o))])]]))
    error_message = "Each client needs at least one option, such as \"rw\" or \"anonuid=1000\", in lowercase with no spaces or commas."
  }

  validation {
    condition     = alltrue([for e in values(var.exports) : can(regex("^0?[0-7]{3,4}$", e.mode))])
    error_message = "mode is octal, such as \"0755\"."
  }
}

variable "nfs_v3" {
  type        = bool
  default     = false
  description = "Serve NFSv3 as well as NFSv4. Off, the server speaks NFSv4 only and needs just TCP 2049. Changing it restarts the NFS server."
}
