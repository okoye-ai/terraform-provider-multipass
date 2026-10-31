# Chapter 11: Extending Terraform by writing a custom provider

## Core Idea
A provider is a Go plugin that wraps a remote API (via a golang client SDK) and exposes resources over RPC — write one when you want an API managed as code or as a self-service front door; the pet resource template (schema + CRUD + acceptance tests) is reproducible for any micro API.

## Frameworks Introduced
- **When to Write a Provider** (two good reasons): (1) wrap a remote API so infrastructure can be managed as code, (2) expose utility functions to Terraform (though for one-offs people usually prefer local-exec or the Shell provider)
  - Best fit: micro APIs and self-service platforms — adoption goes up when customers never have to learn your API's auth/protocols
- **The Provider Anatomy** (five files): `main.go` (boilerplate `plugin.Serve`), `petstore/provider.go` (schema + ResourcesMap + ConfigureFunc), `provider_test.go`, `resource_ps_pet.go` (CRUD), `resource_ps_pet_test.go`
  - Provider responsibilities: expose resources, initialize **shared configuration objects** (API client, connections, mutexes) — init failures almost always mean invalid/expired credentials there
  - Prerequisites: an existing API + a separate golang client SDK repo (OpenAPI spec-first, or hand-written from scratch when only the provider will call it)
- **The CRUD Invocation Matrix** (figure 11.3) — which hooks fire per command:
  - initial apply → Create() → Read()
  - plan → Read()
  - in-place update → Read() → Update() → Read()
  - force-new update → Read() → Delete() → Create() → Read()
  - destroy → Read() → Delete()
- **Schema Design Discipline for Resources**: mark attributes Required/Optional/ForceNew deliberately — `species` is Required+ForceNew (identity-level), `age` Required but not ForceNew (pets have birthdays); don't dodge Update() by ForceNew-ing everything (slow for users)
- **Acceptance Testing Checklist**: schema tests (internal validation, initialization, required env vars via PreCheck) + resource tests (basic create/destroy with `CheckDestroy`, attribute assertions, config with all attributes set); gated by `TF_ACC=1`

## Key Concepts
- **d.SetId()**: sets the unique ID — without it the resource isn't marked created and never persists to state; read the ID from the API response object
- **meta**: the shared configuration object (the SDK client) handed to every CRUD function — `conn := meta.(*sdk.Client)`
- **Read() consistency**: must return the same resource for the same ID or you orphan resources (created by Terraform, now unmanaged)
- **Update() via HasChange**: check each non-ForceNew attribute, PATCH, then call Read() as a side effect
- **Delete()**: API delete + the ID clearing semantics; server-side errors belong to the server/SDK, not the provider
- **EnvDefaultFunc**: `schema.EnvDefaultFunc("PETSTORE_ADDRESS", nil)` — make critical provider config (addresses, keys) settable from environment variables for automation; always implement auth for production APIs
- **Provider install for development**: `.terraformrc` `provider_installation { dev_overrides { ... } direct {} }` pointing at the locally built binary (state may become incompatible with published releases)
- **Publishing**: register at registry.terraform.io, markdown docs, semver GitHub release, CI/CD GoReleaser; private provider registries via the provider registry protocol
- **Error handling**: keep the SDK streamlined; error handling/retry/timeouts are the provider's responsibility (see AWS/Azure provider sources)

## Code Examples
```go
// provider.go — schema, resource map, shared client init
func Provider() *schema.Provider {
    return &schema.Provider{
        Schema: map[string]*schema.Schema{
            "address": &schema.Schema{
                Type:        schema.TypeString,
                Optional:    true,
                DefaultFunc: schema.EnvDefaultFunc("PETSTORE_ADDRESS", nil),
            },
        },
        ResourcesMap: map[string]*schema.Resource{
            "petstore_pet": resourcePSPet(),
        },
        ConfigureFunc: providerConfigure,   // builds & returns sdk.NewClient(cfg)
    }
}

// resource_ps_pet.go — the CRUD skeleton
func resourcePSPet() *schema.Resource {
    return &schema.Resource{
        Create: resourcePSPetCreate, Read: resourcePSPetRead,
        Update: resourcePSPetUpdate, Delete: resourcePSPetDelete,
        Importer: &schema.ResourceImporter{State: schema.ImportStatePassthrough},
        Schema: map[string]*schema.Schema{
            "name":    {Type: schema.TypeString, Optional: true},
            "species": {Type: schema.TypeString, Required: true, ForceNew: true},
            "age":     {Type: schema.TypeInt,    Required: true},
        },
    }
}
func resourcePSPetCreate(d *schema.ResourceData, meta interface{}) error {
    conn := meta.(*sdk.Client)
    pet, err := conn.Pets.Create(sdk.PetCreateOptions{/* d.Get(...) */})
    if err != nil { return err }
    d.SetId(pet.ID)                     // MUST set ID or the resource never happens
    return resourcePSPetRead(d, meta)   // Read() as side effect of Create()
}
```
- **What it demonstrates**: the minimal complete provider blueprint; update/delete follow the same conn → options → call → Read() shape.

## Worked Example
End-to-end: deploy the Petstore API (`terraform-in-action/petstore aws` module: API Gateway + Lambda + RDS, ~24 resources) → `export TF_ACC=1` + `PETSTORE_ADDRESS=<api url>` → `go test -v ./petstore` (Provider, Provider_impl, TestAccPSPet_basic all pass) → `go build` → dev-override in `.terraformrc` → manage `petstore_pet` resources in a normal workspace (age 7→8 shows `~ update in-place`). Serverless cold-start makes first requests take up to 30s; TF_LOG=TRACE for debugging.

## Key Takeaways
1. Provider = RPC plugin wrapping a client SDK; never make raw HTTP calls inside CRUD functions.
2. SetId() in Create() is the single make-or-break call of provider development.
3. Model lifecycle deliberately: ForceNew for identity attributes, in-place updates for mutable ones.
4. Acceptance tests (schema + resource, TF_ACC-gated) are what make the provider production-ready.
5. A Terraform provider is also a product decision: it's the easiest way to get customers to adopt your API.

## Connects To
- **Ch 2**: the function-hook lifecycle this chapter implements from the other side
- **Ch 10**: terraform import pairs with the provider's `Importer: ImportStatePassthrough`
- **Ch 12**: providers in automation need env-var-configurable credentials
- **Appendix E**: writing the companion `data "petstore_pet"` read-only resource