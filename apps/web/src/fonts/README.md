# Fonts

Geist Sans and Geist Mono (Vercel, SIL Open Font License 1.1, see `LICENSE.txt`), subset to
Basic Latin, Latin-1 Supplement, Latin Extended-A and the punctuation/currency symbols the
site copy uses. The subset keeps the full variable weight axis (100–900).

Why: the unsubset variable files are ~70 KB each and both were preloaded on every page,
which put ~140 KB on the critical path before the Largest Contentful Paint. The subsets are
~37 KB each and only Geist Sans is preloaded (Geist Mono is used in two sections below the fold).

Regenerate from `node_modules/geist/dist/fonts/**/Geist*-Variable.woff2` (or a newer Geist
release) with harfbuzz, e.g. the `subset-font` npm package, keeping the same code-point ranges.
