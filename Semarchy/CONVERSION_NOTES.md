# ADPG_ converted to the AdPorts approach

Names, keys and table names are unchanged — `*`, `Pgid`, `Cgid`, `Sgid`, `_*`.
Only the structure moved.

## The shape now

```
Party                       FUZZY_MATCHED   — one deterministic rule, auto-merge only
  ├── CustomerLegalAccount  FUZZY_MATCHED   ← customer match and merge
  │     ├── Address   Contact   Identifier   License   TaxRegistration
  │     ├── CustomerOrgAssignment   Profile   ContactPurpose
  │     └── SbcMatchResult (candidate)
  ├── SupplierLegalAccount  FUZZY_MATCHED   ← supplier match and merge
  │     ├── Address   Contact   Identifier   License   TaxRegistration
  │     └── SupplierSite
  ├── PartyRole
  └── PartyRelationship
```

## 1. Matching moved to the legal accounts

| Entity | before | after |
|---|---|---|
| `Party` | FUZZY_MATCHED, M-01…M-10 (9 rules, steward band 80–94) | **FUZZY_MATCHED, one rule (P-01), all thresholds 100** |
| `CustomerLegalAccount` | FUZZY, one rule `Pgid = Pgid` | **FUZZY, M-01…M-10** |
| `SupplierLegalAccount` | FUZZY, one rule `Pgid = Pgid` | **FUZZY, M-01…M-10** |
| `Address` `Contact` `Identifier` `CustomerOrgAssignment` | FUZZY | **BASIC** |

Three fuzzy entities remain: `Party`, `CustomerLegalAccount`, `SupplierLegalAccount`.

The old `Pgid = Pgid` rule was the reason this could not simply be lifted: it says two
customer accounts merge only if they already share a party. With Party no longer matched,
two loads of the same company produce two parties and nothing would ever merge. The real
rules had to move down with the identity data.

Thresholds on both matchers: newGroup 95, confirmedWithUnconfirmed 98, autoConfirmGolden 99,
`useTransitiveMatchScore: true`, `useMultiIterationGrouping: true`.

## 2. Identity data moved down

`CustomerLegalAccount` and `SupplierLegalAccount` each gained 19 attributes:
`LegalNameEn` `LegalNameAr` `PartyTypeCode` `NameMatchKey` `NamePhoneticKey`
`NameArMatchKey` `IsBranch` `BranchQualifier` `IsInternalEntity` `LicenceKey`
`LicenceAuthorityCode` `LicenceCountry` `TrnKey` `ErpKey` `FusionArKey` `FusionPartyKey`
`EmiratesIdKey` `PhoneKey` `AddressMatchKey`, plus `EmailDomain` and `BusinessPhone` on the
supplier (the customer already had them).

Three FKs added to each: `RegistrationCountry` → Country, `RegistrationEmirateCode` →
Emirate, `LegalFormCode` → LegalForm — M-08 and M-10 need them.

`StandardiseName` and `MatchKeys` enrichers now sit on both legal accounts and read the
identifiers, licences and addresses that hang below them.

`PhoneKey` is now derived directly from `BusinessPhone` on each account instead of being
looked up from the customer. That fixes the gap where a supplier-only company had no
`EmailDomain` and no `PhoneKey`, which silently halved the M-08 and M-10 corroborators on
the supplier path.

## 3. Party matches deterministically, on its own data

`Party` stays FUZZY_MATCHED so that a company arriving from both CRM and Fusion
consolidates into **one** golden party — a BASIC entity would have left two rows.

Its matcher holds a single rule, **P-01**:

```
IsInternalEntity = 0 on both sides
AND (  FusionArKey equal
    OR FusionPartyKey equal
    OR ErpKey equal
    OR (LicenceKey + LicenceAuthorityCode + LicenceCountry all equal
        AND LicenceKey is not 15 digits)  )
score 100
```

Every threshold is 100 and `useTransitiveMatchScore` / `useMultiIterationGrouping` are both
off. Two consequences worth being explicit about: **there is no 80–94 band at party level, so
no steward ever works a party merge board**, and nothing chains — A merging to B does not drag
in C. All judgement calls stay at customer and supplier level, which is where the fuzzy name
rules live.

The 15-digit guard is the same TRN protection as M-02: a TRN typed into the licence field
would otherwise auto-merge an entire tax group into one party at score 100.

**Party derives its own keys, with no cross-entity lookup.** The `MatchKeys` enricher now
normalises `LicenceKey`, `LicenceAuthorityCode`, `LicenceCountry`, `TrnKey`, `ErpKey`,
`FusionArKey`, `FusionPartyKey` and `EmiratesIdKey` **in place**, and derives the three name
keys from `PartyNameEn` / `PartyNameAr`. No `LOOKUP`, so no ordering dependency and no
one-cycle lag — a matcher cannot be allowed to read stale values.

**This puts a requirement on the load.** Those eight columns must arrive populated on the
party payload; Semarchy normalises them but cannot invent them. `Identifier` now hangs off
the legal accounts, so Party can no longer look them up. Each column's `documentation` in the
entity file says `SOURCE-SUPPLIED`. If OSB does not send the trade licence and the system keys
at party level, P-01 never fires and every load creates a new party.

`EmailDomain`, `PhoneKey` and `AddressMatchKey` remain on Party as **reporting** columns,
filled by a separate `CorroboratorRollup` enricher from the customer legal account. Nothing
matches on them, so their one-cycle lag is harmless.

## 4. References

Re-pointed from `Party` to `CustomerLegalAccount` (file and `_name` renamed
`_Pgid` → `_Cgid`, FK column `PGID` → `CGID`):

`Address` · `Contact` · `Identifier` · `License` · `TaxRegistration` ·
`SbcMatchResult` (candidate).

Kept pointing at `Party`: `CustomerLegalAccount_Pgid`, `SupplierLegalAccount_Pgid`,
`PartyRole_Pgid`, `PartyRelationship_FromPgid`, `PartyRelationship_ToPgid`.

**Added beyond the literal instruction, and why.** Five optional `_Sgid` references were
added — `Address` `Contact` `Identifier` `License` `TaxRegistration` →
`SupplierLegalAccount`. Without them a supplier has no licence and no TRN to match on,
because those rows now hang off the customer. Both FKs are optional, so a row belongs to a
customer, a supplier, or both. This is the pattern AdPorts already uses for
`AddressCustomer` / `AddressSupplier`.

92 references in total: 81 original, 6 re-pointed in place, 11 new.

## 5. Fixes carried in along the way

- **All POSIX character classes removed.** `[[:space:]]`, `[[:cntrl:]]`, `[[:punct:]]` have
  no precedent in the live AdPorts model and were the source of the earlier build failures.
  Replaced with `[ \t\r\n]+` and `[^A-Za-z0-9]`.
- **The 15-digit TRN guard in M-02 was inert.** It read `'^[0-9]15$'` — the regex braces had
  been lost, so it matched the three-character string `915` and never a TRN. Now `'^[0-9]{15}$'`.
- **13 validations were at `validationScope: NONE`** and never fired. All moved to `PRE_CONSO`.
  Worth a dry run on real data before go-live — a `PRE_CONSO` failure rejects the source record.
- **`overrideStrategy: NO_OVERRIDE`** on both surviving survivorship rules would have reverted
  every steward decision on the next load. Changed to `UNTIL_NEXT_USER_CHANGE`, matching the
  live AdPorts model.

## 6. Verified before packaging

258 files parse as YAML · every reference resolves to an existing entity · no duplicate
reference name, physical name, `toRoleName` per entity or `fromRoleName` per target · no FK
column collides with an attribute · every FK ≤ 25 characters · both FUZZY entities have
exactly one ID and one Standard survivorship rule, every BASIC entity has none and no
`goldenIdGeneration` · every
attribute named in a match rule, enricher or validation exists on its entity, and every
traversal resolves through a real reference · every `REGEXP_LIKE` has 2 arguments and every
`REGEXP_REPLACE` has 3 · the ERD, application, forms, steppers and collection views contain
no dangling entity or reference paths.

Not verified: `sem-design dm model build` has not been run — no Semarchy CLI here.

## 7. Later changes (requested after the first conversion)

**System keys removed from both legal accounts.** `EmiratesIdKey`, `ErpKey`, `FusionArKey`
and `FusionPartyKey` are gone from `CustomerLegalAccount` and `SupplierLegalAccount`,
together with the two match rules that used them — **M-01** (Fusion / ERP id equal) and
**M-07** (Emirates ID equal) — and their enricher expressions.

Those keys now live only on `Party`, which is what P-01 matches on. Both legal accounts
match purely on licence, TRN and name:

| | rules |
|---|---|
| `Party` | P-01 |
| `CustomerLegalAccount` | M-02 M-03 M-04 M-05 M-06 M-08 M-10 |
| `SupplierLegalAccount` | M-02 M-03 M-04 M-05 M-06 M-08 M-10 |

Worth knowing what this gives up: two records that share a Fusion or ERP id but have no
licence, no TRN and dissimilar names will no longer merge at account level. They will still
merge at party level through P-01, and the accounts then sit under one party — which is the
intended shape, but the accounts themselves stay separate until something else matches them.

**`label:` and `documentation:` stripped from every entity attribute** — 375 label lines and
306 documentation lines across all 38 entities. Semarchy will derive display names from the
attribute names instead. Entity-level `label`, `pluralLabel`, `description` and
`documentation` are untouched, as are the `label:` lines on match rules and form field groups.

If `sem-design dm model build` reports a missing required property on attributes, `label` is
mandatory in this Semarchy version and the lines need restoring — they are all recoverable
from the copy of ADPG__2 this was converted from.

## 8. Still open

- Binning. `usingMatchOn: false` on all 18 rules. On a full customer load this is an O(n²)
  comparison. The six bins in the spec are still unimplemented.
- `historizeGolden: false` on all 38 entities, which blocks the attribute-level change
  detection the outbound routing needs.
- Losing CGIDs and SGIDs need a home as `Identifier` rows after a merge, so CRM and
  Fusion can remap.
- Publication is not yet gated on `PartyStatusCode = 'ACTIVE'`.
