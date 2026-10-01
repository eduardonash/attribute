# Lumen

Ballistics, camera tools, and visuals for Multicrew Tank Combat.

- `lumen.lua` — current script
- `attribute.lua` — compatibility loader for existing links
- `PROJECT.md` — architecture, controls, limitations, and verification notes

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/eduardonash/attribute/main/lumen.lua"))()
```

**Trajectory → Shell ESP** displays your observed projectiles independently of assist, shell redirection, preview, and flight progress. Existing preferences and diagnostic API names remain compatible across the rename.

Player ESP uses a commit-pinned [fork of tulontop/esp-lib.lua](https://github.com/eduardonash/esp-lib.lua), authored by tul (@.lutyeh), with corrected full-body bounds and managed cleanup. Tank ESP retains Roblox Highlights. See `PROJECT.md` for test status and limitations.
