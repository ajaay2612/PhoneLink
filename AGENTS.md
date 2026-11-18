# Project navigation

Use Graphify for code discovery and relationship/impact queries in this project instead of grep or rg. Read the source files identified by the graph directly to verify details before editing.

Keep the graph current with `graphify update . --no-cluster`, then regenerate its report with `graphify cluster-only . --no-label` after completing changes. Keep Graphify outputs under this folder's `graphify-out/`; do not merge into or modify a global graph.
