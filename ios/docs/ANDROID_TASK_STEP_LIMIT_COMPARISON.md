# Android task step limit and iOS MCP model-call limit

Comparison base: iOS mainline `6d74328356d16339a6d4e73065c0671f26861c5f` and
its checked-in Android source. This is not a claim of feature parity.

Android's `SettingsSubPages.kt` offers off, 30, 60, 120, 240 or a custom
1–500 value. `FeatureFlags.taskStepLimit()` persists the value and documents
that a change applies to the next task; off is represented as no limit.
`TaskRun.kt` captures it in the main `RunSpec.stepBudget` except for condition
checks, and constructs the main `AgentLoop` with that value unless eval hooks
supply an override. `AgentLoop.kt` iterates `1..maxSteps`, then has a separate
final-turn procedure which can request a concluding model response. This is not
a cap on every network request or every subtask: e.g. child runs have their own
budgets and an intent gate or final turn may involve additional model work.

At the iOS base, settings have no corresponding task-step preference. Ordinary
chat without the local-tool flow makes a single completion or stream request;
when local learning tools are enabled, `UserProfileChatFlow` has its own fixed
three-model-call budget and 90-second bound. MCP conversation uses
`MCPConversationRunner`: default 12 model calls, six approved remote tool or
resource calls, and 180 seconds; correction calls and local actions share the
model-call budget. Skill authoring uses `SkillToolSession`, with separate default
limits of 12 model calls, ten tool calls and 180 seconds of model time. The
fixed-plan skill execution runtime is a different flow. None of these originally
read an Android-style task-step preference.

This candidate adds only a user-selectable **MCP model-call limit** per sent
message, from 1 to 12, default 12. The app refreshes the shared preference
and captures it at submission, including when another window changed it, so a
change during an approval applies to the next run. It does not raise the
existing runner ceiling, the six-call remote-tool ceiling or the time limit.
One call means one MCP runner model request, including format correction and the
request that returns a final answer. In contrast to Android's final turn, no
extra finishing call is granted after the iOS limit. An approved remote action
may execute on the last call; its result remains visible when the run stops,
but no final answer is invented and a completed action is not rolled back.

Ordinary chat, profile/memory flows, skill authoring and fixed skill execution
do not read this new preference. The Android default of unlimited and custom
limits up to 500 are not implemented: adopting them would require separate
budget semantics and safety review for each iOS runtime. No phone-control
features are included.

The preference has its own UserDefaults key; malformed values fall back to 12.
UI-test and live-test namespaces use separate suites. The local synthetic App
harness tests persistence, invalid values, the actual selected MCP connection,
separate approval, retained results, a limit changed while approval is pending,
the next run's changed budget, and a setting changed in a second session. It uses no model provider or remote MCP
service. Native iOS SwiftUI presentation and accessibility require device or
simulator verification; CLT typechecking and parsing are not native validation.
