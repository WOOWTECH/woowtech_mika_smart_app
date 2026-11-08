# Connect a computer to Apporo Assistant

This branch is a development build. No public Apporo Assistant installer or release channel has been published by this work.

Use the CLI bundled in this source checkout. Python 3.10+ and authorized USB ADB are required for USB access. On the phone, open **Settings → Connect a computer**, select USB and enable access.

```sh
export MIKA_ANDROID_PACKAGE=com.apporo.assistant
python3 tools/mika/scripts/mika_cli.py devices --json
python3 tools/mika/scripts/mika_cli.py connect --device SERIAL --json
```

Select the actual device serial. Explicitly setting the package is essential when Mika or woowtech agent is also installed. Internal `mika` command and API names are retained for compatibility.

For Wi-Fi or a private VPN, use the address displayed by the phone and a private token file:

```sh
python3 tools/mika/scripts/mika_cli.py --url http://PHONE:8765 --token-file /private/path/token doctor --json
```

Never put the token in chat or a task. Connectivity does not authorize sending a task. Ask the user to complete login or verification on their own screen. Remote tasks keep the same ordering and payment restrictions as the shared engine.

For MCP, see [MCP setup](mcp.en.md).
