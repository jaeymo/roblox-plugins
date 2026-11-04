# roblox-plugins
A monorepo of personal Roblox Studio plugins. Each plugin lives in its own folder under `plugins/` with its own `default.project.json`, and all plugins share one set of Wally packages at the repo root.

## Plugins

- [NodeManager](plugins/NodeManager/README.md): create, organize, visualize and validate development nodes in Workspace.

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