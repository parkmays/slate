# Git root and branches

## Canonical root

Use **this directory** (the one containing `Package.swift`, `packages/`, and `apps/desktop/`) as the Git repository root for SLATE. Initialize a remote here if you do not already have one:

```bash
git init
git remote add origin <url>
```

## “Merge all branches”

Merging unrelated branches (for example agent branches created in a different repository or in a parent home-directory Git repo) can introduce noise or conflicts. **Merge only branches that belong to this project’s remote**, using your normal review process (`main` / `develop` / feature branches).

If you previously used a different Git root by mistake, migrate history or re-clone into this layout rather than merging unrelated histories.
