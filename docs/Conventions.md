# Luau Coding Conventions

This document defines my personal Luau coding conventions. Follow these
conventions when writing or modifying code. The existing code and APIs
remain the source of truth for project-specific behavior.

## 1. General Principles

-   Write strictly typed Luau. **All code should be typed**, including
    parameters, return values, module methods, and meaningful data
    structures.
-   Prefer clear, explicit code over clever or unnecessarily abstract
    code.
-   Follow the established architecture and use existing systems rather
    than duplicating them.
-   Implement the requested solution completely. Prefer one
    well-reasoned implementation over a list of alternatives.
-   Inspect existing code and dependency APIs before assuming how
    something works.
-   Keep comments relatively rare. Add them when they clarify
    non-obvious behavior, explain a necessary constraint, or help with
    math-heavy logic.

## 2. Naming

Use these conventions consistently:

-   **Most local variables:** `camelCase`
-   **Function parameters:** `camelCase`
-   **Methods and module tables:** `PascalCase`
-   **Types:** `PascalCase`
-   **Enums, events, and config keys:** `PascalCase`, such as
    `Enums.ModifierKinds.Add`, `Events.Health.Damaged`, and
    `PlayerConfig.Movement.WalkSpeed`. Identifiers inside definition
    configs keep their `domain:name` form, such as `"item:sword"`.
-   **Constants:** `SCREAMING_SNAKE_CASE`. This covers the keys of the
    `Constants` module (`Constants.TAGS.ITEM`) and module-level constant
    values (`local MAX_INPUT_LENGTH = 200`). A local that aliases a
    `PascalCase` table is `PascalCase` too
    (`local Realms = Enums.CommandRealms`).
-   **Packet configs:** packet keys are `PascalCase`
    (`Enums.Packets.ClientLoaded`); the `NAME` and `PAYLOAD` fields stay
    as Backbone defines them.
-   **Require aliases:** `PascalCase`, named after the module, and kept
    in the file's sorted require block. Config modules are aliased
    `<Name>Config` in the singular, matching the module's own table
    (`local ItemConfig = require(configs.Items)`).
-   **Variables associated with packages, services, or Backbone
    conventions:** follow the established `PascalCase` convention in
    those areas.
-   **Constructors and factory methods:** lowercase names, such as
    `new`, `fromModel`, and `fromId`.

Do not rename established APIs merely to make them match a general rule.
Follow the local convention when a module or framework has a specific
pattern.

## 3. Module Structure and Methods

Use the typed-self module pattern:

``` luau
--!strict

local SomeModule = {}

export type SomeModule = typeof(SomeModule)

function SomeModule.DoSomething(self: SomeModule, value: string): boolean
    -- Implementation
    return true
end

return SomeModule
```

-   Every module should export its self type using
    `export type ModuleName = typeof(ModuleName)`.
-   Type module methods' `self` explicitly, including private methods.
-   Use colon syntax when calling methods that take `self`:
    `someModule:DoSomething()`.
-   Prefer method declarations in the form
    `function Module.Method(self: Module, ...)`.
-   Prefer module methods over local functions. Local functions are
    appropriate when there is a specific reason for keeping a helper
    local.
-   Private methods should be methods on the module table, use a leading
    underscore followed by camelCase, and include the `@priv` annotation
    immediately above the method:

``` luau
--[=[
    @priv
]=]
function SomeModule._doSomething(self: SomeModule)
    -- Implementation
end
```

-   Use lowercase names for constructors and factories where
    appropriate, such as `ItemFactory.fromModel(model)`. These are
    intentional exceptions to normal method naming.
-   Keep each module focused on its responsibility, but do not split
    code into extra modules just to make files shorter.

## 4. Types and Type Safety

-   Type everything. Do not leave function signatures or meaningful data
    structures untyped.
-   Prefer precise types over `any`.
-   Shared type definitions belong in their respective modules under
    `ReplicatedStorage/Shared/Types`. Reuse the appropriate type module
    rather than duplicating shared definitions.
-   Use optional types when a value may legitimately be absent, and
    handle the absent case appropriately.
-   Prefer runtime type narrowing when it is practical. Type assertions
    are acceptable when an invariant is known, but avoid unnecessary
    casts.
-   Prefer casting an instance to the expected class when retrieving it
    with `:FindFirstChild()`, while avoiding excessive or unjustified
    assertions.
-   `any` is permitted when interacting with a genuinely untyped API.
    Keep that use contained and intentional; do not use `any` simply to
    silence a type error.
-   Do not suppress type errors without understanding the underlying
    issue.
-   Generic type parameters may use whichever clear, conventional names
    fit the situation; no special project-specific generic naming rule
    is required.

## 5. Control Flow and Expressions

-   Prefer early returns when they reduce nesting or make a function's
    preconditions clearer.
-   Use ordinary `if` statements for control flow.
-   For ternary-style expressions, prefer the Luau `and/or` pattern when
    it is semantically safe:

``` luau
local name = someBoolean and "True" or "False"
```

-   Do not use the `and/or` pattern when the intended true result can be
    `false` or `nil`, because the expression may incorrectly fall
    through to the alternative. Use an `if` expression or ordinary
    conditional logic in those cases.
-   Avoid redundant comparisons against boolean literals, such as
    `isEnabled == true`. Use the boolean directly when that communicates
    the condition clearly.
-   Use explicit comparisons when they clarify the condition, especially
    for optional values or sentinel values, such as `value ~= nil`.
-   Prefer generalized iteration for tables and numeric loops when
    iterating by index or over a numeric range. Follow the surrounding
    code when a specific iteration style is already established.

## 6. Packages and Frameworks

Use the project's existing packages and framework rather than
implementing duplicate functionality.

### Backbone

Backbone is the game framework and provides established systems such as
audio, interface, character, entity, and physics controllers.

-   Prefer existing Backbone controllers and APIs when they already
    provide the needed functionality.
-   Use the appropriate existing system rather than creating a parallel
    controller/service architecture.
-   Inspect the actual implementation and types before using an API or
    lifecycle hook. Do not invent methods or assume behavior.

### Janitor

Use Janitor for finite-lifetime resources and cleanup, including event
connections, signal connections, temporary instances, and other
resources that require explicit destruction.

-   Make resource ownership and cleanup part of the implementation.
-   Tie cleanup to the lifetime of the object, system, or operation that
    owns the resource.
-   Follow the cleanup patterns already used by the surrounding code.

### Promise

Use the project's Promise package for asynchronous workflows where
promises improve composition, sequencing, error handling, or
frontend/asynchronous coordination.

-   Do not wrap ordinary synchronous functions or simple getters in
    promises without a real reason.
-   Preserve useful types and handle rejection paths appropriately.
-   Do not add asynchronous complexity to synchronous operations.

### Signal and Roblox Events

Use the project's Signal package for custom event-driven communication
where appropriate. Roblox-provided events should still be used when the
event belongs naturally to a Roblox API or instance. Do not replace
native Roblox events with custom signals unnecessarily, or create
duplicate event systems.

### Other Dependencies

-   Prefer an existing dependency when it appropriately solves the
    problem.
-   Inspect the installed package's source or type definitions when its
    API is unclear.
-   Do not assume similarly named packages share the same behavior.
-   Avoid introducing dependencies without a concrete need.

## 7. Error Handling and Logging

-   Choose error handling based on the situation. Handle expected
    missing or optional data gracefully; surface violated invariants
    when continuing would hide a bug.
-   Use `assert` when an invariant must hold and continuing without it
    would be invalid.
-   Use `pcall` or `xpcall` when there is a concrete need to contain or
    recover from an error. Do not wrap code indiscriminately.
-   Use `print` and `warn` with a script-name prefix and backtick string
    interpolation:

``` luau
print(`[{script.Name}] some message here`)
warn(`[{script.Name}] something went wrong`)
```

-   Do not introduce a new logging abstraction when the existing project
    conventions are sufficient.

## 8. Comments and Configuration

-   Comments should be relatively rare and should explain non-obvious
    reasoning, constraints, or math-heavy logic rather than restating
    the code.
-   Comment a configuration setting only when its meaning or effect is
    not obvious from its name, such as values that feed math or that
    are applied relative to another setting. Self-explanatory settings
    need no comment.
-   Private methods must have the `@priv` annotation immediately above
    the declaration, using the format shown in the module section.
-   Avoid speculative TODOs and comments about hypothetical future
    improvements.

## 9. Implementation Expectations

When implementing or modifying code:

1.  Inspect the relevant modules, their callers, and the APIs they
    depend on.
2.  Follow the established architecture and coding conventions.
3.  Choose one suitable implementation and complete it rather than
    presenting several alternatives.
4.  Keep changes focused on the requested behavior. Avoid unrelated
    refactoring.
5.  Update affected callers when a changed API requires it.
6.  Reuse existing packages and framework systems where appropriate.
7.  Preserve strict typing and handle cleanup, asynchronous failures,
    and optional values correctly.
8.  Do not claim code was tested, linted, or type-checked unless those
    checks were actually performed.

The goal is code that is explicit, strongly typed, consistent with the
existing project, and straightforward for another programmer to
understand and maintain.
