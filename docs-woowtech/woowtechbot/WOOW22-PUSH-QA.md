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

## Corrected source0a78edb2 — HA natural completion PASS

New Home-ready21:21:08.696Z, unchanged signed hash177b980a36b4d6099873149d0f684c421c926bf5b39587e4845462e71008ae05. HA sole normal sendId `fa731315-8781-4655-b18d-5966d5b70a2f`, request21:22:04.227Z/20221:22:04.369Z, provider completed21:22:08.742Z/succeeded, exact marker `android-qa-ha-0a78-fa731315`. Native event `e6ca1bdd-9ab0-40f9-b26b-123bb1494b77`, expiry21:32:08.765Z, no injected notification/retry.

Phone21:22:22.112153Z unique exact service|bot|seed|event active tag/results SECRET. Visible completed text, group expanded then actual body tap into BotServiceActivity / correct HA QA bot / composer / exact assistant marker. [Screenshot](evidence/woow22-push/corrected-ha-natural-tap.png). HA21:24:14.688Z independently post-tap seed/task/API/client/live registration rev1/jobs0, exact original successful sendId and reply; HA relay21:24:14.687Z sent/finished fingerprint. Ordinary background, not cold/offline/cellular. Single seed no picker; tag+actual reply+server metadata, not independent internal selection ID.

PaaS21:25:19.306Z independently confirms corrected HA event sent, exact finished six-field/expiry fingerprint, original live rev1 binding and pending0. Corrected-source HA ordinary-background acceptance is complete.

## Corrected source0a78edb2 — Podman no-process FCM wake and navigation PASS

Fresh cold ready21:24:09.265569Z after `am stop-app`: PID absent, package stopped=false; no force-stop. PID polling remained absent at21:25:01.958340Z and first observed9642 at21:25:03.360908Z. AMS independently records process start21:25:02.620Z for FirebaseInstanceIdReceiver broadcast, between original Podman send21:25:02.360Z and exact relay ACK21:25:03.278Z. No manual app launch. These are sampled host/OS observations, not Google's internal delivery timestamp.

Unique artificial attention event `a7d54a46-3d20-4793-a43e-76b10bf8c36a`, expiry21:35:02.360Z. Phone21:25:32.270253Z observed the unique exact service|bot|main-seed|event attention/SECRET tag and visible attention text. Real body tap resumed BotServiceActivity / expected Podman QA bot / composer / retained main conversation. Opening All conversations without switching showed the original long-reply main entry highlighted. [Body tap](evidence/woow22-push/corrected-podman-cold-tap.png), [highlighted main conversation](evidence/woow22-push/corrected-podman-cold-picker.png).

PaaS21:25:44.405Z independently confirms sent/expected attention fingerprint/expiry/original live registration revision1. Original Podman post-tap metadata requested separately. No-process FCM wake, receipt and body navigation PASS; not force-stop, low-memory eviction, offline or natural completion. One event only; subsequent senders remain HOLD until a separate fresh ready.

Podman21:30:41.541Z owner post-tap independently confirms active/main exact seed, original long-reply title and RESTORE-HAIKU-1126 in that thread, original live client, registered revision1, jobs0/idle/notifications. Cold acceptance is fully corroborated; original-site evidence commit3681f6b.

## Corrected source0a78edb2 — lab43 permission receipt/navigation PASS

Fresh Home-ready21:30:12.961070Z. Single artificial permission `fbcedd67-df52-4354-a333-c5b3a3a76452`, sender21:31:35.645Z / exact ACK21:31:36.659Z / persisted sent, expiry1795729295416. Phone21:32:25.531945Z exact service|bot|seed|event tag, attention/SECRET. After group expansion, actual body tap opened correct lab43 QA bot/composer. Picker highlighted 未命名對話 and not android-qa-device-1642; no manual thread switch. [Body](evidence/woow22-push/corrected-lab43-body.png), [picker](evidence/woow22-push/corrected-lab43-picker.png). Site post-tap metadata requested. Ordinary background artificial event; not model completion/cold.

PaaS lab43 post-tap21:35:15.013Z independently confirms seed/task/original live client/registered rev1/identity/jobs0; relay21:35:15.828Z live/rev1/pending0. Lab43 acceptance complete.

## Corrected source0a78edb2 — lab53 attention receipt/navigation PASS

Fresh Home-ready21:34:42.319466Z. Unique artificial attention `c79e930d-688c-4316-9e16-e7d6d9f4d778`, sent21:35:37.884Z / exact ACK21:35:38.440Z / persisted sent, expiry21:45:37.659Z. Phone21:35:53.996292Z unique exact service|bot|seed|event tag, attention/SECRET. Actual group expansion and body tap opened BotServiceActivity / expected lab53 QA bot / composer. Picker highlighted android-qa-lab53-seed and not device-b76e869b, without manually switching threads. [Body](evidence/woow22-push/corrected-lab53-body.png), [picker](evidence/woow22-push/corrected-lab53-picker.png). Post-tap readonly metadata requested. Ordinary background artificial fixture, no model completion; lab provider login remains unavailable. Neither lab result represents formal PaaS461 deployment.

## Corrected source0a78edb2 — additional HA no-process FCM wake PASS

Separate cold ready21:38:43.160769Z after Home then am stop-app, PID absent/stopped=false. Polls stayed absent through21:39:24.880848Z and first saw11718 at21:39:25.604113Z. AMS process start21:39:24.940Z is FirebaseInstanceIdReceiver broadcast, between HA send21:39:24.704Z and exact ACK21:39:25.541Z. No manual launch; host polling is sampled, not a precise Google delivery clock.

One artificial attention `fec0157f-3a73-4f4d-a9d7-8938798c856c`, expiry21:49:23.583Z. Phone21:39:38.285599Z exact full tag/attention SECRET, visible attention and actual body tap to original HA QA bot/composer. [Body](evidence/woow22-push/corrected-ha-cold-body.png). Single-seed tag/UI/server corroboration; no independent selected-thread-ID observation. Not force-stop/offline/model completion. Separate offline natural request follows only under fresh ready21:40:54.451018Z with WiFi0/mobile_data0/default network none; its result is not yet claimed.

Final lab53 post-tap21:38:35.276Z confirms exact seed/task/notifications/idle, original live client, registered rev1/exact session/outbox0. Relay21:41:36.832Z confirms event sent/exact attention+expiry fingerprint/live revision1/pending0. Lab53 corrected-source acceptance complete.

Additional HA cold post-tap21:40:53.263Z confirms seed/task/thread API/client/live registration rev1/outbox0; relay21:40:55.876Z confirms same event sent/attention fingerprint/live/pending0. Cold acceptance corroborated. Offline request had not been submitted when initial ready exceeded the sender's freshness window; fresh observation21:43:38.089907Z again confirmed Home/WiFi0/mobile_data0/default none, authorizing the same single, still-unsubmitted request. No duplicate request or notification.
