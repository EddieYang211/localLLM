# CRAN Submission Checklist - localLLM v1.2.0

**Date:** 2026-02-16
**Maintainer:** Yaosheng Xu <xu2009@purdue.edu>
**Package:** localLLM
**Version:** 1.2.0

---

## ✅ Pre-Submission Checklist

### Package Files
- [x] Source package built: `localLLM_1.2.0.tar.gz` (165 KB)
- [x] DESCRIPTION updated with correct date (2026-02-16)
- [x] NEWS.md contains version 1.2.0 changes
- [x] cran-comments.md updated for this submission
- [x] LICENSE file present (MIT + file LICENSE)
- [x] README.md present and informative

### Testing
- [x] R CMD check passed (0 errors, 0 warnings, 1 note)
- [x] Win-builder checks passed (devel, release, oldrelease)
- [x] Local macOS check passed
- [x] GitHub Actions CI passing (Ubuntu, macOS, Windows)
- [x] All 206 tests pass
- [x] All examples run successfully
- [x] Vignettes build without errors

### Documentation
- [x] All exported functions documented
- [x] @return tags present for all functions
- [x] Examples use tempdir() (not user directories)
- [x] Package names in single quotes in DESCRIPTION
- [x] No spelling errors in documentation

### Code Quality
- [x] No code/documentation mismatches
- [x] No unstated dependencies
- [x] No non-ASCII characters in code
- [x] Proper namespace usage (NAMESPACE file)
- [x] No .Rcheck or .tar.gz files in package directory

### CRAN Policies
- [x] Package size reasonable (~165 KB)
- [x] No undeclared dependencies
- [x] Examples run in < 5 seconds (or use \dontrun)
- [x] No writes to user home directory without permission
- [x] Proper use of tempdir() in examples and tests
- [x] C++ standard declared (C++17 in SystemRequirements)

---

## 📋 Submission Information

### Test Results Summary

**R CMD check:** ✓ PASS
- Errors: 0
- Warnings: 0
- Notes: 1 (system time verification only)

**Win-builder:** ✓ PASS (all 3 versions)
- R-devel: PASS
- R-release: PASS
- R-oldrelease: PASS

**GitHub Actions:** ✓ PASS
- Ubuntu-latest (R-release): PASS
- macOS-latest (R-release): PASS
- Windows-latest (R-release): PASS

### Important Notes for CRAN

1. **C++17 Requirement:**
   - Package requires C++17 (declared in SystemRequirements)
   - Successfully tested on all platforms
   - Required by llama.cpp dependency

2. **Runtime Download Architecture:**
   - Backend library NOT bundled with package
   - Downloaded via `install_localLLM()` after package installation
   - Keeps package size minimal (165 KB vs 100+ MB)
   - Platform-optimized builds (Metal/CUDA support)

3. **No Breaking Changes:**
   - R-level API unchanged from previous versions
   - Existing user code continues to work
   - Backend changes transparent to users

---

## 📤 CRAN Submission Steps

### Step 1: Final Verification
```bash
# Verify package file exists
ls -lh localLLM_1.2.0.tar.gz

# Verify MD5 checksum
md5 localLLM_1.2.0.tar.gz
```

### Step 2: Submit via CRAN Web Form

**URL:** https://cran.r-project.org/submit.html

**Required Information:**
1. **Package name:** localLLM
2. **Version:** 1.2.0
3. **Maintainer email:** xu2009@purdue.edu
4. **Upload file:** localLLM_1.2.0.tar.gz

**Additional Comments (paste into submission form):**
```
This is version 1.2.0 of the localLLM package, a major update with
backend improvements and enhanced features.

All checks pass:
- R CMD check: 0 errors, 0 warnings, 1 note (time verification)
- Win-builder: PASS on devel, release, and oldrelease
- GitHub Actions: PASS on Ubuntu, macOS, Windows

The package uses C++17 (declared in SystemRequirements) and has been
successfully tested on all platforms. The lightweight architecture
downloads the backend library at runtime, keeping the package size
at 165 KB.

No breaking changes to the R-level API. All existing user code
continues to work without modification.

Please see cran-comments.md in the package for detailed information.
```

### Step 3: Email Confirmation

You will receive an email at **xu2009@purdue.edu** with a confirmation link.

**Action Required:**
1. Check your inbox (and spam folder)
2. Click the confirmation link within 24 hours
3. Email will come from: CRAN@R-project.org

### Step 4: Wait for CRAN Review

**Timeline:**
- Initial automated checks: 1-2 hours
- Manual review by CRAN team: 1-7 days (typically 2-3 days)

**Possible Outcomes:**
1. ✅ **Accepted** - Package published to CRAN
2. ⚠️ **Questions/Comments** - CRAN team requests clarifications
3. ❌ **Rejected** - Issues need to be fixed (resubmit after fixes)

### Step 5: Respond to CRAN (if needed)

If CRAN team has questions:
1. Read their email carefully
2. Address ALL points raised
3. Reply promptly (within 1-2 days)
4. Be polite and professional
5. Make requested changes and resubmit

---

## 📧 Email Templates

### If CRAN asks about C++17:
```
Dear CRAN Team,

The package requires C++17 because the underlying llama.cpp library
(which we wrap) uses C++17 features. We have successfully tested
compilation on:

- Windows (win-builder: devel, release, oldrelease)
- macOS (Intel and ARM64)
- Linux (Ubuntu via GitHub Actions)

All platforms support C++17 with modern compiler versions. The
SystemRequirements field clearly declares this requirement.

Best regards,
Yaosheng Xu
```

### If CRAN asks about runtime downloads:
```
Dear CRAN Team,

The package uses a lightweight architecture where the C++ backend
library is downloaded at runtime rather than bundled. This design:

1. Reduces package size from 100+ MB to 165 KB
2. Allows platform-optimized builds (Metal, CUDA)
3. Simplifies cross-platform distribution

Users must explicitly call install_localLLM() after package
installation. This is clearly documented in:
- Package description
- README
- Function documentation
- Vignettes

The download source is GitHub releases (reliable and versioned).

Best regards,
Yaosheng Xu
```

---

## 🎯 Post-Submission

After submission, monitor:

1. **Email:** xu2009@purdue.edu
2. **CRAN incoming:** https://cran.r-project.org/incoming/
3. **Package status:** Look for "localLLM" in the list

**Timeline:**
- Appears in "incoming" within 1-2 hours
- Moves to "pretest" (automated checks)
- Moves to "inspect" (manual review)
- Either "publish" or "reject" decision

---

## 📞 Support Contacts

**CRAN Contact:** CRAN@R-project.org
**Package Maintainer:** Yaosheng Xu <xu2009@purdue.edu>
**GitHub Issues:** https://github.com/EddieYang211/localLLM/issues

---

## ✅ Final Check Before Submission

Before clicking "Submit", verify:

- [ ] Confirmed email address is correct: xu2009@purdue.edu
- [ ] Package file is localLLM_1.2.0.tar.gz
- [ ] cran-comments.md is in the package
- [ ] All tests pass
- [ ] Win-builder passed
- [ ] Ready to respond to CRAN within 24-48 hours

---

**Good luck with your CRAN submission!** 🚀
