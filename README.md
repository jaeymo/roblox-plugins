# roblox-plugins
A monorepo of personal Roblox Studio plugins. Each plugin lives in its own folder under `plugins/` with its own `default.project.json`, and all plugins share one set of Wally packages at the repo root.

## Toolchain

Managed by [Rokit](https://github.com/rojo-rbx/rokit) (see `rokit.toml`):

| Tool | Purpose |
| --- | --- |
| rojo | Builds each plugin into an `.rbxm` |
| wally | Package manager (root `wally.toml` → root `Packages/`) |
| wally-package-types | Adds Luau types to Wally's package thunks |
| lune | Runs the scripts in `.lune/` |
| selene | Linter |
| stylua | Formatter |

```sh
rokit install
lune run install
```

## Layout
```
plugins/
  MyPlugin/
    default.project.json   # the plugin's Rojo project
    src/
      init.server.luau     # entry point (becomes the "Main" Script)
      SomeModule.luau      # becomes a child ModuleScript of Main
Packages/                  # shared Wally packages (gitignored)
default.project.json       # root project, only used for the sourcemap (luau-lsp / wally-package-types)
.lune/                     # repo scripts
```

## Scripts

```sh
lune run new MyPlugin              # scaffold plugins/MyPlugin
lune run build                     # build all plugins into Studio's local plugins folder
lune run build MyPlugin            # build just one
lune run build MyPlugin --watch    # rebuild on change (reload plugins in Studio to pick it up)
lune run install                   # after editing wally.toml
lune run check                     # selene + stylua --check
```

`build` uses `rojo build --plugin`, which writes `MyPlugin.rbxm` straight into `%LOCALAPPDATA%\Roblox\Plugins`.

## Using packages

1. Add the dependency to the root `wally.toml` and run `lune run install`.
2. Make sure the plugin's `default.project.json` maps the shared folder (new plugins include this by default):

   ```json
   "Packages": { "$path": "../../Packages" }
   ```

3. Require it from the plugin: `require(script.Parent.Packages.Signal)`.

Note: the whole `Packages/` folder gets bundled into each plugin that maps it. You can't cherry-pick a single package, since Wally's link modules depend on `Packages/_Index`. If a plugin needs no packages, delete the `Packages` entry from its project file.
