output "exports_file" {
  description = "Path of the exports file the circuit writes on each host."
  value       = "/etc/exports.d/conn3x.exports"
}

output "exports" {
  description = "Exported paths, each mapped to the hosts it's exported to."
  value       = { for path, e in var.exports : path => [for c in e.clients : c.host] }
}
