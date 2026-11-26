# woow.22 push QA — 2026-11-26 UTC

User requested parallel backend coordination; Android parent remains the sole POCO controller. Existing four profiles, sessions and registrations are preserved. Earlier 3820/3821 receipts are not counted as 3822 results.

## Current device

POCO USB ZHO7GIKRHYNRKZRC: versionName 0.1.37-woow.22, versionCode3822, package stopped=false independently read. Normal signed build (see PREVIEW06-ANDROID-ALIGNMENT.md). Fixed portrait temporarily for notification target checks; restore automatic rotation after QA.

## Podman — background test in progress

Original profile opens QA bot `Podman 實測 516b0108` and composer with preserved main-thread content. No pairing, model message or data change. Pressed Home; resumed activity independently confirmed MIUI Launcher. Requested exactly one new artificial attention from the original Podman sender, contingent on a fresh session/registration/seed preflight. PaaS independently checks relay, never sends a duplicate. Other sites and models await separate phone-ready checkpoints.

PaaS 16:40:07.612Z baseline: service21c51aff-99fc-46ec-a970-f75b96658059 / sessione7a016cf-55ab-41a3-8b63-e4ff6cad6127 / registrationb2da04c9-2149-4323-b433-113b69974ff3 / revision1, exact match/live, no pending or retained events. This is existing ACK, not proof of a new PUT.

Phone observation 16:43:16.793004Z: no active notification tag for the Podman service. Event ID, send ACK, handset receipt and actual body tap remain pending. Ordinary Home background, not cold/offline/cellular.

## Other stations

PaaS lab43/53 16:40:06–07Z: live client sessions, registered/revision1, exact relay matches, jobs/pending0. Both have no authenticated available model provider; natural completion requires site model login. No credential copying or model attempt. HA baseline and model readiness are being coordinated independently. All original bindings retained.

## Podman first background receipt and body tap — handset PASS

Event `1b968be9-d970-410b-8ed0-e53f0a1eff2e`: sender16:46:42.213Z, ACK16:46:43.205Z (Podman report). Phone16:47:29.676569Z exact single service|bot|main-thread|event active tag, woowtechbot_attention/SECRET. Visible attention text; group expanded then actual body tapped, resumed BotServiceActivity with expected QA bot, composer and retained main conversation. Opening All conversations without selecting another thread showed the long-reply main entry highlighted and three alternatives not highlighted. Await independent post-tap metadata mapping. [Body tap](evidence/woow22-push/podman22-attention-tap.png), [selected conversation](evidence/woow22-push/podman22-picker.png). Artificial ordinary background, not cold/natural. No model message or profile change.

Podman owner16:51:15.497Z independently confirmed activeThreadId=mainThreadId=7cb1b6b6-8ee0-4af2-8d83-787369ff75d6, the highlighted long-reply title maps to this exact task, notifications=true/busy=false. Phone target and server metadata agree: background attention receipt and exact main-thread body navigation PASS. Next natural completion has a separate fresh Home-ready request; no natural success claimed yet.

PaaS independent read16:52:58.004Z confirmed artificial event state=sent, exact six attention fields plus persisted expiry fingerprint, original live registration/revision1 and pending0. Separate Podman natural Home-ready checkpoint16:51:43.059421Z has been delivered; provider login was reported valid by Podman, but no natural event/receipt is yet recorded. UI fallback fix0a78edb2 is being built separately and is not installed during this test; device evidence remains the installed9e0382d2 build.

## Podman natural finished receipt — delivery PASS, exact-marker response FAIL

Only normal guarded API submission: sendId `poco22-natural-7540fb6b-5086-4616-ac0b-79341cb42933`, marker `PODMAN-NATURAL-3fd88b6b-2796-47d9-9727-663328ae847e`, Claude/claude-haiku-5-5. Podman reports request16:55:00.935Z/20216:55:01.085Z, native done event `9293c5e3-01df-4b4d-aabd-e8f7d106500b`, expiry17:05:07.056Z. Its16:55:32Z read confirms terminal success, idle, no tools, jobs0; that is observation time, not precise completion time. No manual notify/send/outbox injection or resubmission.

Phone16:55:15.351060Z: one exact service|bot|main-thread|event tag, results/SECRET. Visible completed text; expanded group and tapped actual body, resumed BotServiceActivity with expected QA bot/composer. [Screen](evidence/woow22-push/podman22-natural-tap.png) shows the unique request and the real assistant answer declining to echo the marker because guarded relayed content is reference material. The unique marker is in the user request, **not** the assistant answer: exact-marker compliance FAIL. Natural completion notification delivery/body navigation PASS; relay and post-tap metadata independently pending. Do not bypass guarded semantics or automatically retry.

Podman16:56:50.132Z post-tap metadata independently confirms original active/main seed and the unique sendId user message pending=false followed by the actual assistant response. PaaS16:57:37.911Z independent relay read confirms sent/expected finished fingerprint/exact live registration and pending0. Natural notification transport and main-thread navigation PASS, exact-marker compliance FAIL. No retry. HA now has a separate fresh Home-ready request on the unchanged installed build; its new result remains pending.

## HA natural completion — phone receipt, body navigation and exact reply PASS

Fresh Home-ready16:57:31.360091Z. HA reports sole normal message sendId `66654d20-0011-4ca7-9604-95cf869ef11f`, request17:00:08.207Z/20217:00:08.334Z, Codex/gpt-6.2-sol turnCompleted17:00:13.488Z/succeeded, exact assistant marker `android-qa-ha-woow22-66654d20`. Native done/outbox event `24d54265-9b7f-463c-9f35-079de7c3eef3`, expiry17:10:13.499Z, relay persisted sent and jobs0 reported by HA, no artificial injection or retry.

Phone17:01:50.499070Z independently found the exact HA service|bot|seed|event notification, results/SECRET. Visible completed text, expanded group then real body tap; resumed BotServiceActivity and correct original HA QA bot/composer. [Actual assistant reply](evidence/woow22-push/ha22-natural-tap.png) exactly matches the new marker. Single initial thread has no picker: tag+actual reply+server metadata corroboration, not an independent internal selection-ID observation. Ordinary Home background; not cold/offline/force-stop/cellular. Device remained source9e0382d2 normal3822 throughout. PaaS independent finished fingerprint and HA post-tap metadata requested; no new event authorized.

HA17:04:01.577Z post-tap seed/task/API/client/regrev1/jobs0 and PaaS17:04:23.505Z independent sent/finished fingerprint/live/pending0 complete this original9e0382d2 acceptance. Subsequently the corrected0a78edb2 APK was installed, exact hash verified and UI checked; no new-source push receipt is claimed. All subsequent senders require a new site-specific ready; original registrations retained.
