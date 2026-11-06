# Computer access (MCP): let AI tools on your computer hand tasks to woowtech agent

[繁體中文](mcp.md) | English

> Using the CLI or the Skill? See [Agent quick path](agent-quickstart.en.md). This page covers connecting an MCP client directly. For every technical detail, see upstream's [MCP guide](https://github.com/wangzan101/Mika/blob/main/docs/mcp.en.md); its commands use upstream's package `com.wangzan101.mika`, which is `io.woowtech.agent` for woowtech agent.

With "Connect a computer" on, woowtech agent (渥屋助理) is an MCP server. An AI tool on your computer that speaks MCP (an MCP client) can hand it a job, and woowtech agent does it on the phone its own way (operating apps, using the built-in browser, working with files), then hands back the result. The computer says what to get done; woowtech agent on the phone decides how.

There are two ways to connect. Each has its own switch and token, and both can be on at once:

- **Over USB (recommended)**: with the phone on a cable and USB debugging on, one command on the computer turns it on, without touching the phone. It listens on the phone itself only, so it can't be reached over Wi-Fi.
- **Over Wi-Fi or a private network**: turned on in the phone's settings, off by default. When the computer and the phone are on the same Wi-Fi or in the same private VPN network, they connect without any port forwarding on your router.

## Connecting over USB (recommended)

You need adb on the computer, the phone listed in `adb devices`, and woowtech agent opened at least once (that's when it writes the script onto the phone).

1. On the computer, run:

   ```
   adb shell sh /sdcard/Android/data/io.woowtech.agent/files/connect-computer.sh
   ```

   It first starts the phone helper (skipped if it's already running), then turns USB mode on, and finally prints the connection info: `url`, `headers`, `token`, `port`, `forward` and a few more fields.

2. Forward port 8765 on the computer to the phone:

   ```
   adb forward tcp:8765 tcp:8765
   ```

3. In your MCP client, add a server of type Streamable HTTP (also called "HTTP"): URL `http://127.0.0.1:8765/mcp`, header `Authorization: Bearer <token>`. See the config example under "Connecting over Wi-Fi or a private network" below; just use `http://127.0.0.1:8765/mcp` as the URL.

To see the connection info again later:

```
adb shell cat /sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json
```

Once it's on:

- A "Computer access is on" notification stays in the shade, and access stays on while woowtech agent is in the background. On the phone, Settings › Connect a computer first shows "Waiting for a computer"; after a request arrives it shows "Request received from a computer" and the request time.
- **After you unplug and replug the cable** (or adb on the computer restarts), run `adb forward tcp:8765 tcp:8765` again. The token stays the same.
- Running the command in step 1 again while it's on keeps the token, so clients you already set up keep working.
- **It turns off when the phone restarts.** Run the command in step 1 again; the token is new then, so update it in your client config.

To turn USB mode off (any of these; the old token stops working at once and the connection info file is deleted; the next time you turn it on you get a new token):

```
adb shell sh /sdcard/Android/data/io.woowtech.agent/files/connect-computer.sh off
```

Or switch off "Connect through USB" in Settings › Connect a computer › Advanced settings on the phone, or tap "Turn off" on the notification (which also turns off the Wi-Fi mode).

The same with plain commands. The component starts with the package `io.woowtech.agent`; the class name and the actions keep upstream's names:

```
adb shell am start-foreground-service -n io.woowtech.agent/com.wangzan101.mika.mcp.McpService -a com.wangzan101.mika.mcp.USB_ON
adb shell cat /sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json
adb shell am start-foreground-service -n io.woowtech.agent/com.wangzan101.mika.mcp.McpService -a com.wangzan101.mika.mcp.USB_OFF
```

After turning it on, the connection info file takes a second or two to appear.

## Connecting over Wi-Fi or a private network

### Turning it on

1. In woowtech agent, open Settings › Connect a computer, select "MCP" › "Wi-Fi / VPN", then tap "Enable network access". Network access is off by default; selecting a guide does not enable it.
2. While it is on, a "Computer access is on" notification stays in the shade; its "Turn off" button switches it off right there.
3. Select an address reachable from the computer, tap "Copy config" and add it to your MCP client. The copied config contains the address and the token; "Preview" is collapsed by default and only shows a token placeholder.
4. Connect or refresh tools in the client, then check that the page shows "Request received from a computer" and the request time.

Access switches, copying and replacing the token, and remote wake/unlock are under "Advanced settings", collapsed by default. The token is stored encrypted on the phone, the same way as model API keys.

### Connecting from a computer

- **Same Wi-Fi**: use the Wi-Fi address from the list (usually `192.168.*.*` or `10.*.*.*`).
- **Private VPN network**: once the phone and the computer are in the same network, use that network's address from the list (these networks often use `100.64.*.*` to `100.127.*.*`).
- When the phone is on mobile data, or the other side has a public address, woowtech agent refuses the connection.

In your MCP client, add a server of type "HTTP" (also called Streamable HTTP), enter the address, and add the header `Authorization: Bearer <token>`. Each client words its config file a little differently; most look like this:

```json
{
  "mcpServers": {
    "woowtech-agent": {
      "type": "http",
      "url": "http://192.168.1.23:8765/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

## Tools

| Tool | Arguments | What it does |
| --- | --- | --- |
| `mika_run_task` | `goal` (required), `conversation` and `request_id` (optional) | Hands over a job and returns a `task_id` right away. The task is recorded in a conversation you can see in the app; to follow up on an earlier job, pass the `conversation` that task returned. |
| `mika_task_status` | `task_id` | The task's state now: status, latest progress, what it is waiting for, and the answer when done. |
| `mika_wait_task` | `task_id`, `timeout_s` (optional, default 30, at most 50) | Waits until the status changes or time runs out, then returns the state. |
| `mika_answer` | `task_id`, `text` | Answers the question woowtech agent asked in this task. |
| `mika_steer_task` | `task_id`, `text` | Adds instructions to a running task (up to 4000 characters). |
| `mika_cancel_task` | `task_id` | Stops the task. |
| `mika_list_tasks` | `limit` (optional, default 10) | The most recent tasks handed over from computers, newest first. |

The tool names keep upstream's `mika_` prefix; renaming them would break computer-side tools. Suggested flow: `mika_run_task` → `mika_wait_task` repeatedly → on `waiting_for_answer`, reply with `mika_answer` → until `done` / `failed` / `cancelled`.

Remote wake and unlock (`mika_device_state`, `mika_wake_device`, `mika_unlock_device`) is off by default. Turn it on yourself under Advanced settings on the phone and enter the current PIN or password twice there; the computer can't set or read it.

## Security

- **Off by default**; it listens only while on and stops at once when turned off.
- **USB mode listens on the phone itself (127.0.0.1) only**; the computer comes in through adb's port forwarding, and Wi-Fi or other networks can't reach it.
- **Only the computer can turn USB mode on and get its token**: the service only accepts callers with system-level permission such as the adb shell. The token is written to `/sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json`; since Android 11 other apps can't read that folder.
- **Every request needs the token.** 5 wrong tries from one address within a minute lock that address out for a minute.
- **No browser requests**: anything carrying an `Origin` header is refused, so web pages can't reach the port through your browser.
- **Private networks only**: both ends must be on a LAN, a private VPN network, or the phone itself; connections from public addresses are dropped immediately.
- **Payments and confirmations stay on the phone**: in tasks handed over from a computer, payments and actions that need your approval are never carried out, whether or not Autonomous mode is on. `mika_answer` answers questions only and can't approve any of these.
- **Only the computer's own tasks**: a computer can't see or stop tasks you started on the phone.
- The transport is plain HTTP, so use it only on networks you trust. Don't share the token; if you think it leaked, replace it under Advanced settings.

## When it doesn't work

- **No address in the list**: the phone isn't on Wi-Fi or a private VPN network.
- **The USB script says the file doesn't exist**: open woowtech agent once, wait a few seconds, and try again.
- **Can't connect over USB** (`curl` reports connection refused or reset): run `adb forward tcp:8765 tcp:8765` again; if the phone restarted, run the command that turns it on first.
- **Port 8765 is already used on the computer**: pick another free port, e.g. `adb forward tcp:18765 tcp:8765`, and use `http://127.0.0.1:18765/mcp` in the config. Nothing changes on the phone.
- **HTTP 429**: too many wrong tokens from one address; wait a minute.
- **The task never starts** (the call fails right away, or the task turns `failed` after two minutes): open woowtech agent on the phone and try again. Android sometimes stops a background app from starting work on its own; once you've opened the app it works.
- **The task stays `paused`**: the phone is most likely locked. woowtech agent needs the phone unlocked to work.
