# Az Framework Compatibility Bridge

The bridge exposes Az player, job, money, metadata, and inventory helpers to the shim resources below:

- `qb-core`
- `es_extended`
- `ND_Core`

Start order should keep `Az-Framework` ahead of the shims:

```cfg
ensure Az-Framework
ensure qb-core
ensure es_extended
ensure ND_Core
```

The shims are meant for resources that read framework exports, callback APIs, job updates, and common money or inventory helpers. They do not reimplement every private table or every niche helper from the original frameworks.
