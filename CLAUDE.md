# CLAUDE.md — hoopR-kp-data Development Guide

## Repo Overview

`hoopR-kp-data` is the R-side data aggregation repo that scrapes Ken Pomeroy
(<https://kenpom.com>) men's college basketball team pages, persists the
parsed output (coaches, players, team schedules, depth charts) to disk under
`data/`, and commits the results back to this repo. It is the cache of
KenPom-derived season tables consumed by analysts and downstream tooling.

The companion R package providing the actual scraping primitives (`login()`,
`teams_links`, etc.) is `hoopR` (the `kenpomR`-flavoured login helpers were
folded into hoopR). Scraping KenPom requires a valid paid KenPom subscription
— pass credentials via the `KP_USER` / `KP_PW` environment variables.

- **Package name (DESCRIPTION)**: `hoopR.kenpom`
- **License**: CC BY 4.0
- **R Requirement**: >= 4.0.0

## Pipeline Position

```
kenpom.com --[R rvest scrape]--> hoopR-kp-data [HERE]
                                       | git commit
                                       v
                                committed CSV / RDS / parquet under data/
                                       |
                                       v
                          analysts / downstream consumers
```

Unlike the ESPN-side hoopR pipeline (`hoopR-mbb-raw` -> `hoopR-mbb-data` ->
sportsdataverse-data releases -> `hoopR`), the KenPom flow stops here: the
parsed tables are committed directly into this repo's `data/` tree rather
than uploaded as GitHub Releases on `sportsdataverse-data`. KenPom is a
paywalled source, so the data is not redistributed via the public release
channel.

## Build & Development Commands

The two entry points are `R/team_page_calls.R` (one-shot scrape for a
single year, no commit) and `R/update.R` (scrape + git commit + push, the
CI-style flow). Both call `gather_team_pages()` defined in `R/pull_team_page.R`.

```sh
# Single-year scrape (no commit). Logs into KenPom, walks every team,
# writes data/coaches/, data/players/, data/team_schedules/,
# data/depth_charts/ for the requested year.
Rscript R/team_page_calls.R

# Update flow (scrape + commit + push). Same scrape, then bundles
# everything under data/* into one commit and pushes to main.
Rscript R/update.R

# Refresh the team-link index for every season back to 2002.
# Writes data/kp_team_info.csv + data/teams_links.rda (used by gather_team_pages).
Rscript R/pull_team_links.R
```

`gather_team_pages(year, file_path)` is the core helper — it iterates the
team list in `hoopR::teams_links` filtered to `year`, scrapes the per-team
KenPom page (`https://kenpom.com/team.php?team=<slug>&y=<year>`), and
appends rows into per-year data frames before persisting them.

### Environment Variables

| Var       | Used By                          | Description                          |
|-----------|----------------------------------|--------------------------------------|
| `KP_USER` | `R/update.R`, `hoopR::login()`   | KenPom account email                 |
| `KP_PW`   | `R/update.R`, `hoopR::login()`   | KenPom account password              |
| `GITHUB_PAT` / `SDV_GH_TOKEN` | `.github/workflows/update_kenpom.yml`, `R/0001_push_existing_release_data.R` | GitHub token for commits / piggyback uploads |

## Repo Layout

```
R/
  pull_team_page.R                   # gather_team_pages() — core scraping loop
  pull_team_links.R                  # Rebuilds the KenPom team-index for 2002..most_recent
  team_page_calls.R                  # Single-year scrape entry (no commit)
  update.R                           # Scrape + commit + push entry
  0000_create_hoopR_releases_init.R  # One-off: bootstrap sportsdataverse-data release tags
  0001_push_existing_release_data.R  # One-off: backfill existing ESPN mbb data into releases
data/
  coaches.csv                        # All-years master (one row per team-year)
  coaches/coaches_{year}.{csv,parquet,rds}
  players.csv                        # All-years master roster
  players/{csv,}players_{year}.{parquet,rds}
  team_schedules.csv                 # All-years master schedule
  team_schedules/{csv,}team_schedules_{year}.{parquet,rds}
  year_depth1.csv                    # All-years team depth chart "table 1"
  year_depth2.csv                    # All-years team depth chart "table 2"
  depth_charts/{csv,}year_depth1_{year}.{parquet,rds}
  depth_charts/{csv,}year_depth2_{year}.{parquet,rds}
  geocoded_venues.csv                # Venue geocoding lookup
.github/workflows/
  update_kenpom.yml                  # Manual-dispatch KenPom team-links refresh
```

The per-year `csv/`, `parquet/`, and `rds/` artifacts under each dataset
folder are the canonical persisted form. The top-level `coaches.csv`,
`players.csv`, `team_schedules.csv`, `year_depth1.csv`, `year_depth2.csv`
are the all-years aggregates rebuilt periodically.

## Code Conventions

- **Dependencies**: `rvest` + `xml2` for HTML scraping, `dplyr` / `tidyr` /
  `stringr` for tidy pipelines, `data.table` + `arrow` + `qs` for the
  fast persistence side, `glue` for path building. See `DESCRIPTION`.
- **Authentication**: always go through `hoopR::login(Sys.getenv("kp_user"), Sys.getenv("kp_pw"))`
  (or the env-var-only `hoopR::login()` form). Never hardcode credentials.
- **Session reuse**: `gather_team_pages()` creates one logged-in `browser`
  session and uses `rvest::session_jump_to()` for every team page — do not
  re-login per team. KenPom rate-limits aggressive logins.
- **Team list source of truth**: `hoopR::teams_links` (regenerated via
  `R/pull_team_links.R`). Do not maintain a parallel team list here.
- **Per-team failures**: a scrape failure for one team should not abort
  the year. Wrap fragile `rvest::html_nodes()` accesses in `tryCatch` /
  defensive checks when extending the parser.
- **Output paths**: keep the `data/<dataset>/<dataset>_<year>.{csv,parquet,rds}`
  shape. Downstream tooling assumes this layout.

## Daily / Update Workflow

`.github/workflows/update_kenpom.yml` is a manual-dispatch workflow
(`workflow_dispatch` only — no cron yet) that sets up R, installs
`sportsdataverse/hoopR`, `sportsdataverse/sportsdataverse-data`, and
`ropensci/piggyback`, and runs the scrape under `KP_USER` / `KP_PW`
secrets plus `SDV_GH_TOKEN` for commit auth. When/if cron cadence is
added, mirror the in-season windows used by `hoopR-mbb-data/daily_mbb.yml`.

The shell convenience `daily_basketball_scraper.sh` is `.gitignore`d —
local development only.

## KenPom-Specific Gotchas

- **Subscription required**: every CI run needs a valid `KP_USER` /
  `KP_PW` pair. There is no public-data fallback. Expect the workflow to
  fail with a `login()` error if the credentials lapse.
- **HTML schema drift**: KenPom occasionally rearranges per-team page
  tables. The selectors in `R/pull_team_page.R` (`.coach`, schedule
  table, etc.) are positional — verify them after any KenPom site
  redesign.
- **Year coverage**: KenPom data starts at 2002. `gather_team_pages()`
  asserts `year >= 2002`. Older seasons must be added upstream at KenPom
  first; nothing this repo can do about it.
- **Team-name mismatch**: a team name not present in `hoopR::teams_links`
  for the requested year will trigger `assertthat::assert_that()` and
  abort. Rebuild the team index via `R/pull_team_links.R` first when a
  new season starts.
- **`hoopR:::login`** in `R/pull_team_page.R` uses the unexported helper.
  If `hoopR` ever renames or removes it, update both the call site and
  `R/update.R`.
- **Data redistribution**: KenPom content is proprietary. Even though
  this repo carries CC BY 4.0 metadata, the underlying data is not
  freely redistributable — the repo itself should remain private to
  authorized SportsDataverse collaborators.

## Cross-Repo References

- The R package providing scraping primitives (`hoopR::login()`,
  `hoopR::teams_links`, `hoopR::most_recent_mbb_season()`):
  <https://github.com/sportsdataverse/hoopR>
- Sister men's basketball ESPN pipeline:
  <https://github.com/sportsdataverse/hoopR-mbb-raw> and
  <https://github.com/sportsdataverse/hoopR-mbb-data>
- Companion NBA data repo: <https://github.com/sportsdataverse/hoopR-nba-data>
- Shared SportsDataverse conventions: <https://github.com/sportsdataverse/wehoop/blob/main/CLAUDE.md>

## Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scrape): capture KenPom efficiency margin column on team page
fix(parse): handle teams with missing depth chart row in 2024
chore(data): refresh coaches/coaches_2025.csv
ci: wire KP_USER/KP_PW secrets into update_kenpom.yml
```

Daily/season data refresh commits should use a stable, parseable subject —
the convention across SportsDataverse data repos is one umbrella commit per
update run rather than per-file commits. Keep the year and dataset in the
subject for easy log scanning.

**Important: Never include AI agents or assistants (e.g., Claude, Copilot, Cursor, GPT, Gemini) as co-authors on commits.** Omit all `Co-Authored-By` trailers referencing AI tools. This applies whether the change was generated, refactored, or reviewed with AI assistance — the human author is the sole attributable contributor.
