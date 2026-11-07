---
name: apporo-smart
display: Apporo smart
packages: ["com.apporo.smart"]
aliases: ["Apporo smart", "apporo smart"]
sites: []
open: Apporo smart
description: Connect to computer agents and inspect sessions.
---
# Apporo smart

Apporo smart is the Apporo client for computer AI-agent sessions, based on the shared smart application. It is not the Apporo aiot device-control application or Apporo platform business application. A paired, available computer is required.

Inspect the available hosts and sessions in the actual app. Ask which host or session the user means if there is more than one. Never invent a pairing code or expose a connection token. The user completes account and pairing steps.

Viewing a session is different from sending a command to a computer. Read the visible session state first. Before handing work to another agent, verify the requested scope and selected destination. Do not create a recursive chain where computer and phone agents keep delegating the same task to each other.

Do not call a task finished just because a prompt was sent or accepted. Observe the returned result and distinguish queued, running, waiting for the user, failed and complete. If the host is offline, report that limitation without claiming the requested filesystem or application action occurred.

This guide is based on the shared smart code and existing brand configuration, not a verified walkthrough of every server version.
