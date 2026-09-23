output "embedding_lambda_role_arn" {
  value = aws_iam_role.embedding_lambda.arn
}

output "embedding_lambda_role_name" {
  value = aws_iam_role.embedding_lambda.name
}

output "retrieval_lambda_role_arn" {
  value = aws_iam_role.retrieval_lambda.arn
}

output "retrieval_lambda_role_name" {
  value = aws_iam_role.retrieval_lambda.name
}

output "admin_role_arn" {
  value = aws_iam_role.admin.arn
}

output "admin_role_name" {
  value = aws_iam_role.admin.name
}
