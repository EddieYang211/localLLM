# CRAN Policy Notes for localLLM Maintainers

This note summarizes CRAN Repository Policy points that matter for maintaining
`localLLM`. It is a practical checklist, not a substitute for the official
policy.

Official policy:

<https://cran.r-project.org/web/packages/policies.html>

## Core Principle

CRAN is a distribution repository for publication-quality R packages. Submitting
or updating a package means the maintainer has read and agrees to CRAN policies.

For `localLLM`, this means:

- Keep releases small and reviewable.
- Avoid frequent resubmissions unless there is a real fix.
- Make package checks reliable on CRAN machines.
- Do not assume CRAN binary repositories behave like source package releases.

## Email Etiquette

CRAN email should be plain text only.

Do not send:

- HTML email.
- Rich-text email.
- Attachments unless explicitly requested.
- Questions to a broad CRAN list when the policy names a more specific contact.

Use the correct channel:

- New submissions and resubmissions go through the CRAN submission form.
- Published package issues may go to CRAN, if appropriate.
- Binary package questions should go to the relevant binary package maintainer
  listed by CRAN policy, not to a busy general list.

When in doubt, re-read the policy before sending.

## Source Packages vs Binary Packages

CRAN source packages and CRAN binary packages are separate.

The source package is the package uploaded by the maintainer, for example:

```text
src/contrib/localLLM_1.3.0.tar.gz
```

Binary packages are built later by CRAN infrastructure or platform maintainers,
for example:

```text
bin/macosx/big-sur-arm64/contrib/4.4/localLLM_1.2.1.tgz
bin/windows/contrib/4.4/localLLM_1.2.1.zip
```

Important implications:

- CRAN can show `localLLM 1.3.0` as the source version while an older R binary
  repository still indexes `localLLM 1.2.1`.
- `install.packages("localLLM")` on macOS and Windows usually prefers binary
  packages by default.
- If the user's R version points to an old binary repository, they may install
  an older binary even though the current source package is newer.

## Binary Repository Support Window

CRAN policy states that binary packages are built for the current version of R.
They may also be built for the last version in the previous series or for
R-devel.

Do not assume older R series binary repositories keep receiving new package
versions.

Example diagnostic:

```r
options(repos = c(CRAN = "https://cloud.r-project.org"))

available.packages(type = "source")["localLLM", "Version"]
available.packages(type = "binary")["localLLM", "Version"]
```

For a specific binary repository:

```r
available.packages(
  contriburl = "https://cloud.r-project.org/bin/macosx/big-sur-arm64/contrib/4.4"
)["localLLM", "Version"]
```

If source is newer than binary, this does not necessarily mean CRAN made an
error. The binary repository may correspond to an older R series that is no
longer updated.

## User Installation Guidance

Recommended guidance for users:

```r
install.packages("localLLM")
```

If a user is on an older R version and receives an older binary package, tell
them to either upgrade R or install from source:

```r
options(download.file.method = "libcurl")
install.packages("localLLM", type = "source")
```

Do not promise that every R version and platform will have a current binary
package at the same time.

## External Libraries and Backend Downloads

CRAN is cautious about packages that download external software.

For `localLLM`:

- Do not download the backend library at package load time.
- Do not download the backend library during package installation.
- Keep `install_localLLM()` user-initiated and explicit.
- Use HTTPS URLs.
- Prefer fixed versioned URLs over floating `latest` URLs.
- Provide clear errors for download, SSL, permission, and checksum failures.
- Document what is downloaded, where it is stored, and how users can remove or
  override it.

Precompiled external software is sensitive under CRAN policy. Keep the design
transparent and user-controlled.

## Network Access

CRAN checks should not depend on live network access.

For examples, tests, and vignettes:

- Do not require downloading models.
- Do not require downloading backend binaries.
- Do not rely on third-party services being reachable.
- Skip network-dependent tests on CRAN.
- Fail gracefully if a network resource is unavailable.

Good pattern:

```r
testthat::skip_on_cran()
```

or conditional checks around network-dependent behavior.

## File System Writes

Packages should not write arbitrary files to the user's home directory, the R
library directory, or system locations.

Preferred locations:

```r
tools::R_user_dir("localLLM", "cache")
tools::R_user_dir("localLLM", "data")
tools::R_user_dir("localLLM", "config")
```

During CRAN checks:

- Use `tempdir()` for temporary files.
- Avoid persistent writes outside temporary directories.
- Avoid creating cache directories in the check user's home directory.

## Source Package Contents

The CRAN source tarball should not include generated binary artifacts.

Make sure `.Rbuildignore` excludes files such as:

```text
src/*.o
src/*.so
src/*.dll
src/*.dylib
src/symbols.rds
inst/lib
```

For `localLLM`, source should contain the R package source and buildable C++
interface code, not compiled backend binaries.

## Examples, Tests, and Vignettes

CRAN examples and tests should be fast, deterministic, and portable.

Avoid in CRAN checks:

- Large model downloads.
- Real LLM inference requiring substantial memory.
- Long-running benchmarks.
- Assumptions about GPU availability.
- More than 2 CPU cores.
- Opening browsers or interactive UI.

Use small mocked tests for:

- Argument validation.
- Path handling.
- Error handling.
- Metadata parsing.
- Backend installation helper logic without real downloads.

## Submission and Resubmission

Before submission:

```bash
R CMD build localLLM
R CMD check --as-cran localLLM_*.tar.gz
```

For resubmission:

- Use the CRAN submission form.
- Explain changes in the optional comments field.
- Bump the package version for updates to a published package.
- Do not repeatedly submit while a previous submission is pending.
- Explain any WARNING or significant NOTE clearly.

## Reverse Dependencies

If other CRAN packages depend on `localLLM`, check reverse dependencies before
making breaking changes.

For future releases:

- Identify reverse dependencies.
- Run reverse dependency checks when API behavior changes.
- Notify affected maintainers ahead of time if needed.

## Archival Risks

CRAN packages can be archived for:

- Check ERRORs on CRAN machines.
- Long-standing WARNINGs or significant NOTEs.
- Policy violations.
- Maintainer email failure.
- Broken dependencies.
- Network-dependent checks that fail.
- External resources becoming unavailable.

Monitor:

<https://cran.r-project.org/web/checks/check_results_localLLM.html>

## Practical Checklist for localLLM

Before each CRAN release:

- Confirm `DESCRIPTION` version is correct.
- Confirm `NEWS.md` describes user-visible changes.
- Confirm `.Rbuildignore` excludes compiled artifacts.
- Run `R CMD build`.
- Run `R CMD check --as-cran`.
- Check examples do not require model downloads.
- Check tests do not require network access on CRAN.
- Check backend download is explicit and user-initiated.
- Check cache paths use CRAN-compliant locations.
- Use plain text for any CRAN-related email.
- Do not assume older R binary repositories will update.

