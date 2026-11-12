# Learning reference coordination

Reference capture and every snapshot check acquire the learning file's nonblocking
cooperative lock and compare its encrypted-file revision with the store's loaded
revision. A changed or unreadable revision fails closed; a busy lock is reported
separately and does not itself revoke the snapshot. Reload and obtain fresh user
confirmation after a conflict. The lock and revision checks do not change the
encrypted format or migrate existing data.

Reference-bearing model calls acquire the same lock after their final revision
check. The producer retains the lease until the request begins sending body data
or the producer has actually returned. Cancellation does not release it early.
Only clients conforming to `ReferenceDispatchBoundChatModelClient` may be used:
they must not signal dispatch early, start detached requests after returning, or
retry independently. If the platform never reports body progress, the lease is
retained until completion and concurrent edits fail with a busy message. Native
iOS URLSession callback and cancellation behavior still requires device and SDK
verification before integration.

This is a cooperative, local-file guarantee: every writer must use the same lock
file and check the revision. It cannot prevent non-cooperating processes from
editing files or a remote service from retaining bytes already sent. A change or
cancellation after dispatch can stop publication of a late result, but cannot
recall request bytes already handed to the networking stack. A process crash
releases its OS file lock; it does not provide an acknowledgement that a remote
service did or did not receive data. The implementation does not claim otherwise.
