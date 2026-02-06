# MartenImportmap

Integration between [Marten](https://martenframework.com) and the [ImportMap](https://github.com/treagod/importmap) shard.

## Installation

Add the shard to your `shard.yml`:

```yaml
dependencies:
  marten_importmap:
    github: treagod/marten-importmap
```

Then update your Marten project's installed apps:

```crystal
config.installed_apps = [
  MartenImportmap::App,
  # ...
]
```
