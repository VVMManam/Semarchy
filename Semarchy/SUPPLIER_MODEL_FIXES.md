# Supplier model fixes — aligned to ADPG_MDM_Data_Model_Customer&Supplier_V0.2

Validated with the bundled `sem-design` 2.0.1: `sem-design data-product build --data-product-folder src` → **Build successful**.
The validator checks names and SemQL syntax only. Nothing below has been deployed or run against data.

## Match and merge

| Entity | Change |
|---|---|
| SupplierLegalAccount | Every rule excludes non-trade (`NonTradeFlag='Y'`) and holding (`IsHolding`) accounts. MAT-01 and MAT-02 previously had no non-trade exclusion. |
| SupplierLegalAccount | MAT-06 (name key + country only) lowered from 96 to 90, so it becomes a steward suggestion instead of an auto-merge. The key strips LLC/LTD/FZE/FZCO, so "X LLC" and "X FZE" would otherwise merge. |
| SupplierBankAccount | MAT-05 (IBAN), MAT-04 (account + bank country) and MAT-13 (account name) now require the same supplier (`FID_Sgid`). Bank accounts of different suppliers no longer merge. |
| TaxRegistration | New `SameTaxIdUnderSameSupplier` (supplier + tax type + normalised number, 100). |
| Address | New `SameUsageAndAddressUnderSameSupplierSite` (100). |
| Contact | New `SameEmailUnderSameSupplierSite` and `SameVendorContactIdUnderSameSupplierSite` (100). |

## Enrichers (the match keys were never populated before)

| Enricher | Populates |
|---|---|
| `DeriveSupplierMatchKeys` | `TrnMatchKey` from `VATRegistrationNumber` (placeholders and short values ignored); `WebsiteDomain` from `Website`; `NameTokenKey` (first three name tokens sorted, the rest appended) |
| `ResolveRegistrationCountry` (new) | `FID_RegistrationCountry` from `TaxCountryCode`; AE fallback for a UAE emirate or a UAE TRN (`100…`, 15 digits) |
| `DetectLicensePlaceholder` (new, same rule as customer) | `LicenseIsPlaceholder`, `LicenseFormatValid`, `IsPrimaryLicense` |
| `DeriveGovernmentEntity` (new) | `IsGovernmentEntity` from supplier type, when the source does not send it |
| `SetSupplierLegalAccountId` (new, POST_CONSO) | `SupplierLegalAccountId` = golden key `Sgid` |
| `ResolveCurrency`, `ResolvePaymentTerm`, `ResolveRegistrationEmirate` | Re-enabled. They had been committed disabled; the identical lookups already run on Site and Bank Account. |
| `StandardizeNameMatchKey` | Now runs after `NameEnUpperCase` |
| Site `ResolveCurrency` / new `ResolveInvoiceCurrency` | Payment currency and invoice currency are resolved separately (previously one `COALESCE`) |
| Assignment `SupplierSiteAssignmentNormalize` | `RecordStatusCode` derived from `InactiveDate` (past date gives I) |

## Validations

| Entity | Change |
|---|---|
| SupplierLegalAccount | VAL-04 Supplier Type and VAL-05 Business Relationship are now mandatory as well as domain-checked. |
| SupplierLegalAccount | New: VAL-02 Account Status mandatory; VAL-03 Licence number mandatory. |
| SupplierLegalAccount | VAL-10 (licence dates): NULL-safe licence-type test. |
| SupplierLegalAccount | Currency, payment term and registration country "resolved" checks re-enabled. |
| SupplierLegalAccount | `FusionSupplierId` and `SupplierLegalAccountId` are no longer mandatory (model: N / generated). |
| SupplierSite | New: VAL-15 site code mandatory; VAL-17 site address mandatory; invoice currency resolved. |
| SupplierSite | VAL-54 "warning" disabled, because Semarchy has no warning severity and it would reject every new site. |
| SupplierSiteAssignment | VAL-56 "warning" disabled for the same reason. Withholding tax fields are no longer mandatory (model: N). |
| SupplierBankAccount | VAL-25 IBAN: real check (format, UAE = AE + 21 digits, mod-97 checksum). It used to pass any value not starting with two letters and two digits. |
| SupplierBankAccount | New VAL-26 to VAL-30: supplier, site, country, bank and branch name, account name and number mandatory. |

## Survivorship

- `SPEND_AUTHORIZED` is now tested on `BusinessRelationshipCode` (it was tested on `AccountStatusCode`, where it never occurs) in all three supplier rules.
- Every supplier rule ends with `CreationDate ASC`, the "oldest wins" tie-break its description promises.
- The `DefaultRule` of each supplier entity now ranks like the entity's main rule (Legal Account: the legal-identity rule). Reference codes therefore survive from the same record as the licence block.
- Site: primary pay site, then pay site, now rank first, as the rule description says.

## References and attributes

- New references: SupplierLegalAccount → Party (`Pgid`), → Party (`ParentPgid`, hierarchy), → PartyRole (`PartyRoleId`); Profile → SupplierLegalAccount; SupplierSite → Currency (`InvoiceCurrency`; the existing one is relabelled Payment Currency).
- `StartDateActive` changed from String to Date.
- `SiteCode` length increased from 50 to 240.
- Assignment `PrepaymentAccount`, `FutureDatedPaymentAccount` and `DistributionSet` lengths increased from 20 to 200.
- `SupplierValidationPending` action set disabled: it started the customer workflow and nothing used it.

## Deliberately not changed (decision needed or not possible)

1. **Primary key name.** The model calls the PK "Supplier Legal Account ID" and Sgid a String `SG000000001`. The build's generated PK is `Sgid` (numeric sequence, required for a fuzzy-matched entity) and every child FK targets it. Renaming would rewrite all references and forms. `SupplierLegalAccountId` now mirrors it instead.
2. **Truncated physical column names** (`..._COD`, `LICENSE_RECORD_CODE`, …): renaming orphans existing data.
3. **Columns longer than the model** (NameEn 255, site phone/fax 240, …) are kept. Shrinking risks truncation; the model's `RemitAdviceEmail` String(30) is too short for an email.
4. **`Pgid` is not made mandatory.** As on the customer side, the integration must populate it.
5. **`LicenseActivity_Sgid`** exists in the build but not in the model; it was left in place.
6. **`BicSwift` "derived from IBAN"**: a BIC cannot be derived from an IBAN without a bank directory.
7. **Workbook issues for the model owner**:
   - The Mapping (All) sheet is out of sync with the entity sheets.
   - Rules S-N1..S-N7, S-A1, S-I7, S-C1, S-L1, S-ST1 and S-BK1 are not defined.
   - VAL numbering clashes with the build.

## Check after first deploy

- New mandatory validations will flag existing records that lack the data (expect VAL-03 licence and VAL-17 site address counts). VAL-17 depends on the integration loading `FID_AddressName`; nothing resolves it from a name.
- `StartDateActive` String to Date: existing non-date values will fail the column change.
- Untested at runtime:
  - the lookup-plugin SQL;
  - `TO_NUMBER(…, REPEAT('9', 80))` in the IBAN check on PostgreSQL;
  - the POST_CONSO enricher reading `Sgid`.
