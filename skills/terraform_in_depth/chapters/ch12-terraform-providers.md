# Chapter 12: Terraform providers

## Core Idea
A provider is a Go implementation of Terraform Plugin Framework interfaces — provider, data source, resource, and function — so building one is less about protocol plumbing (gRPC is abstracted away) and more about designing stable user-facing interfaces first, since a provider change is far more disruptive than a module change.

## Frameworks Introduced
- **Interfaces-first design**: before writing any code, define the resources, data sources, and functions you want users to have and how they'll be used (write the example user HCL first); the user experience centers the rest of the design.
  - When to use: building a platform other developers should control with Terraform, an open source platform that lacks a provider, or data-processing functions (e.g. Terraform Core Functions provider).
  - How: sketch desired usage (provider block, data source, resource), then implement each interface backwards from it.
- **Provider interface (Table 12.1)**: `Metadata` (version + type name prefix), `Schema` (provider configuration), `Configure` (build the API client; hand it to resources/data sources via `DataSourceData`/`ResourceData`), `Resources` / `DataSources` / `Functions` (lists of constructors), `New` (provider constructor).
- **Data source interface (Table 12.2)**: `Metadata` (name = `req.ProviderTypeName + "_thing"`), `Schema`, `Configure` (pluck the client from `ProviderData`), `Read` (look up data from user parameters and populate state).
- **Resource interface = CRUD + import (Table 12.3)**: `Metadata`, `Schema`, `Configure`, `Create` (called once), `Read` (refresh from state's ID), `Update` (in place), `Delete`, plus `ImportState`.
- **Function interface (Table 12.4)**: `Metadata`, `Definition` (summary, description, `Parameters`, `Return`), `Run`. Functions are logic only — no client, no state, never reach out to a service (Terraform has no `FunctionData` option), and are ignored gracefully by Terraform < v1.8.
- **Unit vs acceptance tests**: unit tests are isolated and test logic/functions; acceptance tests (`TestAcc` prefix, run only when `TF_ACC=1` via `make testacc`) test against the real service and cost real money.

## Key Concepts
- **Terraform Plugin Framework**: the current state-of-the-art SDK for providers, supporting Protocol version 6; it sits on top of the gRPC protocol so you rarely see the protocol itself.
- **Schema**: the framework data structure exposing parameters, attributes, and configuration values — declares type (`StringAttribute`/`BoolAttribute`), `Required`/`Optional`/`Computed`, `Default`, `Sensitive` (filtered from logs), `DeprecationMessage`, and `MarkdownDescription` (used by tfplugindocs).
- **Model**: the Go struct mirroring a schema (`types.String` fields tagged `tfsdk:"name"`); providers, data sources, and resources each have one.
- **Diagnostics**: the `resp.Diagnostics` collector on most function responses; append `AddAttributeError`/`AddError` messages, keep processing to gather all errors, then `return` when `resp.Diagnostics.HasError()`.
- **tflog**: the Terraform-aware logging package (`tflog.Debug`/`Error`/`Trace`, `SetField`, `MaskFieldValuesWithFieldKeys`) that maps to `TF_LOG` levels — never use `log.Fatal`, which exits without returning errors to Terraform and can leave corrupted state.
- **The Unknown state**: a configuration value whose source hasn't been applied yet (e.g., a provider attribute fed from another provider's resource); detected with `data.X.IsUnknown()` so you can tell the user what to do instead of crashing.
- **dev_overrides**: the `provider_installation` block in `~/.terraformrc` pointing at your `GOBIN` so Terraform uses your locally built provider during development (keep `direct {}` so other providers still install normally).
- **Plan modifiers**: `stringplanmodifier.UseStateForUnknown()` on computed fields prevents endless "known after apply" churn by reusing the state value.
- **Normalization to prevent drift**: if the platform alters what you send (e.g., Mastodon injects HTML), sanitize/normalize in Create/Update AND Read, or you will have eternal state drift.

## Mental Models
- Think of a provider as "primarily interfaces in Terraform to other systems": it's a translation layer between Terraform's declarative graph and a service's API, so its public surface deserves module-level care about compatibility — one provider can back thousands of modules.
- Think of every provider operation as the same loop: load the model from Config/Plan/State, call the client, write results back to state via `resp.State.Set(ctx, &data)`.
- Think of the Configure function as a credential funnel: check Unknown → default from environment variable → override from provider block → complex validation → collect all diagnostics → build and test the client → expose it via `DataSourceData`/`ResourceData`.
- Think of acceptance tests as running the real Terraform binary: `resource.Test` spins up a protocol-6 provider server, drives actual Terraform code, and cleans up.

## Anti-patterns
- **Returning on the first error**: Diagnostics can collect many messages — process everything first so users see all problems at once, then return if `HasError()`.
- **Calling Go's `log.Fatal` in a provider**: kills the process without returning errors to Terraform, possibly corrupting state; use Diagnostics + tflog + return.
- **Skipping normalization**: server-modified fields (added HTML, reformatted timestamps) that go unchecked create perpetual drift on every read.
- **Writing provider config without environment-variable fallbacks**: making credentials `Required` in the schema forces code changes when switching credentials; mark them `Optional` and let env vars (e.g. `MASTODON_HOST`) supply defaults.
- **Shipping scaffolding leftovers**: unrenamed `ScaffoldingProvider`/`Example` types, unpruned example resources/data sources/functions, unupdated `.github/dependabot.yml`, `.copywrite.hcl`, and module names break `go generate` and confuse users.
- **Testing functions with acceptance-style resource tests when unit tests suffice**: functions never touch a service, so use `resource.UnitTest` (no PreCheck) — and gate with `tfversion.SkipBelow(tfversion.Version1_8_0)` since functions need Terraform 1.8+.

## Code Examples
```go
func (p *MastodonProvider) Configure(ctx context.Context, req
    provider.ConfigureRequest, resp *provider.ConfigureResponse) {
    var data MastodonProviderModel
    tflog.Debug(ctx, "mastodon_provider configure")
    resp.Diagnostics.Append(req.Config.Get(ctx, &data)...)

    if data.Host.IsUnknown() {                       // value not yet applied
        resp.Diagnostics.AddAttributeError(path.Root("host"),
            "Unknown Mastodon API Host",
            "Either target apply the source of the value first, set the value "+
                "statically in the configuration, or use the MASTODON_HOST "+
                "environment variable.")
    }
    host := os.Getenv("MASTODON_HOST")               // env var default
    if !data.Host.IsNull() {
        host = data.Host.ValueString()               // provider block wins
    }
    // ...same pattern for client_id, client_secret, email, password, access_token...
    if resp.Diagnostics.HasError() {
        return                                       // report everything at once
    }
    c := mastodon.NewClient(&config)
    user, err := c.GetAccountCurrentUser(context.Background())
    if err != nil {
        resp.Diagnostics.AddError("Mastodon GetAccountCurrentUser Failed, API is not usable.", err.Error())
    }
    resp.DataSourceData = c                          // client to data sources...
    resp.ResourceData = c                            // ...and resources (not functions)
}
```
- **What it demonstrates**: the four-step Configure pattern (Unknown check → env fallback → block override → collect-then-return diagnostics) ending in client creation and exposure.

```go
func (r *PostResource) Create(ctx context.Context, req
    resource.CreateRequest, resp *resource.CreateResponse) {
    var data PostResourceModel
    resp.Diagnostics.Append(req.Plan.Get(ctx, &data)...)
    if resp.Diagnostics.HasError() { return }

    toot := mastodon.Toot{
        Status:     data.Content.ValueString(),
        Visibility: data.Visibility.ValueString(),
        Sensitive:  data.Sensitive.ValueBool(),
    }
    post, err := r.client.PostStatus(context.Background(), &toot)
    if err != nil {
        resp.Diagnostics.AddError("Client Error", fmt.Sprintf("Unable to create post, got error: %s", err))
        return
    }
    p := bluemonday.NewPolicy()                      // strip server-added HTML: normalizing
    data.Id         = types.StringValue(string(post.ID))
    data.CreatedAt  = types.StringValue(post.CreatedAt.String())
    data.Account    = types.StringValue(string(post.Account.ID))
    data.Content    = types.StringValue(p.Sanitize(post.Content))
    data.Visibility = types.StringValue(post.Visibility)
    data.Sensitive  = types.BoolValue(post.Sensitive)
    resp.Diagnostics.Append(resp.State.Set(ctx, &data)...)
}
```
- **What it demonstrates**: the Create flow — plan into model, call the client, normalize server-side transformations, then save the model to state.

## Reference Tables
Table 12.1 — Provider interface: Metadata (version + type prefix) · Schema (provider configuration) · Configure (build and share the client) · Resources (list of resource constructors) · DataSources (list of data source constructors) · Functions (list of function constructors) · New (provider instance).

Table 12.2 — Data source interface: Metadata · Schema · Configure · **Read** (use user parameters, populate state).

Table 12.3 — Resource interface: Metadata · Schema · Configure · Create (once, from plan) · Read (by ID in state) · Update (in place) · Delete (by ID) · ImportState.

Table 12.4 — Function interface: Metadata · Definition (schema-like, with Parameters + Return) · Run.

Test scaffolding: `resource.Test(TestCase{PreCheck, ProtoV6ProviderFactories, Steps[]})` for data sources/resources; `resource.ComposeAggregateTestCheckFunc` runs every check and aggregates failures (vs `ComposeTestCheckFunc`, which stops at the first); multi-step cases test create → `ImportStateVerify` → update; `resource.UnitTest` with `TerraformVersionChecks` for functions.

## Worked Example
The chapter's end-to-end build is the **Mastodon provider** (`terraformindepth/mastodon`): start from the Terraform Provider Scaffolding template (clean up dependabot/CODEOWNERS/copywrite, `go mod edit -module`, `go mod tidy`, rename to `MastodonProvider`, `TypeName = "mastodon"`); define the provider schema (host, client_id, client_secret, email, password, access_token — all `Optional` so env vars can supply them) and a `MastodonProviderModel`; `Configure` validates via env-var fallback and creates a `go-mastodon` client; a `mastodon_account` data source implements Read-only lookup; a `mastodon_post` resource implements CRUD with `UseStateForUnknown` on computed fields and bluemonday-sanitized content; a `provider::mastodon::identity` function composes `@user@server`; acceptance tests cover data source (`bot == "false"`), resource (create/import/update steps with a config-generating function `testAccPostResourceConfig`), and function (known/null/unknown cases); publishing = `go generate` + tfplugindocs, GPG RSA-4096 key registered with the Terraform Registry (or the OpenTofu registry via GitHub issues), and a semver-tagged GitHub release built by goreleaser.

## Key Takeaways
1. Design the interface first: write the HCL you want users to have, then implement the provider, data sources, resources, and functions backwards from that experience.
2. Follow uniform Configure validation everywhere: Unknown check → environment variable → provider-block override → cross-field validation, collecting every diagnostic before returning.
3. Keep client creation in `Configure` and pass it through `DataSourceData`/`ResourceData`, remembering functions deliberately get no client.
4. Normalize every value the server transforms, in Create/Update and Read alike, so reads don't fabricate drift.
5. Test in three tiers: pure unit tests for functions, acceptance tests (`TF_ACC`) for resources and data sources, with import-state and update steps in every resource's case.
6. Publishing is one-time setup plus automation: register a GPG signing key once, reuse it across providers, and let goreleaser build tagged releases; use dev_overrides locally so `go install` builds are testable immediately.

## Connects To
- **Ch 10**: the local provider's `direxists` is this framework's provider-function feature; the external provider is the last resort standing between you and writing one of these.
- **Ch 9 / Ch 3**: provider testing extends module testing concepts (Terratest vs plugin testing — same Go testing base) and the schema design echoes module interface design.
- **Ch 11**: wrappers read Terraform's JSON outputs; a provider is the "internal" alternative when wrapping scripts won't do.
- **gRPC Protocol v6**: the wire protocol between Terraform and providers, abstracted by the Plugin Framework.