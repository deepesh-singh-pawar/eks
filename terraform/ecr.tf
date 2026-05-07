# -----------------------------------------------------------------------------
# ECR: production-like image registry for the sample app push/pull story.
# Nodes already have ECR read via the managed node policies; CI/your laptop needs `ecr:*` push perms via IAM user/role.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "sample_app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "sample_app" {
  repository = aws_ecr_repository.sample_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retain only the newest few images in a learning repo to control storage cost"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}
