# EasyMail

EasyMail is a lightweight World of Warcraft mail addon built from scratch. It takes inspiration from Postal-style quality-of-life features, but keeps the codebase smaller, clearer, and easier to maintain.

## Features

### Inbox
- `Open All` button for unattended inbox processing.
- `AH Sold` button for quickly opening sold Auction House mail.
- `Open Sel` and `Return Sel` for selected mail only.
- Row checkboxes for selective inbox actions.
- Shift-click a mail row to quick loot money or attachments.
- Ctrl-click a mail row to quickly return mail.
- `DEL` action under mail expiry with confirmation for mails that still contain gold, attachments, or COD, plus safe fallback to return when direct delete is not allowed.
- Mailbox Summary chat output for inbox actions.

### Open All Filters
- Toggle gold looting.
- Toggle attachment looting.
- Allow or block COD mail.
- Skip GM mail.
- Stop when bags are full.
- Leave a chosen number of free bag slots.
- Filter by mail type: Non-AH, AH Sold, AH Cancelled, AH Won, and Other AH Mail.
- Shift-click `Open All` to temporarily override filters.

### Send Mail Tools
- `EM` quick menu next to the recipient field.
- Quick fill from target, last mailed recipient, alternate characters, recent recipients, friends, and guild members.
- Online-first Friends and Guild sections.
- Pinned recipients for commonly used mail targets.
- Default recipient support.
- Recipient notes.
- Profession note presets.
- Toggle visibility of send-menu sections from Source Settings.

### Quick Attach
- Quick attach Trade Goods.
- Quick attach Consumables.
- Quick attach Gems.
- Quick attach Recipes.
- Quick attach Stackables.
- Alt-click a bag item to attach it instantly while Send Mail is open.
- Right-click overflow support when the current mail is already full.
- If a mail is already full, extra Alt-clicked or overflow items are queued for Mass Send and continue across multiple mails.
- Baganator category-to-mail overflow is supported: the first 12 items attach normally and the rest continue into the Mass Send queue.
- A dedicated Mass Send Queue popup shows queued items, tooltips, per-item removal, and a clear queue action.
- The queue popup auto-opens when overflow starts, remembers its last position, and clears automatically when the mail window closes.

### Mail QoL
- Automatic wire-style subject filling when sending gold and the subject is blank.
- Recent recipients are remembered after successful sends.
- Known characters are recorded for alt support.
- Recipient favorites, default recipient, and notes are saved.
- Export or reset settings and recipient data from slash commands.
- Reduced routine chat spam so only important summaries and warnings stay visible during normal use.

## Version
- Current release: `1.0.12`
- Game version targets: Retail, Classic client families, and Forever beta (TBC Anniversary tested; other added clients pending in-game validation).
- Interface versions: `11509`, `20506`, `30405`, `38000`, `40402`, `50504`, `120100`, `16001`.

## Other WoW clients and Forever beta

Install the same `EasyMail` folder in each client's `Interface/AddOns` directory. One `EasyMail.toc` lists the interface versions and loads the same Lua files for every client. No build script or separate package is required. The shared code detects modern and legacy container, item, guild, and backdrop APIs.

The interface numbers are based on the [Myslot manifest](https://github.com/tg123/myslot/blob/master/Myslot.toc), with Era and Anniversary updated for the installed 1.15.9 and 2.5.6 clients. Forever beta `16001` is also documented by [ForeverGuide](https://github.com/prezus/ForeverGuide). These identify client versions, not completed EasyMail in-game tests. Other clients still need verification.

If a client update marks the addon out of date, check its interface number with:

```text
/dump select(4, GetBuildInfo())
```

Update the corresponding number in the comma-separated `## Interface:` list in `EasyMail.toc`. Keep the folder name `EasyMail`.

Before relying on another client, test opening the mailbox, selected mail, money and attachments, full bags, COD filters, sending, Alt-click attach, and overflow queues. Verify locked items remain untouched and reopen the mailbox after closing it. Test optional Baganator integration separately when available.

## Install
Copy the `EasyMail` folder into your WoW addon directory so it ends up like this:

```text
World of Warcraft\_retail_\Interface\AddOns\EasyMail
```

## Notes
- EasyMail is a from-scratch addon, not a Postal fork.
- The goal is to provide strong everyday mail features without dragging in unnecessary complexity.
- Built and tested iteratively for WoW Retail UI behavior.
- License: GPLv3.

## Slash Commands
- `/easymail`
- `/em`
- `/em recents`
- `/em export`
- `/em reset settings`
- `/em reset recipients`
- `/em reset all`
- `/em debug`
