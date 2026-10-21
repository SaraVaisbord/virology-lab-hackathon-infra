output "subnet_ids" {
  value = aws_subnet.this[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "total_ha" {
  value       = local.total
  description = "High Availabilty Redundancy"
  # depends_on  = []
}
