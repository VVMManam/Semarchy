# ADPG  — generated Semarchy xDM model (build-fix release)

Generated from `ADPG__Target_Data_Model_V0_2_1.xlsx`.

```
ADPG_/
├─ ADPG-.code-workspace
├─ .vscode/settings.json
├─ resources/platform-administration/
└─ src/
   └─ DataProject/
      ├─ CustomerModel.Model.seml
      ├─ entities/<Entity>/
      │     <Entity>.Entity.seml
      │     forms/ collection_views/ display_cards/
      │     business_views/ steppers/
      │     enrichers/ validations/ survivorship_rules/
      ├─ references/
      └─ applications/AdpgApplication.Application.seml
```

Open the **`.code-workspace` file** (not the folder) in VS Code, then Deploy.

---

## What is in the model

| Artefact | Count |
|---|---|
| Entities | 38 |
| References | 81 |
| Forms / Collection views / Display cards | 38 each |
| Business views (hierarchical) | 15 |
| Steppers | 15 |
| SemQL enrichers | 6 |
| SemQL validations | 15 |
| Survivorship rules (ID + default) | 14 |
| Application | 1 |

### Fuzzy-matched entities (7)

`Party`, `CustomerLegalAccount`, `CustomerOrgAssignment`, `Contact`,
`SupplierLegalAccount`, plus the agreed override `Identifier` and `Address`.
Everything else is `BASIC`.

---

## Fixes applied in this build

Every item below was a validation error on the previous deploy.

**1. Primary keys vs. `mode: SEQUENCE`**
A `String` column cannot back a sequence. PKs now follow the convention proven in
the live `AdPorts-` model:

* a generated PK (all matched entities, and every BASIC entity whose spec `Mand.`
  is `Gen`) → `dataType: LongInteger`, `precision: 38`, `sourceIdGeneration.mode: SEQUENCE`;
* a reference-code PK (`CountryCode`, `IdentifierTypeCode`, `BusinessUnitCode`, …)
  → stays `String`, `sourceIdGeneration.mode: MANUAL` — exactly as
  `CountryReference` and `IssuingAuthority` do today.

**2. Missing survivorship rules**
Each of the 7 matched entities now carries
`survivorship_rules/IdSurvivorshipRule.IDSurvivorshipRule.seml` and
`survivorship_rules/DefaultRule.StandardSurvivorshipRule.seml`, copied from the
format Party uses in the live model.

**3. `invalid qualified name … last attribute is a reference`**
A foreign key can never be named bare in SemQL. Every occurrence now traverses to
a scalar on the referenced entity:

| was | now |
|---|---|
| `Record1.Pgid` | `Record1.Pgid.Pgid` |
| `Record1.Cgid` | `Record1.Cgid.Cgid` |
| `Record1.RegistrationCountry` | `Record1.RegistrationCountry.CountryCode` |
| `Record1.RegistrationEmirateCode` | `Record1.RegistrationEmirateCode.EmirateCode` |
| `Record1.NationalityCode` | `Record1.NationalityCode.CountryCode` |
| `IdentifierTypeCode = 'TRN'` | `IdentifierTypeCode.IdentifierTypeCode = 'TRN'` |
| `BusinessUnitCode` | `BusinessUnitCode.BusinessUnitCode` |

**4. SemQL function set — restricted to what this instance actually has**

* `REGEXP_REPLACE` is the **three-argument** form here — `REGEXP_REPLACE(x, pat, repl)`.
  There is no `'g'` flag; it already replaces every occurrence. The previous build
  used the four-argument PostgreSQL form throughout, which is why *every*
  `REGEXP_REPLACE` reported "function does not exist".
* `SEM_NGRAMS_SIMILARITY` — the similarity function already used in
  `SBCAudit/EnrichMatchScore` — is used for all fuzzy name comparison, and it
  returns **0–100**, not 0–1. All thresholds were rescaled: `0.90 → 90`,
  `0.75 → 75`, `0.93 → 93`, `0.92 → 92`.
* Removed entirely: `BTRIM`, `RTRIM`, `LENGTH`, `NULLIF`, `COALESCE`, `TRANSLATE`,
  `SPLIT_PART`, `METAPHONE`. Length tests are now regex (`REGEXP_LIKE(x, '^.{4,}$')`),
  null-coalescing is `CASE WHEN`, trimming is `LTRIM`, and the phonetic key is the
  letters-only form of `NameMatchKey` (the fuzzy work is done by
  `SEM_NGRAMS_SIMILARITY` in the rules themselves).
* Only these remain: `UPPER`, `LOWER`, `LTRIM`, `INITCAP`, `REGEXP_LIKE`,
  `REGEXP_REPLACE`, `SEM_NGRAMS_SIMILARITY`, `CASE WHEN`, `||`.

**5. `_name is not unique`** — nested `BusinessViewEntity` and
`BusinessViewTransition` nodes are now suffixed when the same entity appears twice
in one hierarchy (e.g. `CustomerLegalAccount2` where it is reachable both
directly from Party and through `PartyRole`). `transitionPath` still carries the
real reference role.

**6. Physical names ≤ 25 characters** — table names, column names, reference
physical names and `toRolePhysicalName` are abbreviated deterministically
(`_LICENSE_ACTIVITY_GROUP_TYPE` → `_LIC_ACTV_GROUP_TYPE`) with
per-entity collision handling.

**7. `The precision attribute is required`** — every `Decimal`, `Integer` and
`LongInteger` attribute now emits `precision` (and `scale` for decimals). A bare
`Decimal` in the spec defaults to `(18,4)`; `Integer` → 10; `LongInteger` → 38.

**8. Reserved name** — `IdentifierType.MatchRule` → `MatchRuleValue`
(physical column `MATCH_RULE` unchanged).

**9. `Missing key 'defaultAction'`** — the application now ends with
`defaultAction: DataProject.applications.AdpgApplication.Root`.

**10. Attributes that were being dropped** — the four composite/unparseable FK
targets (`LicenseActivity.ActivityCode`, `.ActivityGroupCode`,
`LicenseActivityType.GroupCode`, `PartyRole.RoleScopeCode`) were previously
skipped as references but no reference could be built for them, so they vanished.
They are now emitted as plain attributes.

### About the `no model found` errors

Every file in the previous log reported `no model found` / "Missing mandatory
model file", and *every* function — including `UPPER` and `SEM_NGRAMS_SIMILARITY`,
which demonstrably work in the live model — reported "does not exist". That is a
single cascade: the model failed to compile on the structural errors above, so the
SemQL function library never loaded and each downstream file was validated with no
model in scope. `CustomerModel.Model.seml` here is byte-identical to the live one.
Clearing items 1–10 should clear the cascade; if `no model found` persists on its
own, the cause is the deploy target rather than the source
(`--data-location adpg_model` / `--data-source datasource1` in the workspace file
vs. `adpg_customer_model` / `datasource0` on the live instance).

---

## Match rules shipped

**Party** — M-01 Fusion/ERP ID (100) · M-02 licence+authority+country (98) ·
M-03 licence+country, name ≥ 90 (95) · M-04 licence+country, name 75–89 (85) ·
M-05 TRN + name ≥ 90 (95) · M-06 TRN, weak name (80, relationship) ·
M-07 Emirates ID, individuals (98) · M-08 name+country+corroborator (88) ·
M-10 fuzzy name ≥ 93 + corroborator (82).
M-13 is enforced by the enricher — a placeholder identifier yields a NULL key, and
NULL never equals NULL. M-14 is the `IsInternalEntity = 0` clause on every rule.
M-03 and M-05 additionally require `Record1.IsBranch = Record2.IsBranch` so a
branch never auto-merges into its head office.

**Contact** — C-01 e-mail (98) · C-02 Emirates ID (98) · C-03 passport +
nationality (95) · C-04 mobile + name similarity (88) · C-05 name similarity
within the same party (80).

**Identifier / Address / CustomerOrgAssignment / CustomerLegalAccount** — exact,
score 100: same party + type + normalised value; same party + address key; Cgid +
business unit; one customer account per party.

**SupplierLegalAccount** — MAT-01, 02, 02B, 06, 07, 08, 09, 10, 14 on name, licence,
TRN (from the Fusion VAT number), registration country and website domain. Non-trade
and holding accounts never match. MAT-06 (name + country only) is a steward
suggestion (90), not an auto-merge.

**Supplier children** — Site: same supplier + site code. Assignment: same site +
client BU. Bank account: IBAN / account number rules always require the same
supplier (bank accounts of different suppliers never merge). Identifier,
TaxRegistration, Address and Contact each have a same-supplier (or same-site)
exact rule next to their same-customer rule.

## To confirm on your side after this deploys

1. `SEM_NGRAMS_SIMILARITY` thresholds — 90/93 are the design values on a 0–100
   scale; tune once you have real candidate volumes.
2. POSIX classes (`[[:space:]]`, `[[:punct:]]`, `[[:cntrl:]]`) in the regexes —
   supported by the PostgreSQL engine underneath, worth one smoke test.
3. `LicenseActivity` / `LicenseActivityType` composite keys — Semarchy takes
   a single PK, so the first spec column is the PK and the second is a plain
   attribute plus a uniqueness validation you may want to add.
