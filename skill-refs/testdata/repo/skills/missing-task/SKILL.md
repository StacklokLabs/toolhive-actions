---
name: missing-task
description: Fixture skill that runs tasks the Taskfile does not define.
---

# Missing Task

```bash
task build && task deploy
```

Preview with `task docs:missing`. A flattened include has no namespace, so
`task tools:lint` and `task tools` do not exist either.
