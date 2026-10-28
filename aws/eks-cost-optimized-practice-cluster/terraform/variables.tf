variable "region" {
  description = "AWS Region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name (also used to name/tag every resource)"
  type        = string
  default     = "eks-practice"
}

variable "kubernetes_version" {
  description = "Use a version in STANDARD support ($0.10/hr). Extended support costs $0.60/hr."
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "Several similar types improve Spot availability"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
