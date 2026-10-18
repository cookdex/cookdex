# Released interchange fixtures

These immutable samples contain made-up recipes only. Never regenerate them from the current writer during tests.

- `schema1.zip`: earlier recipe schema 1.
- `schema2.zip`: recipe schema 2, including quantity ranges.
- `schema2-setup.zip`: schema 2 plus optional local shopping setup. Snapshots use the same format.
- `text-v1-single.txt` and `text-v1-multi.txt`: human-sharing Text v1, including ranges, Unicode and optional fields.
- `legacy.txt`: earlier readable recipe text from the synthetic corpus.

Every released backup format is restored through the real service in the full Rust suite. Retain all earlier samples when adding a new format.
