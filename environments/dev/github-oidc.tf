resource "aws_iam_openid_connect_provider" "github" {
url = "https://token.actions.githubusercontent.com"
client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
name = "landing-zone-github-actions-role"

assume_role_policy = jsonencode({
Version = "2012-10-17"
Statement = [
{
Effect = "Allow"
Action = "sts:AssumeRoleWithWebIdentity"
Principal = {
Federated = aws_iam_openid_connect_provider.github.arn
}
Condition = {
StringEquals = {
"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
}
StringLike = {
"token.actions.githubusercontent.com:sub" = "repo:FabioENS/landing-zone:*"
}
}
}
]
})
}

output "github_actions_role_arn" {
value = aws_iam_role.github_actions.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_readonly" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}