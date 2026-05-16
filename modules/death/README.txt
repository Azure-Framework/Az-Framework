WHY /injuries DID NOTHING:

Your HTML does NOT listen for "action: open" at all.
It ONLY listens for: data.type === "injury:update"
and decides to show/hide based on:
- data.pinned (player toggled)
- data.dead and data.showDead
- data.showAlive and whether injuries.length > 0

So /injuries must toggle "pinned" AND send a 'injury:update' message.
This patch does exactly that.

ALSO: If you still see NOTHING and NO debug prints:
Your client.lua is NOT LOADING. Confirm:
1) fxmanifest.lua includes 'client.lua' (root) in client_scripts
2) resource is ensured: ensure Az-Death
3) no startup error in F8/console from Az-Death

This client.lua prints: "[Az-Death] client.lua loaded (injury UI matcher)" on load.
If you don't see it, the file isn't being executed.
