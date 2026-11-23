# 渥屋助理 — reply to App Review (4.3 Spam, 4.2.6), draft 2026-11-23

Owner facts given on 2026-11-23: the two assistants serve different audiences. 渥屋助理 (woowtech agent) is for home consumers. Apporo Assistant is for professional
(B2B) users: construction-project site staff and engineering support. Both stay on the WOOW TECH
account, following the precedent of 渥屋科技 (com.woowtech.aiot) and Apporo aiot (com.apporo.aiot),
which are both published by WOOW TECH CO., LTD.

Owner decisions (2026-11-23): keep the current countries, APPORO UNION INC. is a business partner,
testing so far is internal only, and send this reply now without changing the app. The technical
evidence behind answers 4, 7 and 8 is in [APP_REVIEW_43_RESPONSE_DRAFT_20261122.md](APP_REVIEW_43_RESPONSE_DRAFT_20261122.md).

## Reply text (English, for App Store Connect)

Hello App Review team,

Thank you for the questions. Our answers follow.

**1. What does the app do, and what problem does it solve?**
woowtech agent (渥屋助理) is WOOW TECH's AI assistant for households. Families use it for everyday
home tasks: planning schedules and trips, comparing products before a purchase, reading and
summarizing notices, bills and documents, drafting messages, and saving the result as a PDF, HTML
or CSV file. It works with an AI service the user chooses, keeps conversations, memories and skills
encrypted on the device, and can research websites in its built-in browser and answer with
sources. Any step that would spend money always waits for the user.

**2. Who is the intended audience?**
Home consumers — individuals and families — who use Traditional Chinese, mainly in Taiwan. The app
is not aimed at businesses or professional users.

**3. What gap does it address compared with existing apps?**
We do not claim that chat, browsing, memory or document export are unique on their own. What we
offer households is the combination in one Traditional Chinese app that works with the AI service
they already pay for (no subscription to us, no account), keeps their history and memories on their
own device, and turns an answer into a document they can keep or share.

**4. What did you change based on beta testing?**
Testing so far has been internal: our team, on iPhone and iPad through TestFlight. We have not run
an external beta yet. Since build 4 we added local document export (PDF, HTML, CSV); fixed keyboard,
scrolling and return-to-latest behavior in long chats; show model service errors (for example rate
limits) clearly instead of as timeouts; let users preview an attachment before sending it; and
improved the handling and diagnostics of MCP tool results.

**5. Is this app related to other apps in your account?**
Yes. WOOW TECH CO., LTD. also publishes:
- **Apporo Assistant** (com.apporo.assistant): a separate assistant for Apporo's professional
  customers — construction-project site staff and engineering support teams — under the Apporo
  brand. It is provided by APPORO UNION INC., our business partner, and developed by WOOW TECH.
- **渥屋科技 / woowtech aiot** (com.woowtech.aiot) and **Apporo aiot** (com.apporo.aiot): companion
  apps for our smart-space hosts (homes) and Apporo building controllers (buildings). They are not AI
  assistants.
- **woowtech platform** (io.woowtech.odoo): a client for a company's own Odoo server.

**6. Why is this a separate app rather than part of another one?**
woowtech agent and Apporo Assistant serve different people with different needs: households
handling family tasks, versus professionals on construction sites who need engineering help. They
are offered by different providers under different brands, in different default languages, with
separate support and privacy contacts. Putting a family assistant and a professional site tool in one app would confuse both
audiences. We separated our smart-space apps the same way: 渥屋科技 for homes and Apporo aiot for
buildings.

**7. Does it share significant code or assets with your other apps?**
Yes. Both assistants are built by WOOW TECH from the same core code (chat, memory, browser and MCP
modules). They differ in brand, provider, intended users, default language (Traditional Chinese for
woowtech agent, English for Apporo Assistant), privacy policy, report inbox and support contact.

**8. Does it use third-party code or content?**
The app is based on the open-source project Mika (Apache License 2.0); the license and notice are
shown in the app under About. Five reference skill documents from that project are bundled with
attribution. We did not use a commercial template or an app-generation service; WOOW TECH's team
developed and maintains the app. The app embeds no third-party SDKs; it uses Apple frameworks only.

**9. Did you create this app for a client, and who provides its content?**
No. woowtech agent is WOOW TECH's own product, submitted by WOOW TECH CO., LTD., the account
holder. Answers come from the AI service the user chooses; WOOW TECH operates only the inbox that
receives reports about AI responses.

Thank you for your time.

## Notes

- Countries stay as they are (owner): 渥屋助理 11 territories, Apporo Assistant 8, seven overlap, so
  the reply does not claim different countries.
- The two binaries are functionally the same today (Apporo is a rebrand, commit 557f3a27). The owner
  chose to send this reply first and decide on audience-specific features after App Review answers.
- Before sending, select a build that has the store fixes of eb1acf9e (Save Image prompt, English
  name), so the reviewer does not meet the Save Image crash in 274/275.
