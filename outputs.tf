output "alb_dns_name" {
  value = aws_lb.app_alb.dns_name
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app_repo.repository_url
}
