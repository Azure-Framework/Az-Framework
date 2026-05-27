# Az-Chat

Transparent custom NUI chat for FiveM with:
- custom inline-HTML styled message rendering
- stock `chat:addMessage` compatibility
- emoji support and an in-chat emoji picker
- built-in staff commands: `/mute`, `/unmute`, `/purge`, `/dm`, `/announce`
- built-in RP commands: `/me`, `/do`, `/ooc`, `/looc`, `/b`, `/try`, `/roll`
- scroll-capped top-left message feed
- input history with Up Arrow recall
- semicolon keybind to cycle chat visibility states
- badge/role icons for chat modes
- optional proximity chat mode
- admin checks through `exports['Az-Framework']:isAdmin(src)`

## Install

1. Put the `Az-Chat` folder in your resources.
2. In `server.cfg`, stop the stock `chat` resource.
3. Ensure `Az-Framework` before `Az-Chat`.
4. Ensure `Az-Chat`.

Example:

```cfg
stop chat
ensure Az-Framework
ensure Az-Chat
```

## Built-in admin commands

- `/mute <id> <minutes> [reason]`
- `/unmute <id>`
- `/purge [keepLast]`
- `/dm <id> <message>`
- `/announce <message>`

## Built-in RP commands

- `/me <action>` nearby action emote
- `/do <description>` nearby scene/outcome line
- `/ooc <message>` out of character message
- `/looc <message>` local OOC alias
- `/b <message>` quick local OOC alias
- `/try <action>` random success/fail RP attempt
- `/roll [max] [reason]` random roll, defaults to 1-100
- `/chatstatecycle` cycle passive chat visibility

## Notes

- The top-left message stack is capped with internal scrolling so it does not run too far down the screen.
- Press Up Arrow in chat input to recall previous sent entries.
- The visibility cycle keybind defaults to semicolon.
- Mode icons are configured in `Config.ModeIcons`.
- Other resources that trigger `chat:addMessage` will still display in Az-Chat.
- Messages typed with `/` are executed through the command system from the client.
- If you want local/proximity chat, set `Config.UseProximity = true` in `config.lua`.


Native GTA text chat is disabled by default with `Config.DisableNativeTextChat = true` so the right-side `[ALL]` chat does not appear beside Az-Chat.
