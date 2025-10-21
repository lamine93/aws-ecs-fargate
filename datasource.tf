data "aws_availability_zones" "regional" {
  state = "available"

  # exclude Local/Wavelength
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }

  # keep AZ standard
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  az_a = data.aws_availability_zones.regional.names[0]
  az_b = data.aws_availability_zones.regional.names[1]
}