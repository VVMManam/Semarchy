# Semarchy xDM – Master Data Management (MDM)

## 1. Project Overview

This project implements Master Data Management (MDM) for **AD Ports Group (ADPG)** using **Semarchy xDM**. It manages Party, Customer, Supplier, and related business information through a centralized data model (the "ADPG Party Hub").

The main objective is to maintain accurate, consistent, and trusted master data by identifying duplicate records, applying data-quality rules, and creating Golden Records.

## 2. Project Objectives

- Maintain clean and consistent master data.
- Identify duplicate Party, Customer, and Supplier records.
- Apply ID matching and fuzzy matching rules.
- Validate and standardize business data.
- Consolidate eligible duplicate records into trusted Golden Records.
- Apply survivorship rules to select appropriate attribute values.
- Manage relationships between business entities.
- Support model validation and deployment to Dev, Test, and Prod through an Azure DevOps CI/CD pipeline.

## 3. Key Business Entities

| Entity | Purpose |
|---|---|
| Party | Maintains common party information (one record per real-world organisation or person). |
| CustomerLegalAccount | Maintains customer legal account information. |
| SupplierLegalAccount | Maintains supplier legal account information. |
| SupplierSite | Maintains supplier site details. |
| SupplierSiteAssignment | Maintains the business units a supplier site is assigned to. |
| SupplierBankAccount | Maintains supplier bank account details. |
| Address | Stores address information. |
| Contact | Stores contact information. |
| Identifier | Maintains identification details. |
| TaxRegistration | Maintains tax registration (TRN) details. |
| CustomerGolden | Represents consolidated customer information. |
| PartyRole | Maintains roles associated with a party. |
| PartyRelationship | Maintains relationships between parties. |

The model also includes reference data such as Country, Emirate, Currency, PaymentTerm, BusinessUnit, Cluster, LicenseType, and IssuingAuthority, along with workflow and audit entities such as ChangeRequest, MergeApprovalLogs, and IntegrationAudit.

## 4. Main MDM Components

### Entities and Attributes

Entities represent business objects, and attributes represent their individual fields.

### References

References connect related entities. For example, a Customer Legal Account is linked to a Party through `Pgid`.

### Validations

Validations check whether data satisfies configured business rules, such as mandatory fields, licence expiry, IBAN format, and valid identifier formats.

### Enrichers

Enrichers standardize, derive, or calculate attribute values. Examples include normalizing names, phone numbers and e-mail addresses, resolving reference codes, and preparing the keys used for matching.

### Match and Merge

Matching identifies records that may represent the same business object. Eligible duplicate records are then consolidated according to configured merge rules.

- **ID Matching:** Identifies records using matching identifiers or key values, such as licence number, issuing authority, and country.
- **Fuzzy Matching:** Identifies records with similar information, such as company names, licence details, or tax registration information.

Match rules are defined on the fuzzy-matched entities. The main ones are:

| Entity | Rules |
|---|---|
| Party | P01 to P04, PM_A1 |
| CustomerLegalAccount | MR01 to MR11 |
| SupplierLegalAccount | MAT01 to MAT14 |

### Golden Records

Golden Records provide trusted consolidated information after applicable matching, merging, and survivorship processing.

### Survivorship Rules

Survivorship rules determine which attribute values should be retained in the consolidated record.

### User Interface Components

The model includes Forms, Collection Views, Display Cards, Business Views, Steppers, and Action Sets to support viewing and managing business data. These are grouped into the following applications: Party Application, Customer Hub, Customer Administration, Supplier Hub, Supplier Administration, Group Reference Data, and Party360.

### Workflows and Jobs

- **Workflows:** Change Request approval and Customer Validation.
- **Certification Jobs:** Load jobs that run enrichment, validation, matching, and consolidation for each entity.

## 5. Project Structure

The repository contains Semarchy xDM model definitions and supporting configuration files.

```text
Semarchy/
├── src/
│   └── DataProject/
│       ├── applications/
│       ├── entities/
│       │   ├── Party/
│       │   ├── CustomerLegalAccount/
│       │   ├── SupplierLegalAccount/
│       │   ├── Address/
│       │   ├── Contact/
│       │   └── ...
│       ├── references/
│       ├── List_of_values/
│       ├── workflows/
│       ├── ModelJobs/
│       ├── named_queries/
│       ├── model_privilage_grant/
│       └── Model_Diagram/
├── ci-cd/
│   ├── config/
│   ├── scripts/
│   ├── templates/
│   └── tools/
├── resources/
├── ADPG-MDM.code-workspace
└── README.md
```

*Note: This is a simplified structure. Each entity folder can also contain forms, collection_views, display_cards, business_views, steppers, action_sets, enrichers, validations, and survivorship_rules.*

### Important Folders

- **src/DataProject:** Contains the Semarchy data model and configuration files.
- **entities:** Contains entity definitions and related configurations.
- **applications:** Contains application definitions.
- **references:** Defines relationships between entities.
- **List_of_values:** Contains lists of values (status, type, and code lists).
- **workflows / ModelJobs:** Contain workflow and certification job definitions.
- **model_privilage_grant:** Contains role privilege grants.
- **ci-cd:** Contains the Azure DevOps pipeline, per-environment configuration, PowerShell scripts, templates, and the Semarchy Design CLI package.
- **resources:** Contains supporting project resources such as image libraries.

## 6. Technology Stack

- Semarchy xDM / Semarchy Data Platform
- SemQL
- Semarchy Design CLI (`sem-design`) 2.0.1
- Git and Azure DevOps
- Visual Studio Code (open `ADPG-MDM.code-workspace`)
- PowerShell and Node.js 20.x for the CI/CD scripts

## 7. Model Development and Deployment Workflow

1. Define entities, attributes, and references.
2. Configure validations to check data quality.
3. Configure enrichers to standardize or calculate attribute values.
4. Define matching rules to identify potential duplicates.
5. Configure merge policies to consolidate eligible records.
6. Apply survivorship rules to select attribute values.
7. Generate trusted Golden Records through the configured MDM processing.
8. Configure Forms, Collections, and Business Views to manage and display data.
9. Validate the model: `sem-design data-product build --data-product-folder src`
10. Deploy using the Azure DevOps pipeline **ADPorts-MDM-Build**. Run it manually, tick Dev, Test, and/or Prod, and approve the Prod stage (Prod deploys from `main` only).

| Environment | Instance |
|---|---|
| Dev | https://adpg-mdm-dev.eu.semarchy.net |
| Test | https://adpg-mdm-test.eu.semarchy.net |
| Prod | https://adpg-mdm.eu.semarchy.net |

See `ci-cd/README.md` for the full pipeline setup and troubleshooting guide.

## 8. Git Collaboration Workflow

The team uses Git to maintain a shared version of the Semarchy project.

1. Vishnu uploads the initial project files and pushes them to the repository.
2. Mahesh pulls the latest code and adds this README.md file.
3. Lalithya pulls the latest code and adds the Documents folder.
4. Each team member commits and pushes their changes to the shared branch.
5. All team members pull the latest changes to synchronize their local repositories.

Before starting new work, team members should check their local changes and pull the latest shared branch.

## 9. Expected Outcome

The project provides a structured approach to managing Party, Customer, Supplier, and related master data. It applies data-quality rules, matching and merge configurations, survivorship rules, and Golden Record processing to improve data consistency and reliability.

## 10. Conclusion

This Semarchy xDM MDM project combines data modeling, data-quality configurations, duplicate detection, record consolidation, and master data management capabilities to support accurate, consistent, and trusted business information for AD Ports Group.
