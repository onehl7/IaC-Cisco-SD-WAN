# Cisco Catalyst SD-WAN Network-as-Code Module Invocation
# This module reads declarative YAML configurations and applies them to SD-WAN Manager.
module "sdwan" {
  source           = "netascode/nac-sdwan/sdwan"
  version          = ">= 0.1.0"
  yaml_directories = var.yaml_directories
}
