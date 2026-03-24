plugin "google" {
  source  = "github.com/terraform-linters/tflint-ruleset-google"
  # Pinned semver (operators like ~> break tflint --init GitHub fetch)
  version = "0.30.0"
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
