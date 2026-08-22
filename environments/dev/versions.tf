terraform {
  required_version = ">= 1.5.0"
  required_providers {
    sdwan = {
      source  = "ciscoen/sdwan"
      version = ">= 0.3.0"
    }
  }
}
