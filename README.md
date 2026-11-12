# Git Review Agent

An agent that reviews all git actions (commits) in a repository and a dashboard to visualize the results.

## Prerequisites

- **Git** (installed and on `PATH`, or at `C:\Program Files\Git\bin\git.exe`)
- **PowerShell 5.1+** (included with Windows)
- **Node.js** (optional, only if you want to run a local server for the dashboard; the dashboard works standalone by opening `index.html`)

### Installing Git and Node.js (Windows)

If they aren't already on your `PATH`:

```powershell
winget install Git.Git -s winget --accept-package-agreements --accept-source-agreements
winget install OpenJS.NodeJS.LTS -s winget --accept-package-agreements --accept-source-agreements
```

Then add them to your current session's `PATH`:

```powershell
$env:PATH += ";C:\Program Files\Git\bin;C:\Program Files\nodejs"
```

Or install and log out/in so they're on `PATH` permanently.

## Project structure

```
git-review-agent/
├── README.md
├── src/
│   ├── GitReviewAgent.psm1   # agent module (core logic)
│   └── GitReviewAgent.ps1    # entry point script
├── dashboard/
│   ├── index.html            # dashboard UI
│   ├── app.js                # dashboard logic
│   └── style.css             # dashboard styles
└── tests/
```

## Usage

Review the latest 100 commits in the current repo and print JSON:

```powershell
.\src\GitReviewAgent.ps1
```

Review with summary output to console:

```powershell
.\src\GitReviewAgent.ps1 -Summary
```

Export review to a JSON file:

```powershell
.\src\GitReviewAgent.ps1 -Export .\review-report.json -Summary
```

Review a specific repo path:

```powershell
.\src\GitReviewAgent.ps1 -Path C:\path\to\repo -MaxCount 200 -AllBranches
```

## Dashboard

1. Run the agent with `-Export` to produce `review-report.json`.
2. Open `dashboard/index.html` in a browser.
3. Click "Load review file" and select `review-report.json`.
4. Filter by severity, search author/subject, toggle passed reviews.

The "Open repo" link opens the repository folder in your file explorer.

## How reviews work

Each commit is checked against these rules:

- Subject length must not exceed 50 characters.
- Commit type prefix (before `:`) should be one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
- Forbidden words in subject: `fix`, `fixes`, `fixed`, `temp`, `todo`, `hack`, `quick`, `wip`, `asap`.
- Long subjects without a body are flagged as info.

Severity is `Error`, `Warning`, or `Info` based on the highest-severity issue found.

## Extending

Edit `src/GitReviewAgent.psm1` to add review rules in `$script:ReviewRules` or new `Test-*` functions called from `Review-GitAction`.
