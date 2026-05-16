Daily Check-In v2 (wheel spin, keys, rewards in UI)

Installation:
1. Extract the folder 'daily_checkin_v2' into your server's resources directory.
2. Ensure oxmysql and Az-Framework are running.
3. Import sql/daily_checkin.sql into your database (creates keys column and reward table).
4. Replace html/assets/sounds/*.mp3 with your desired sounds, or download free sounds (examples below) and place them in that folder.
5. Add 'ensure daily_checkin_v2' to your server.cfg and start the resource.
6. Use /dailycheckin in-game to open UI and /dailycheckin to open again as needed.

Free sound sources (suggested):
- https://freesound.org (search for short UI blips, open, claim, spin sounds)
- https://freesfx.co.uk (free-to-use SFX)
Make sure to follow the licenses for attribution if required.

Features changed/added:
- Calendar now displays reward amounts (money, weapon, keys) per day.
- UI is a centered container over a blurred background overlay (not full-screen background).
- Animated wheel modal that consumes 1 key per spin and awards random wheel prizes defined in Config.WheelPrizes.
- Keys are tracked per-user in the DB (daily_checkin_users.keys).
- Claiming rewards can grant keys (configured per-day).
