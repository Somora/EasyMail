# API and taint review — 23 October 2026

Scope: Core, Compat, OpenAll, OpenAllSelect, MassSend, QuickAttach, SendTools, and BaganatorCompat, targeting Retail 12.1.5 while keeping Classic fallbacks.

## Changes

- Removed QuickAttach's replacements of `UIErrorsFrame.AddMessage` and its `OnEvent` script. These ran addon code in the general Blizzard error path, including unrelated combat errors. This was a taint risk, not a reproduced blocked-action report. Attachment-limit errors remain visible now.
- Check target existence, player/self predicates, name, and realm for secret values before branching, concatenating, or normalizing. Restricted targets are omitted from the recipient menu; their identity is not saved.
- Ignore restricted `UI_ERROR_MESSAGE` payloads in OpenAll. Ordinary full-bag and COD-money errors still stop processing as before.
- Guard menu bounds and inbox button labels before comparing values. Removed the deprecated `GetMouseFocus` lookup and ancestor traversal; dismissal checks the addon's own menu and anchor bounds.

## Other inspected paths

- Item information uses the existing `C_Item`/legacy fallback. Container access uses `C_Container`/legacy fallbacks; the current documented signatures match the calls. No cooldown, aura, health, power, or combat-log data is used.
- Mail processing, selection, MassSend, and recipient history do not need combat secrets to function. No additional concrete API break was identified in the inspected code. This does not establish runtime compatibility for all clients.
- Bag hooks use `hooksecurefunc`; Blizzard button extensions use `HookScript`. Existing global container hooks remain, with mailbox checks before mail work. Baganator integration hooks its category click method, rather than replacing a shared Blizzard function. These still need integration testing with Baganator installed.
- No new secure attributes or protected-action bypasses were introduced.

## Verification and limits

Six tests in `tests/test_api_safety.py` pass using lupa's Lua 5.1 runtime: compilation of every addon Lua file; ordinary/Classic target behavior; simulated secret target results; legacy and modern item data; unchanged Blizzard error handlers; and secret versus public inbox errors.

Run with Python and `lupa` installed:

```text
python tests/test_api_safety.py
```

The secret tests use marker values, not native WoW secret values. Standalone Lua cannot reproduce Blizzard's secure execution, forbidden frames, or taint propagation. Source review used the public `live` UI mirror, which is mutable, not a pinned 12.1.5 client extraction. No Retail-client test or clean taint-log claim is made.

In Retail, enable Lua errors and test opening/closing mail, target quick fill, selected mail, COD, full bags, Alt-click and overflow/MassSend. Then close mail and exercise combat UI with and without Baganator; inspect any `ADDON_ACTION_BLOCKED`/`ADDON_ACTION_FORBIDDEN` events and taint logs. Repeat the changed paths in Anniversary.

## Sources

- [Blizzard UI error implementation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua)
- [Generated unit API and identity secrecy annotations](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
- [Generated secret inspection APIs](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua)
- [Generated container APIs](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua)
- [Generated item APIs](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)
