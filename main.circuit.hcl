# Facts give each host's distribution, which picks the package name.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os      = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  package = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "nfs-kernel-server" : "nfs-utils" }

  exports_file = "/etc/exports.d/conn3x.exports"
  conf_file    = "/etc/nfs.conf.d/conn3x.conf"

  # One line per export, in exports(5) form: the path, then each client
  # with its options in brackets and no space between them.
  exports = join("", concat(
    ["# Written by Conn3x. Changes here are overwritten on the next apply.\n"],
    [for path, e in var.exports : "${path} ${join(" ", [for c in e.clients : "${c.host}(${join(",", c.options)})"])}\n"],
  ))

  # The kernel dropped NFSv2 long ago, so vers3 is the one switch left
  # between a v4-only server and one that also speaks v3.
  nfs_conf = <<-EOT
    # Written by Conn3x. Changes here are overwritten on the next apply.
    [nfsd]
    vers3 = ${var.nfs_v3 ? "y" : "n"}
  EOT

  # exportfs -s lists one export and client per line, path first.
  check_paths = join(" ", [for path in keys(var.exports) : "'${path}'"])
}

circuit "nfs" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "server" {
    package {
      name = local.package[each.key]
    }
  }

  step "conf_dir" {
    directory {
      path = "/etc/nfs.conf.d"
    }
  }

  # A drop-in, so /etc/nfs.conf stays as the package shipped it.
  step "conf" {
    file {
      path    = local.conf_file
      content = local.nfs_conf
    }
  }

  step "export_dir" {
    for_each = var.exports
    directory {
      path  = item.key
      owner = item.value.owner
      group = item.value.group
      mode  = item.value.mode
    }
  }

  step "exports_dir" {
    directory {
      path = "/etc/exports.d"
    }
  }

  # Exports go in a file of their own, so anything already in /etc/exports
  # keeps working alongside them.
  step "exports" {
    file {
      path    = local.exports_file
      content = local.exports
    }
  }

  # rpc.nfsd only reads which versions to serve when it starts. This runs
  # on a host's first apply and whenever the drop-in changes.
  step "restart" {
    command {
      command  = "systemctl restart nfs-server"
      triggers = { conf = conn3x_file.nfs__conf[each.key].revision }
    }
  }

  step "running" {
    service {
      name    = "nfs-server"
      state   = "started"
      enabled = true
    }
  }

  # exportfs -ra syncs the kernel's table with the files, which drops
  # exports that went away without disturbing clients of the rest. It
  # still exits 0 on some mistakes, such as a host name that doesn't
  # resolve, so any warning fails the apply, and so does an export that
  # didn't make it into the table.
  step "apply" {
    command {
      command = "out=$(exportfs -ra 2>&1); if [ -n \"$out\" ]; then echo \"$out\" >&2; exit 1; fi; live=$(exportfs -s | awk '{print $1}'); for p in ${local.check_paths}; do printf '%s\\n' \"$live\" | grep -qxF \"$p\" || { echo \"$p is not exported\" >&2; exit 1; }; done"
      triggers = {
        exports = conn3x_file.nfs__exports[each.key].revision
        restart = conn3x_command.nfs__restart[each.key].revision
      }
    }
  }
}
