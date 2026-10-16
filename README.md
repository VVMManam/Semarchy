# Semarchy xDM – MDM Project

## Project Overview

This repository contains the Semarchy xDM Master Data Management (MDM) project. It includes model definitions and configuration files used to manage master data, such as entities, references, enrichers, validations, forms, business views, collections, action sets, and applications.

The repository also includes supporting project resources and CI/CD configuration files for working with the model.

## Project Structure

```text
Semarchy/
├── src/
│   └── DataProject/       # Semarchy model definitions and configuration
│       ├── applications/  # Application definitions
│       ├── entities/      # Entity definitions and related components
│       ├── references/    # Reference relationships
│       └── ...            # Other model components
├── ci-cd/                 # CI/CD pipeline, scripts, templates, and environment config
├── resources/             # Supporting resources
├── out/                   # Generated/exported project output
├── README.md              # Project overview and team workflow
└── ...                    # Other project notes and configuration files
```

## Main Areas

- **Entities:** Define the master data records managed by the model.
- **References:** Define relationships between entities and reference data.
- **Validations:** Define checks to help maintain data quality.
- **Enrichers:** Define rules for deriving, standardizing, or updating data.
- **Match and merge:** Support identifying duplicate records and consolidating them where configured.
- **Forms, collections, and business views:** Configure how users view and work with data.
- **Applications and action sets:** Configure user-facing applications and available actions.
- **CI/CD:** Contains Azure DevOps pipeline configuration, scripts, templates, and environment settings.

## Team Responsibilities

| Team member | Responsibility |
|---|---|
| Vishnu | Extract the project ZIP, place the project files in the repository, and commit and push the files to GitHub. |
| Mahesh | Pull the latest repository changes, create or update this `README.md`, and commit and push the changes. |
| Lalithya | Pull the latest repository changes, add the `Documents/` folder with the project documentation, and commit and push the changes. |
| All team members | Pull the latest changes after the team commits so everyone works with the same repository version. |

## Git Workflow

Use the following workflow to keep the team synchronized. Run commands from the project repository folder.

### 1. Get the latest changes

```bash
git switch main
git pull origin main
```

If your team uses a branch other than `main`, replace `main` with the correct branch name.

### 2. Make your assigned changes

- Vishnu: add the extracted project files.
- Mahesh: add or update `README.md`.
- Lalithya: add the `Documents/` folder and its documentation files.

### 3. Stage and commit your changes

```bash
git status
git add .
git commit -m "Describe your changes"
```

Use a meaningful commit message, such as `Add project README` or `Add project documents`.

### 4. Push your changes to GitHub

```bash
git push origin main
```

### 5. Pull again after teammates push

Before continuing your next task, synchronize your local repository:

```bash
git pull origin main
```

If Git reports a merge conflict, resolve the conflict, save the files, then stage and commit the resolution before pushing.

## Important Notes

- Always run Git commands from the correct repository folder.
- Pull the latest changes before starting work and before making a new commit when teammates may have pushed updates.
- Do not overwrite or delete another team member's changes unintentionally.
- Keep project documentation inside `Documents/` and update it when project details change.
- Do not commit passwords, access tokens, private keys, or other secrets.

## Goal

The goal of this team workflow is to keep the Semarchy project, README, and documentation synchronized in one GitHub repository so that Vishnu, Mahesh, and Lalithya can work from the same latest version.
