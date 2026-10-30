variable "region" {
  default = "us-west-2"
}

variable "cpu_instance_type" {
  description = "Always-on node: k3s server + gateway + llama.cpp CPU tier"
  default     = "t4g.xlarge" # arm64, 4 vCPU / 16 GiB — enough for a 3-4B Q4 model
}

variable "gpu_instance_type" {
  description = "On-demand vLLM node, stopped when idle"
  default     = "g6.xlarge" # L4 24 GB
}

variable "ssh_ingress_cidr" {
  description = "Who may reach port 22. Tighten to your home IP if it is stable."
  default     = "0.0.0.0/0"
}

variable "artifact_bucket" {
  default = "starsi-artifacts"
}
