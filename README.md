# EasyMail

EasyMail is a lightweight World of Warcraft Retail mail addon built from scratch. It takes inspiration from Postal-style quality-of-life features, but keeps the codebase smaller, clearer, and easier to maintain.

## Features

### Inbox
- `Open All` button for unattended inbox processing.
- `AH Sold` button for quickly opening sold Auction House mail.
- `Open Sel` and `Return Sel` for selected mail only.
- Row checkboxes for selective inbox actions.
- Shift-click a mail row to quick loot money or attachments.
- Ctrl-click a mail row to quickly return mail.
- `DEL` action under mail expiry with safe fallback to return when direct delete is not allowed.
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

### Mail QoL
- Automatic wire-style subject filling when sending gold and the subject is blank.
- Recent recipients are remembered after successful sends.
- Known characters are recorded for alt support.
- Recipient favorites, default recipient, and notes are saved.
- Export or reset settings and recipient data from slash commands.

## Version
- Current release: `1.0.1`
- Game version target: WoW Retail
- Interface version: `120001`

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
