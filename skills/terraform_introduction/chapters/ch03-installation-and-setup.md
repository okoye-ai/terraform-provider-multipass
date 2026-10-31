# Chapter 3: Installation and Setup

## Core Idea
Terraform installs as a single binary per OS; verify any install immediately with `terraform -v`.

## Frameworks Introduced
- **Install → verify ritual**: after installing on any machine, run `terraform -v` as a smoke test before doing anything else.

## Key Concepts
- **Single-binary distribution**: Terraform is distributed as one executable (`.exe` on Windows; package-manager install elsewhere)
- **Versioned releases**: pin the version you verified (book uses `Terraform v1.5.1` as example output)

## Reference Tables

| Platform | Install method |
|---|---|
| Windows | Download zip from Terraform downloads page, extract `terraform.exe` |
| Ubuntu | HashiCorp apt repo: add GPG key + `deb https://apt.releases.hashicorp.com $(lsb_release -cs) main`, then `sudo apt update && sudo apt install terraform` |
| RHEL | `yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo`, then `sudo yum -y install terraform` |
| macOS | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |

## Code Examples *(technical)*
```bash
terraform -v      # e.g. output: Terraform v1.5.1
```

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```
- **What it demonstrates**: the macOS Homebrew path — the fastest verify-able install on Macs.

## Key Takeaways
1. Terraform is one binary — "installing" mostly means choosing a package source.
2. Always verify with `terraform -v`; don't assume the install worked.
3. For other OSes, follow the official Terraform documentation steps.

## Connects To
- **Ch 4**: first commands you run after install (`init`, `plan`, `apply`)