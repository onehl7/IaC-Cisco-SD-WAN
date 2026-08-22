variable "yaml_directories" {
  type        = list(string)
  description = "List of directories containing the Cisco Network as Code (NaC) YAML files."
  default     = ["data"]
}
