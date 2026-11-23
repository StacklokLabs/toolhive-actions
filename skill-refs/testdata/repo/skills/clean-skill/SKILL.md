---
name: clean-skill
description: Fixture skill whose references all resolve or are skipped.
---

# Clean Skill

Run `scripts/run.sh` from the skill, and read `references/notes.md` and
`docs/guide.md` (also `docs/guide.md:3` and `docs/guide.md#setup`). The
`Taskfile.yml` and `.github/workflows/release.yml` live in the repository.

These are not checked: `https://example.com/missing.md`, `#setup`,
`<path/to/file.md>`, `${HOME}/missing.md`, `$TMPDIR/missing.md`,
`{{ .Values.path }}/missing.md`, `*.md`, `~/missing.md`, `/etc/missing.conf`,
`application/json`, `owner/repo` and ``a `nested` span``. Placeholders and
non-paths are skipped too: `release/v0.11.1`, `release/vX.Y.Z`,
`docs/adr/NNNN-slug.md`, `data/{YYYY}-W{WW}/items.yaml`, `./...` and
`docs/…`. `docs/guide.md::Setup` names a section of an existing file, and
`broken-path/SKILL.md` is a sibling skill.

Build with `task build`, test with `task t` or `FOO=1 task test`, serve the
docs with `task docs:serve` or `task docs`, lint with `task lint`, and use `task remote:anything` or
`task release:v1.2.0`. `task --dir other missing` uses another Taskfile.

```bash
task build && task test
task build 2>&1 | tail -3
task test > test.log
gh workflow run release.yml --ref main -f dry_run=true
gh workflow run "Release"
gh workflow run deploy.yml -R other-org/other-repo
cat .github/workflows/release.yml | grep name  # task missing-in-comment
```

```python
task = "missing-in-python"
```

```console
$ task build
task: missing-in-output
```
