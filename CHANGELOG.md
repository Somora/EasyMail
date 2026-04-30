# EasyMail Changelog
All notable changes to this project will be documented in this file.

## Version 1.0.3 (30/04/2026)
- Added a confirmation popup for `DEL` when a mail still contains gold, attachments, or COD.
- Kept direct `DEL` behavior for empty mails so quick cleanup stays fast.
- Moved the send-mail `EM` button away from the `Postage` area to avoid overlap when sending many items.

## Version 1.0.2 (22/04/2026)
- Updated WoW Retail interface version to `120005`.

## Version 1.0.1 (21/04/2026)
- Added `/em export` to open a copyable export of EasyMail saved data.
- Added `/em reset settings` to reset filters and source settings while keeping recipient data.
- Added `/em reset recipients` to clear recents, alts, default recipient, pinned recipients, and notes while keeping settings.
- Added `/em reset all` for a full EasyMail saved data reset.
- Cleaned up unused legacy send-mail autocomplete file from the repository.
- Improved `DEL` expiry action safety around Blizzard delete/return APIs.

## Version 1.0.0 (06/04/2026)
- Initial Retail release of EasyMail.
- Added `Open All` inbox processing for gold and attachments.
- Added mail filters for gold, attachments, COD, GM mail, bag handling, and mail types.
- Added `AH Sold` one-click processing for sold Auction House mail.
- Added selective inbox processing with row checkboxes, `Open Sel`, and `Return Sel`.
- Added inbox shortcuts: Shift-click quick loot and Ctrl-click quick return.
- Added expiry action button under mail duration with `DEL` fallback behavior.
- Added Mailbox Summary chat output for inbox actions including money, items, COD, and filter results.
- Added send-mail `EM` menu with target, last mailed, alts, recents, friends, and guild recipients.
- Added online-first Friends and Guild menu polish with pinned recipients.
- Added Quick Attach actions for common item categories.
- Added automatic wire subject filling for gold mails.
- Added default recipient support.
- Added recipient notes and profession note presets.
- Added source toggles for send-menu sections including Quick Attach, Recipient Notes, and Profession Notes.
- Added saved recipient data for recents, favorites, notes, and known characters.
