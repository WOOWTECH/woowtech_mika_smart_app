# 渥屋助理 — reply to App Review (4.3 Spam, 4.2.6), draft 2026-11-23

Owner facts given on 2026-11-23: the two assistants serve different audiences. 渥屋助理 (woowtech agent) is for home consumers. Apporo Assistant is for professional
(B2B) users: construction-project site staff and engineering support. Both stay on the WOOW TECH
account, following the precedent of 渥屋科技 (com.woowtech.aiot) and Apporo aiot (com.apporo.aiot),
which are both published by WOOW TECH CO., LTD.

Owner decisions (2026-11-23): keep the current countries, APPORO UNION INC. is a business partner,
testing so far is internal only, and send this reply now without changing the app. The technical
evidence behind answers 4, 7 and 8 is in [APP_REVIEW_43_RESPONSE_DRAFT_20261122.md](APP_REVIEW_43_RESPONSE_DRAFT_20261122.md).

**Sent 2026-11-23 09:14 (Taipei)** in the App Review thread `5aaf9478-27a2-3680-bbc6-7742d60b37bc` as two
messages, `90e907cb-a52c-4082-8015-0b5c44d419d0` and `42dabfa6-57c9-4100-b114-2882a19d025f`; the thread read back
both bodies exactly. Before sending, build 276 (source `533cd6d8`, the store fixes of `eb1acf9e` on top of 275)
was selected for version 0.1.0 in place of 274. The version was not resubmitted.

## Reply text (English, App Store Connect thread 5aaf9478…)

Apple's message asks to reply instead of resubmitting if the app already complies, and to answer its nine
questions in full. The earlier woowtech smart and Apporo smart replies were split into parts because of the
message length limit (every part under 4,000 characters), so this one is sent in two parts.

### Part 1

```text
(Part 1 of 2: answers 1-4)

Hello,

Thank you for the review. We believe woowtech agent (渥屋助理) 0.1.0, App ID 6834435121 meets guidelines 4.3(a), 4.3(b) and 4.2.6, so we are replying instead of resubmitting. Our answers follow in two messages because of the length limit.

1. woowtech agent is an AI assistant for household use. Families use it to plan schedules and trips, compare products, summarize notices, bills and documents, draft messages, and save the result as a PDF, HTML or CSV file. It connects to an AI service the user chooses, keeps conversations, memories and skills encrypted on the device, and researches websites in its built-in browser, answering with sources. Any step that spends money waits for the user. The problem it solves: AI help at home usually means copying text between a chat app, a browser and a document editor; here the research, the answer, saved family preferences and the finished document stay together on the user's device.

2. Home consumers — individuals and families — who use Traditional Chinese, mainly in Taiwan. It is not aimed at businesses or professionals.

3. Most AI chat apps are tied to one provider's subscription and keep history on its servers. woowtech agent is built for Traditional Chinese households: it works with the AI service they already use, keeps history and memories on their device, researches the web with sources, and turns answers into documents in the same app. No single feature is unique; the value is this combination for this audience.

4. Testing has been internal: our team used the app on iPhone and iPad through TestFlight and development builds; no external beta yet. Feedback we applied: in long chats the message box covered the latest reply (we fixed the layout and added a return-to-latest control); testers wanted to keep answers as files (we added PDF, HTML and CSV export); memories could not be changed from the chat (the assistant can now edit or forget them on request); rate-limit errors from the AI service looked like timeouts (they are now shown as such); and attachments could not be checked before sending (they can now be previewed first).
```

### Part 2

```text
(Part 2 of 2: answers 5-9)

5. It is a standalone product. Our account also has Apporo Assistant, an assistant for professionals on construction projects (site staff and engineering support), provided by our business partner APPORO UNION INC. under the Apporo brand. The other apps are not assistants: 渥屋科技 (woowtech aiot) controls our smart-space hosts in homes, Apporo aiot controls Apporo building controllers, and woowtech platform is a client for a company's own Odoo server.

6. No. Apporo Assistant belongs to a different provider and brand and serves professional teams at work. Merging a household assistant into a partner's professional app, or the reverse, would mix two audiences, brands and privacy and support relationships. The other apps control devices or business systems.

7. Yes, with Apporo Assistant. WOOW TECH builds both from the same core frameworks: AssistantContracts (shared types), AssistantDomain (chat flow), AssistantModels (the user's AI service), AssistantMemory and AssistantSkills (on-device memory and skills), AssistantBrowser (browser and web research), AssistantMCP (the user's own tool servers) and AssistantPersistence (encrypted storage). woowtech agent also includes AssistantDocuments (PDF, HTML and CSV export). The name, icon, brand, default language, privacy policy and report inbox are separate.

8. Yes. The app is derived from the open-source Android app Mika (Apache License 2.0); its license and notice are shown in the app. We rebuilt it natively for iOS in Swift and bundle five of its reference skill documents with attribution. What we added: the Traditional Chinese household experience, encrypted on-device storage, built-in browser research and web tasks that stop for the user's approval, connections to the user's own tool servers, document export, and reporting of AI responses. No commercial template or app-generation service was used.

9. No. woowtech agent is WOOW TECH's own product, concept and brand, submitted by WOOW TECH CO., LTD. Answers come from the AI service each user chooses.

Thank you for your time.

WOOW TECH CO., LTD.
```

## Notes

- Countries stay as they are (owner): 渥屋助理 11 territories, Apporo Assistant 8, seven overlap, so
  the reply does not claim different countries.
- The two binaries are functionally the same today (Apporo is a rebrand, commit 557f3a27). The owner
  chose to send this reply first and decide on audience-specific features after App Review answers.
- Before sending, select a build that has the store fixes of eb1acf9e (Save Image prompt, English
  name), so the reviewer does not meet the Save Image crash in 274/275.
