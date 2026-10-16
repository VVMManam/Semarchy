# Semarchy SDP – Azure DevOps CI/CD

This folder holds everything needed to build the Semarchy model in `src/` and
deploy it to the three Semarchy SDP environments from Azure DevOps.

```
 Run pipeline (manual) — tick the environments you want
     │
     ▼
 ┌──────────┐ ─► Deploy Dev    (if ticked, no approval)
 │  Build & │ ─► Deploy Test   (if ticked, no approval)
 │ validate │ ─► ⏸ Approval → Deploy Prod   (if ticked, main branch only)
 └──────────┘
```

Nothing runs on push. The ticked environments deploy independently of each
other (not one after another); each waits only for the Build stage.

| Environment | Instance | Deploys | Azure DevOps environment | Variable group |
|---|---|---|---|---|
| Dev  | https://adpg-mdm-dev.eu.semarchy.net/  | When ticked, no approval | `MDM-SDP-Dev`  | `MDM-SDP-Dev`  |
| Test | https://adpg-mdm-test.eu.semarchy.net/ | When ticked, no approval | `MDM-SDP-Test` | `MDM-SDP-Test` |
| Prod | https://adpg-mdm.eu.semarchy.net/      | When ticked, **after approval** (main only) | `MDM-SDP-Prod` | `MDM-SDP-Prod` |

Based on Semarchy's guide
[Set up an Azure DevOps CI/CD pipeline for SDP](https://support.semarchy.com/support/solutions/articles/43000794896-set-up-an-azure-devops-ci-cd-pipeline-for-sdp).

## What's in this folder

```
ci-cd/
├─ azure-pipelines.yml            The pipeline: Build → Dev → Test → Prod
├─ config/
│  ├─ common.yml                  Shared settings (Node version, model folder, CLI package path)
│  ├─ dev.yml                     Dev instance URL, datasource, data location
│  ├─ test.yml                    Test instance URL, datasource, data location
│  └─ prod.yml                    Prod instance URL, datasource, data location
├─ templates/
│  ├─ stage-deploy.yml            One deploy stage (used for Dev, Test and Prod)
│  └─ steps-install-sem-design.yml  Installs Node + the Semarchy Design CLI
├─ scripts/
│  ├─ Invoke-SemDesign.ps1        Runs sem-design build/deploy and fails the step reliably
│  ├─ Test-ModelInventory.ps1     Lists every model element and flags files that would not deploy
│  ├─ Convert-ToDataProduct.ps1   One-time conversion of the model to the Design CLI 2.x format
│  └─ Setup-AzureDevOps.ps1       One-time Azure DevOps setup (environments, approval, secrets, pipeline)
└─ tools/
   └─ semarchy-sem-design-2.0.1.tgz.zip  Semarchy Design CLI 2.0.1, the agreed version, zipped (see tools/README.md)
```

## What gets deployed

Each deploy runs Semarchy Design CLI **2.0.1**:
`sem-design data-product deploy --data-product-folder src`. It deploys the
**whole data product** in `src/` as one model edition. Nothing is
picked selectively, so every element type goes together:

| Area | Elements (from `src/DataProject`) |
|---|---|
| Data model | Data product profile, entities (attributes, keys, entity type), references, lists of values, model diagrams, data retention policy |
| Match & merge | Match rules (inside each fuzzy-matched entity's `matcher`), ID and standard survivorship rules, duplicate managers |
| Data quality | SemQL validations, SemQL enrichers, Java plugin enrichers |
| Flows & jobs | Workflows, certification jobs |
| Applications & UI | Applications, forms, collection views, display cards, business views, steppers, action sets |
| Queries & security | Named queries, data product privilege grants |

Before every build and every deploy, `Test-ModelInventory.ps1` counts each
element type and adds the table to the run's **Summary** tab (under *Semarchy
model inventory* and *Model deployed to &lt;env&gt;*). It also saves
`Semarchy-model-inventory.json` in the build artifact (`semarchy-model-build`). It **stops the run** if a
`.seml` file has no `_type` or two elements clash on name. It **warns** about:

- files that are not `*.seml`, such as `*.seml.disabled`. These are left out of the deploy.
- files whose name doesn't match their element type
- fuzzy-matched entities with no match rules or no ID survivorship rule

Set `MODEL_CHECK_STRICT: 'true'` in `config/common.yml` to make warnings stop the run too.

### Before the first run: convert the model to 2.0.1 and fix three errors

Checked 26 Sep 2026 with Design CLI 2.0.1 against the current `src/`
(439 model files: 43 entities, 11 of them fuzzy-matched; 70 references; 14 LOVs;
26 match rules; 24 survivorship rules; 12 validations; 15 enrichers; 2 workflows;
26 jobs; 2 applications; 170+ UI elements).

**Step 1: convert to the 2.x format (one command).** The project was written for
Design CLI 1.x. Version 2.0.1 renamed four element types and rejects the old names
("Missing mandatory model file", "Unknown _type: ModelJob", "function UPPER does
not exist"...):

| 1.x `_type` | 2.0.1 `_type` | Files in this project |
|---|---|---|
| `Model` | `DataProductProfile` | 1 (`CustomerModel`) |
| `ModelJob` | `CertificationJob` | 26 (`ModelJobs/`) |
| `ModelPrivGrant` | `DataProductPrivGrant` | 3 (`model_privilage_grant/`) |
| `ModelVariable` | `DynamicVariable` | 0 |

From the repo root:

```powershell
.\ci-cd\scripts\Convert-ToDataProduct.ps1 -DataProductFolder src -WhatIf   # preview
.\ci-cd\scripts\Convert-ToDataProduct.ps1 -DataProductFolder src           # convert
```

The script changes only the `_type:` line in those 30 files, and keeps line
endings. It also renames files to `<name>.<type>.seml` with `git mv` (26 renames,
including `ContactPurposeForm.seml` → `ContactPurposeForm.Form.seml`). Running it
twice changes nothing. Tested on a copy of this repo.

**Step 2: fix three model errors.** These fail with every CLI version:

1. **Unresolved merge conflict** in
   `entities/CustomerLegalAccount/CustomerLegalAccount.Entity.seml`, match rule
   `MR05_TrnMatch_NameSimilar` (around line 794). The file has `<<<<<<< HEAD` and
   `=======` markers with two versions of the rule. This breaks the whole entity
   and causes about 200 follow-on errors. Keep one version and delete the markers.
   The second version (`FID_IdentifierType = 'TRN'`, name similarity >= 90,
   `matchOnExpression: Identifier`) matches the other rules and the MR-05 design.
2. **MR-19** (`NameMOLExact_LicenseIndependent`, around line 945) has
   `matchOnExpression: MdmIdentifier`. Every other rule uses `Identifier`.
3. **Orphan enricher** `entities/MdmLicense/enrichers/EnrichEmirateCode.JavaPluginEnricher.seml`
   points at an entity `MdmLicense` that doesn't exist. Delete it with `git rm`.

With steps 1 and 2 done, `sem-design data-product build` (2.0.1) reports
**Build successful**. The pipeline enforces this: the completeness check stops on
merge-conflict markers and on 1.x element types, and the build step stops on any
other model error, so nothing is deployed until they're fixed.

**Not deployed** (`.disabled` files; rename to `.seml` to include):

- `workflows/DuplicateConfirmation.Workflow.seml.disable`
- `entities/CustomerLegalAccount/enrichers/SetInitialUnderReviewStatus.SemQLEnricher.seml.disabled`
- `entities/Identifier/validations/IdentifierValueFormatCheck.SemQLValidation.seml.disabled`
- `entities/CustomerLegalAccount/enrichers/EnrichEmirateCode.JavaPluginEnricher.seml.disabled` (needs its plugin on each instance)
- `List_of_values/TitleCode.LOVType.seml.disabled` and
  `entities/changerequest/action_sets/WorkflowActionSet.ActionSet.seml.disabled`
  are old copies. The active `.seml` versions exist and are deployed.

**Not part of a model deploy:** platform-level items such as roles, users,
datasources, plugin JARs and `resources/platform-administration` exports
(currently empty). These are set up once per instance, in Platform
Administration or through the SDP API.

## Per-environment configuration

Each environment has its own file in `config/`. Change settings there, commit,
and the next run uses them. Secrets are never in these files.

| Setting | Meaning |
|---|---|
| `SDP_INSTANCE_URL` | Root URL of the Semarchy Data Platform instance (`https://<tenant-url>`, **no `/dm`**; that's the Design CLI 2.x format) |
| `SDP_DATA_SOURCE` | Datasource on that instance that backs the data location |
| `SDP_DATA_LOCATION` | Data location the model is deployed into |

The client ID and secret for each environment are in the matching variable
group (**Pipelines › Library**), as secret variables `SDP_CLIENT_ID` and
`SDP_CLIENT_SECRET`.

> **Check before the first run:** all three files currently use datasource
> `datasource1` and data location `adpg_model1` (taken from the repo's
> `ADPG-MDM.code-workspace`). Confirm the real names on each instance.
> The instance URLs have no `/dm` suffix, as Design CLI 2.x requires. The deploy
> step stops with a clear message if a URL ends in `/dm`.

## One-time setup

### 1. Semarchy SDP (each of Dev, Test, Prod)

1. Make sure the datasource and data location named in `config/<env>.yml` exist
   (datasources are created through the SDP API).
2. **Platform Administration › Clients › +** – create a technical client for
   the pipeline, give it the **DM Admin** role, and copy the client ID and secret.
   Use a separate client per environment.

### 2. Repository

1. Make sure `ci-cd/tools/semarchy-sem-design-2.0.1.tgz.zip` is committed
   (see [tools/README.md](tools/README.md)).
2. Run the model conversion and fixes in *Before the first run* above.
3. Commit and push the `ci-cd` folder and the converted `src` to `main`.

### 3. Azure DevOps – automatic (recommended)

Run the setup script once from the repo root. It creates the three
environments, the **Prod approval check**, the three variable groups (it
prompts for the client IDs and secrets), the pipeline, and grants the pipeline
access to all of them. It is safe to re-run.

```powershell
# PAT scopes: Build (Read & execute), Code (Read), Environment (Read & manage),
# Variable Groups (Read, create & manage), Project and Team (Read), Identity (Read)
.\ci-cd\scripts\Setup-AzureDevOps.ps1 -ProdApprovers 'first.last@adports.ae','[Semarchy]\Release Approvers'
```

Defaults: organisation `abudhabiports`, project `Semarchy`, repository
`Semarchy`, pipeline name `ADPorts-MDM-Build`. Override with `-Organization`,
`-Project`, `-Repository`, `-PipelineName`. Use `-MinimumApprovers 2` to
require two approvals.

### 3. Azure DevOps – manual alternative

1. **Pipelines › Environments › New environment** – create `MDM-SDP-Dev`,
   `MDM-SDP-Test`, `MDM-SDP-Prod` (resource: *None*).
2. Open **MDM-SDP-Prod › ⋮ › Approvals and checks › + › Approvals** – add the Prod
   approvers. Leave MDM-SDP-Dev and MDM-SDP-Test with no checks so they deploy without approval.
3. **Pipelines › Library › + Variable group** – create `MDM-SDP-Dev`,
   `MDM-SDP-Test`, `MDM-SDP-Prod`, each with `SDP_CLIENT_ID` and
   `SDP_CLIENT_SECRET`. Click the padlock on both to make them secret.
4. **Pipelines › New pipeline › Azure Repos Git › Semarchy › Existing Azure
   Pipelines YAML file** – branch `main`, path `/ci-cd/azure-pipelines.yml`. Save.
5. On the first run, click **Permit** when the run asks for access to the
   environments and variable groups.

> Create the `MDM-SDP-Prod` approval **before** the first run. If an environment
> does not exist, Azure DevOps creates it on first use with no approval.

### Pipeline name

The pipeline is called **ADPorts-MDM-Build**, and its runs are numbered
`ADPorts-MDM-Build-<yyyyMMdd>.<n>`. The run number comes from the `name:` line in
`azure-pipelines.yml`. The pipeline's own name is set in Azure DevOps: open
**Pipelines**, click the pipeline, then **⋮ › Rename/move**.

### 4. Recommended protections

- **Repos › Branches › main › Branch policies**: require a pull request and add
  a **Build validation** policy using this pipeline. PR runs only execute the
  Build stage; nothing is deployed.
- On `MDM-SDP-Prod`, you can also add **Business hours** or **Exclusive lock**
  checks.

## Agents

By default every job runs on Microsoft-hosted `ubuntu-latest` agents. To use a
self-hosted pool (for example `Default`, as in Semarchy's guide), run the
pipeline manually and set the **Agent pool** parameter to:

```yaml
name: Default
```

To make that permanent, change the `agentPool` default in `azure-pipelines.yml`.
Linux and Windows agents both work; the scripts use PowerShell and need no admin
rights.

New Azure DevOps organisations may need a free hosted-parallelism grant from
Microsoft before Microsoft-hosted agents run jobs.

## Running and approving

- The pipeline never starts on its own. Open **Pipelines › ADPorts-MDM-Build ›
  Run pipeline**, pick the branch, tick **Deploy to Dev**, **Deploy to Test**
  and/or **Deploy to Prod**, then **Run**.
- With nothing ticked, the run only builds and validates the model.
- Prod is deployed only from `main`; from another branch the Prod stage is skipped.
- When a run reaches Prod, approvers get a notification. Open the run and
  click **Review › Approve**. The approval times out after 3 days by default.
- The first run that uses an environment may also ask to **Permit** access to
  the environment and its variable group. That is a one-time authorisation,
  not an approval.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Semarchy Design CLI package not found` | Commit `ci-cd/tools/semarchy-sem-design-2.0.1.tgz.zip` (or change `SEM_DESIGN_PACKAGE`). |
| `Semarchy Design CLI version is 'x' but this pipeline requires '2.0.1'` | The package in `tools/` isn't 2.0.1. Replace it, or change `SEM_DESIGN_VERSION` in `config/common.yml` once a new version is agreed. |
| `uses _type 'Model'/'ModelJob'/'ModelPrivGrant'`, `Missing mandatory model file`, `Unknown _type: ModelJob` | The model is still in 1.x format. Run `scripts/Convert-ToDataProduct.ps1`. |
| `Error executing command ...` | The CLI failed before deploying: bad URL, credentials or connection. Design CLI 2.0.1 exits 0 in this case, so the wrapper also requires the CLI's `Deployment successful` message. |
| `Deployment settings missing or still placeholders: SDP_CLIENT_ID…` | Variable group missing, not authorised, or values still `CHANGE_ME`. Check Pipelines › Library. |
| Run waits with "needs permission" | Click **Permit**, or re-run `Setup-AzureDevOps.ps1`. |
| `Cannot read properties of null (reading 'displayFormatValueInterpreter')` | A model error in `src/` (seen before in `TaxTypeForm.Form.seml`). Fix the model; the Build stage stops before anything deploys. |
| 401 / invalid client on deploy | Wrong client for that instance, or the client lacks the **DM Admin** role. |
| Summary shows a warning for a `.disabled` file or a file name that doesn't match its type | See *What gets deployed* above. Rename the file, or set `MODEL_CHECK_STRICT` to `true` to block deploys until it's fixed. |
| `no model found` / unknown data location | Check `SDP_DATA_SOURCE` / `SDP_DATA_LOCATION` in `config/<env>.yml`. |

## Running the same commands locally

```powershell
Expand-Archive .\ci-cd\tools\semarchy-sem-design-2.0.1.tgz.zip $env:TEMP\semdesign -Force
npm install -g $env:TEMP\semdesign\semarchy-sem-design-2.0.1.tgz
.\ci-cd\scripts\Invoke-SemDesign.ps1 -Action Build -RootFolder src

$env:SDP_CLIENT_ID = '<dev client id>'; $env:SDP_CLIENT_SECRET = '<dev secret>'
.\ci-cd\scripts\Invoke-SemDesign.ps1 -Action Deploy -RootFolder src `
    -InstanceUrl https://adpg-mdm-dev.eu.semarchy.net -DataSource datasource1 -DataLocation adpg_model1
```
