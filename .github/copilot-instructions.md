# hoopR-kp-data Copilot Instructions

## Project Context

This repo is the R-side KenPom data aggregation stage for SportsDataverse
men's college basketball. It logs into <https://kenpom.com> with a paid
account, walks every team page for a given season, parses coaches,
players, team schedules, and depth charts, and commits the resulting
CSV / parquet / RDS files under `data/` back to `main`.

The DESCRIPTION ships as `hoopR.kenpom` (license CC BY 4.0). Scraping
primitives (`login()`, `teams_links`, `most_recent_mbb_season()`) live
in the upstream R package <https://github.com/sportsdataverse/hoopR>.

Pipeline: `kenpom.com -> hoopR-kp-data [HERE] (data/ committed) -> analysts / downstream tooling`.

Unlike the ESPN-side hoopR pipeline, parsed KenPom data is **not**
republished to `sportsdataverse-data` releases — KenPom content is
paywalled and not freely redistributable. Output stays in this repo's
`data/` tree.

## Repository Workflow

- Branch from `main`; `main` is the default and release branch.
- The scrape entry points are `R/team_page_calls.R` (one-shot, no commit)
  and `R/update.R` (scrape + commit + push to `main`).
- Team-link index lives upstream in `hoopR::teams_links`. Rebuild it via
  `Rscript R/pull_team_links.R` whenever a new season starts.
- The single CI workflow is `.github/workflows/update_kenpom.yml`
  (manual `workflow_dispatch` only — no cron yet).
- Do not commit credentials. `KP_USER` / `KP_PW` flow through env vars /
  GitHub secrets; `SDV_GH_TOKEN` (or `GITHUB_PAT`) handles commit auth.

## Build & Development Commands

```sh
# Single-year scrape (no commit). Writes data/coaches/, data/players/,
# data/team_schedules/, data/depth_charts/ for the requested year.
Rscript R/team_page_calls.R

# Scrape + commit + push to main. Same scrape, then bundles data/* into
# one commit message: "Updated Team Pages <ts> using kenpomR version X.Y.Z".
Rscript R/update.R

# Refresh hoopR::teams_links for seasons 2002..most_recent_mbb_season().
# Writes data/kp_team_info.csv (and updates the R data object on disk).
Rscript R/pull_team_links.R
```

Outputs the scrape writes under `data/`:

- `data/coaches/coaches_{year}.{csv,parquet,rds}` (and `data/coaches.csv` aggregate)
- `data/players/players_{year}.{parquet,rds}` (and `data/players.csv` aggregate)
- `data/team_schedules/team_schedules_{year}.{parquet,rds}` (+ `team_schedules.csv` aggregate)
- `data/depth_charts/year_depth1_{year}.{parquet,rds}` and `year_depth2_{year}.{parquet,rds}`
  (+ `year_depth1.csv` / `year_depth2.csv` aggregates)
- `data/geocoded_venues.csv` — venue lookup, refreshed less often

## Code Style

- Follow tidyverse style: `snake_case`, 2-space indent, pipe-first.
- HTML extraction: `rvest::session_jump_to()` + `xml2::read_html()` +
  `rvest::html_nodes()` / `html_elements()`. Reuse the single logged-in
  `browser` session — do not re-`login()` per team.
- Tidy pipelines: `dplyr::mutate()` / `select()` / `bind_rows()`,
  `stringr::str_extract()` / `str_remove()` for slug parsing,
  `tidyr::spread()` (legacy) where the scraping code already uses it.
- Persistence: `data.table::fwrite()` for CSV, `arrow::write_parquet()`
  for parquet, `saveRDS()` for RDS. Keep all three formats per dataset.
- Naming: `gather_<thing>_pages()` for top-level scraping helpers,
  `pull_<thing>()` for narrower fetch helpers.
- Never hardcode credentials. Always `hoopR::login(Sys.getenv("kp_user"), Sys.getenv("kp_pw"))`.

## KenPom Gotchas

- A valid paid KenPom subscription is required for every CI run; the
  scrape will hard-fail at `hoopR::login()` if `KP_USER` / `KP_PW`
  lapse.
- KenPom data starts at 2002. `gather_team_pages()` asserts `year >= 2002`.
- The per-team page parser uses positional selectors (`.coach`, schedule
  table, depth tables). Verify them after any KenPom redesign.
- Team-name drift: a team missing from `hoopR::teams_links[year=]` will
  trip an `assertthat::assert_that()` and abort the run. Refresh the
  team index first (`Rscript R/pull_team_links.R`).
- KenPom content is proprietary. Even though DESCRIPTION says CC BY 4.0,
  the scraped data is not freely redistributable.

## Cross-Repo References

- Scraping primitives (upstream): <https://github.com/sportsdataverse/hoopR>
- Sister ESPN MBB pipeline: <https://github.com/sportsdataverse/hoopR-mbb-raw> and <https://github.com/sportsdataverse/hoopR-mbb-data>
- Companion NBA repo: <https://github.com/sportsdataverse/hoopR-nba-data>
- Shared SportsDataverse conventions: <https://github.com/sportsdataverse/wehoop/blob/main/CLAUDE.md>

## Conventional Commits

Use: `type(scope): description`. Common types: `feat`, `fix`, `chore`,
`ci`, `docs`, `refactor`, `data`. Examples:

```
feat(scrape): add KenPom efficiency margin column to team page parser
fix(parse): handle missing depth-chart row for 2024 short rosters
chore(data): refresh coaches/coaches_2025.csv
ci: pin r-lib/actions/setup-r-dependencies@v2 in update_kenpom.yml
```

Use `type!:` or a `BREAKING CHANGE:` footer for breaking changes.

**Important: Never include AI agents or assistants (e.g., Claude, Copilot, Cursor, GPT, Gemini) as co-authors on commits.** Omit all `Co-Authored-By` trailers referencing AI tools. This applies whether the change was generated, refactored, or reviewed with AI assistance — the human author is the sole attributable contributor.
