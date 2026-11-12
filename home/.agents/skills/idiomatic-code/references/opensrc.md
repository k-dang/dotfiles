# opensrc troubleshooting

Consult the relevant branch when fetching or citing reference source encounters one of these conditions. Use CLI help for supported commands; the [official CLI README](https://github.com/vercel-labs/opensrc/blob/main/packages/opensrc/README.md) is a fallback when local help is insufficient.

## CLI missing

Use `npx --yes opensrc --help`, then the same `npx --yes opensrc` prefix for subsequent calls. This keeps the tool outside project dependencies.

## Source version differs from the requested spec

Cache labels can differ from the source they contain. Investigate the resolved tag or fallback and fetch the correct supported spec where possible. Disclose any remaining mismatch and leave exact-version compatibility unverified.

## Git metadata missing

Some caches omit `.git`. Cite cached `file:line` locations with the actual package version or ref and fetch date. A remote HEAD lookup does not establish the cached revision. Use commit permalinks only when the actual cached commit is known; disclose mutable refs otherwise.

## Cached branch is stale

When newer source is needed, resolve the desired revision and fetch an explicit spec supported by the CLI. Retain existing cache entries so other work keeps its references.

## Fetch fails

Check the spec, supported flags, connectivity, and access, then retry when there is a concrete correction. Continue with accessible references and disclose the gap. If none can be fetched, report that the reference audit is blocked and label any local-only observations accordingly.
