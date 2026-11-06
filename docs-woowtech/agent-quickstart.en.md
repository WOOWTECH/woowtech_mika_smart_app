# Agent quick path

[繁體中文](agent-quickstart.md) | English

For AI agents on a computer (for example Claude Code or Codex): follow these fixed steps to install the CLI or the Skill and connect to woowtech agent (渥屋助理) on the phone. The steps are already chosen; don't weigh alternatives.

woowtech agent is WOOWTECH's build of the open-source [Mika](https://github.com/wangzan101/Mika). The CLI and the Skill keep upstream's `mika` name. The phone app's package is `io.woowtech.agent`; over ADB the CLI finds it by itself.

## 1. Resolve the latest release tag

```sh
curl -s https://api.github.com/repos/WOOWTECH/woowtech_mika_smart_app/releases/latest   # read tag_name
```

```powershell
(Invoke-RestMethod https://api.github.com/repos/WOOWTECH/woowtech_mika_smart_app/releases/latest).tag_name
```

Below, `<tag>` is that value (e.g. `v0.1.37-woow.1`) and `<ver>` is the version without the `v` (e.g. `0.1.37-woow.1`).

## 2. Skill or CLI

- Agent supports skills: **install the Skill by default**; it bundles the CLI script.
- Otherwise install the CLI: `pipx install 'git+https://github.com/WOOWTECH/woowtech_mika_smart_app.git@<tag>#subdirectory=tools/mika'`.

## 3. Install the Skill

`<skills-directory>` is your agent's skills directory, as given in that agent's own documentation; the Skill goes into a `mika` folder inside it.

macOS, Linux:

```sh
curl -L -o mika.zip https://github.com/WOOWTECH/woowtech_mika_smart_app/archive/refs/tags/<tag>.zip
unzip -q mika.zip -d mika-src
mkdir -p <skills-directory> && cp -R mika-src/woowtech_mika_smart_app-<ver>/tools/mika <skills-directory>/mika
python3 <skills-directory>/mika/scripts/mika_cli.py --version
```

Windows PowerShell:

```powershell
Invoke-WebRequest https://github.com/WOOWTECH/woowtech_mika_smart_app/archive/refs/tags/<tag>.zip -OutFile mika.zip
Expand-Archive mika.zip -DestinationPath mika-src
New-Item -ItemType Directory -Force "<skills-directory>" | Out-Null
Copy-Item -Recurse mika-src\woowtech_mika_smart_app-<ver>\tools\mika "<skills-directory>\mika"
py -3 "<skills-directory>\mika\scripts\mika_cli.py" --version
```

Python 3.10 or later: `py -3` on Windows, `python3` elsewhere. With only the Skill, `mika` below means `python3 <skills-directory>/mika/scripts/mika_cli.py` (`py -3 ...` on Windows).

## 4. Connect

Use the connection method the user picked on the phone (woowtech agent › Settings › Connect a computer). You can't see the phone: if the user hasn't said which one, ask once; don't guess.

1. USB: use authorized ADB.
   ```sh
   mika devices --json
   mika connect --device SERIAL --json
   ```
   With more than one phone online, ask the user which one and keep using it.
2. Wi-Fi / private VPN: use the HTTP address and token file path the user gives you. Read the token from the file only; never show it.
   ```sh
   mika --url http://PHONE:8765 --token-file /path/to/token doctor --json
   ```

Common errors:

| Error | What to do |
| --- | --- |
| `unauthorized` | Ask the user to allow USB debugging on the phone. |
| `offline` | Ask the user to replug the cable. |
| `connection_info` (connection information unreadable) | Ask the user to unlock the phone and open woowtech agent once, then run `connect` again. |
| `incompatible_api` | Ask the user to update woowtech agent on the phone. |

## Notes

- Installing and connecting doesn't authorize sending tasks; don't submit phone tasks the user didn't ask for.
- Never print, read aloud or put the token in a command, goal or reply.
- A successful `connect` / `doctor` only proves connectivity, not that a task will succeed.
- To connect an MCP client directly, see [Computer access (MCP)](mcp.en.md).
