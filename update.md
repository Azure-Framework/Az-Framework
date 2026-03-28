<div align="center">

# Az-Framework
### Weekly Change Summary
### GitHub Markdown Report

</div>

---

## Overview

This document summarizes the main changes, fixes, goals, and follow-up items discussed for **Az-Framework** during the past week.

---

<details open>
<summary><strong>Main Work Covered</strong></summary>

## Main Work Covered

- Continued standardization of core framework-style exports so resources can call simple functions without needing custom wrappers everywhere.
- Direction pushed toward cleaner, easier-to-use APIs such as simplified money/player/job exports.
- Work included a dedicated export test resource to validate framework compatibility and expose failures.
- Focus on making framework behavior feel more plug-and-play for dependent Az resources.

</details>

---

<details open>
<summary><strong>Important Changes / Goals</strong></summary>

## Important Changes / Goals

- Make exports simple and predictable.
- Support calls such as adding money, checking admin state, getting player job, getting player character, and reading player names with consistent patterns.
- Reduce callback confusion by providing stable sync-style or direct-access patterns where possible.
- Improve compatibility across Az resources that expect framework data quickly and reliably.

</details>

---

<details open>
<summary><strong>Issues Found During Testing</strong></summary>

## Issues Found During Testing

- Some callback-based export tests timed out.
- Sync-style calls returned valid data more reliably than some callback flows.
- This suggested parts of the callback bridge or async response handling still needed cleanup.

</details>

---

<details open>
<summary><strong>Direction Requested</strong></summary>

## Direction Requested

- Keep the API simple and framework-wide.
- Make exports behave consistently across all dependent resources.
- Ensure other Az scripts can depend on framework exports without custom fallback logic.

</details>
