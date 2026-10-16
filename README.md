# ADPG Master Data Management (MDM)

## 1. Project Overview

This project implements Master Data Management (MDM) using **Semarchy xDM**. It manages Party, Customer, Supplier, and related business information in a centralized data model.

The main objective is to maintain accurate, consistent, and trusted master data by identifying duplicate records, applying data-quality rules, and creating Golden Records.

## 2. Project Objectives

- Maintain clean and consistent master data.
- Identify duplicate Party, Customer, and Supplier records.
- Apply ID matching and fuzzy matching rules.
- Validate and standardize business data.
- Consolidate eligible duplicate records into trusted Golden Records.
- Apply survivorship rules to select appropriate attribute values.
- Manage relationships between business entities.
- Automate model build, validation, and deployment using Azure DevOps CI/CD.

## 3. Key Business Entities

| Entity | Purpose |
|---|---|
| Party | Maintains common party information. |
| CustomerLegalAccount | Maintains customer legal account information. |
| SupplierLegalAccount | Maintains supplier legal account information. |
| Address | Stores address information. |
| Contact | Stores contact information. |
| Identifier | Maintains identification details. |
| CustomerGolden | Represents consolidated customer information. |
| PartyRole | Maintains roles associated with a party. |
| PartyRelationship | Maintains relationships between parties. |

The model also includes reference data such as Country, Currency, BusinessUnit, and other supporting entities.

## 4. Main MDM Components

### Entities and Attributes
Entities represent business objects, and attributes represent their individual fields.

### References
References connect related entities. For example, a Customer Legal Account can be linked to a Party.

### Validations
Validations check whether data satisfies configured business rules, such as mandatory fields and valid identifier formats.

### Enrichers
Enrichers standardize, derive, or calculate attribute values. Examples include normalizing contact details and preparing keys used for matching.

### Match and Merge
Matching identifies records that may represent the same business object. Eligible duplicates are then consolidated according to the configured merge rules.

- **ID matching:** Identifies records using matching identifiers or key values.
- **Fuzzy matching:** Identifies records with similar information, such as company names, licences, or tax registration details.

### Golden Records
Golden Records provide trusted consolidated information after applicable matching, merging, and survivorship processing.

### Survivorship Rules
Survivorship rules determine which attribute values should be retained in the consolidated record.

### User Interface Components
The model includes Forms, Collection Views, Display Cards, Business Views, Steppers, and Action Sets to support viewing and managing business data.

## 5. Project Structure

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
│       └── ADPGModel.DataProductProfile.seml
├── ci-cd/
│   ├── azure-pipelines.yml
│   ├── config/
│   ├── scripts/
│   └── templates/
├── resources/
├── ADPG-MDM.code-workspace
├── README_GENERATED.md
└── CONVERSION_NOTES.md
```

### Important Folders

- **src/DataProject:** Contains the Semarchy data model and configuration files.
- **entities:** Contains entity definitions and their related configurations.
- **applications:** Contains Semarchy application definitions.
- **references:** Defines relationships between entities.
- **ci-cd:** Contains Azure DevOps pipeline definitions, environment configurations, scripts, and deployment templates.
- **resources:** Contains supporting resources, including image libraries.

## 6. Technology Stack

- Semarchy xDM
- Semarchy SemQL
- Git and GitHub
- Visual Studio Code
- Azure DevOps Pipelines
- PowerShell

## 7. CI/CD Workflow

The repository contains an Azure DevOps pipeline for building, validating, and deploying the Semarchy model.

1. The pipeline builds and validates the model.
2. The pipeline can deploy to the Development environment.
3. The pipeline can deploy to the Test environment.
4. Production deployment requires approval and is restricted to the main branch.

The pipeline is manually triggered, and selected environments can be deployed independently after the build stage.

Environment configuration is maintained under `ci-cd/config/`.

## 8. Git Collaboration Workflow

The team uses Git and GitHub to maintain a shared version of the project.

1. Vishnu uploads the initial project files and pushes them to GitHub.
2. Mahesh pulls the latest code and adds this README.md file.
3. Lalithya pulls the latest code and adds the Documents folder.
4. Each team member commits and pushes their changes to the shared branch.
5. All team members pull the latest changes to synchronize their local repositories.

Before starting new work, team members should check their local changes and pull the latest shared branch.

## 9. Expected Outcome

The project provides a structured approach to managing Party, Customer, Supplier, and related master data. It applies data-quality rules, matching and merge configurations, survivorship rules, and Golden Record processing to improve data consistency and reliability.

The Azure DevOps pipeline supports controlled deployment of the Semarchy model across Development, Test, and Production environments.

## 10. Conclusion

This ADPG MDM project combines Semarchy xDM data modeling, data-quality configurations, duplicate detection, record consolidation, and CI/CD automation to support reliable master data management.