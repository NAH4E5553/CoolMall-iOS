import Foundation
import MallCore
import Observation

/// Page state for the integrated home and its shared refresh/recovery slot. The Scene/home-root view identity owns this model; SwiftUI's task
/// owns every await call.
///
/// Request validity: `generation` bumps on every accepted read and on every
/// visibility loss, so a stale success/error/cancellation can never overwrite
/// or clear a newer request (STATE-02/03). Retained ready/empty/failed states
/// survive tab switches with no implicit re-read; an unfinished first read
/// returns to idle and re-reads once when visible again. A still-current
/// request that gets cancelled — including a service that ignores
/// cancellation and returns a value or a plain error — falls back to the
/// retained state instead of stranding the page in loading (R-HOME-01-01).
///
/// HOME-RETAP-DEBOUNCE refresh (2026-10-20, 300ms trailing merge): a real
/// home re-tap still scrolls to top immediately, but its read is merged —
/// every DISTINCT re-tap event invalidates the previous identity, cancels
/// the previous merge timer/read task and ends the waiters of whatever it
/// superseded, then re-arms "last tap + 300ms". Only after the last tap has
/// been quiet for the full window (and the page is still active) does ONE
/// latest read start; a single tap waits the same 300ms. Pulls, recoveries
/// and accessibility refreshes keep their ORIGINAL immediate-or-rejected
/// contracts and are busy while a merge wait or a read is pending. A
/// re-tap may supersede an in-flight pull (its waiter ends promptly, never
/// cleaning the new task). Losing visibility cancels timer and read and
/// drops the pending intent without replay. Stale success/error/cancellation
/// outcomes are rejected by the generation guard; duplicate delivery of the
/// SAME intent token (retap token / pull interaction) is deduplicated.
@MainActor @Observable
final class HomeViewModel {
    enum State: Equatable {
        case idle
        case loading
        case ready(HomeSnapshot)
        case empty(HomeSnapshot)
        case failed(HomeLoadFailure)
    }

    private(set) var state: State = .idle
    private let home: any HomeLoading
    private var generation = 0
    private var retainedState: State?
    private var lastConsumedRetryToken = 0

    // Refresh state (internal projections only).
    private(set) var isRefreshing = false
    private(set) var refreshFailedHint = false
    /// Monotonic ticket bumped whenever an IMMEDIATE refresh intent (pull,
    /// recovery, hint retry, accessibility) is accepted.
    private(set) var refreshTicket: UInt64 = 0
    /// The ONE owner of EVERY network read — first load, original retry and
    /// refresh alike: the task holds the trailing 300ms merge sleep and the
    /// read for the CURRENT intent; a new retap cancels and replaces it
    /// whole (R-DB-01: also the in-flight first read, for real). Never a
    /// pending boolean slot consumed by a view task, never two independent
    /// I/O drivers.
    private var ownedTask: Task<Void, Never>?
    /// The generation the current ownedTask serves — lets a cancelled
    /// CALLER cancel exactly its own request and never a newer one.
    private var ownedRequest: Int?
    /// Synchronously occupied at acceptance, cleared only by the CURRENT
    /// intent's settle: covers the window where the owned Task has been
    /// created but has not started executing yet (R-DB-02) — isRefreshing
    /// alone only turns on once the task runs.
    private(set) var hasPendingOwnedRequest = false
    /// A retap intent is inside its merge window (busy for other entries).
    private(set) var isRetapPending = false
    /// Visibility snapshot owned here so an expired merge can re-check it.
    private var isActive = true
    /// Internal merge-window seams for @testable time control; production
    /// sleeps on the monotonic task clock for 300ms — no public clock or
    /// API is exposed. `retapElapsed` anchors the ABSOLUTE merge deadline at
    /// acceptance (R-DB-03): the task only waits the REMAINING time.
    var retapMergeWindow: ContinuousClock.Duration = .milliseconds(300)
    var retapMergeSleep: (ContinuousClock.Duration) async throws -> Void = {
        try await Task.sleep(for: $0)
    }
    var retapElapsedOverride: (() -> ContinuousClock.Duration)?
    private let clockStart = ContinuousClock().now

    private func retapElapsed() -> ContinuousClock.Duration {
        retapElapsedOverride?() ?? (ContinuousClock().now - clockStart)
    }
    private var lastHandledReTapToken: UInt64 = 0
    private var lastHandledPullInteraction: UInt64?
    private var refreshWaiters: [UInt64: [UUID: CheckedContinuation<Void, Never>]] = [:]

    /// Reserves the same slot as a re-tap; only the single drive performs I/O.
    /// A rejected pull ends immediately. An accepted pull waits for its ticket.
    func pullToRefresh(interaction: UInt64? = nil) async {
        guard !Task.isCancelled else { return }
        if let interaction {
            guard interaction != lastHandledPullInteraction else { return }
            // Consume even while busy: a callback repeated after the current
            // request ends still belongs to the same rejected interaction.
            lastHandledPullInteraction = interaction
        }
        guard acceptImmediateRefresh() else { return }
        let ticket = refreshTicket
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Covers cancellation before registration, including a handler
                // that already ran while this MainActor operation was pending.
                guard !Task.isCancelled else { continuation.resume(); return }
                refreshWaiters[ticket, default: [:]][waiterID] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPullWaiter(ticket: ticket, waiterID: waiterID)
            }
        }
    }

    /// Non-drag accessibility intent, immediate (original contract).
    func requestAccessibleRefresh() { acceptImmediateRefresh() }

    /// ORIGINAL immediate acceptance for pull/recovery/hint/accessibility:
    /// state-gated and busy-rejected. `hasPendingOwnedRequest` is occupied
    /// SYNCHRONOUSLY at acceptance, so a second immediate entry is rejected
    /// even in the same actor turn, before the first intent's Task has
    /// started executing (R-DB-02) — it changes no ticket, cancels nothing
    /// and ends no waiter. A re-tap may still supersede the accepted intent.
    @discardableResult
    private func acceptImmediateRefresh() -> Bool {
        switch state {
        case .ready, .empty, .failed: break
        case .idle, .loading: return false
        }
        guard !hasPendingOwnedRequest, !isRefreshing, !isRetapPending else { return false }
        startOwnedRead(debounced: false, bumpsTicket: true)
        return true
    }

    /// Arms the single owner task. `debounced` waits until the ABSOLUTE
    /// deadline captured synchronously at acceptance — "this event + 300ms"
    /// on the internal monotonic clock (R-DB-03) — sleeping only the
    /// REMAINING time and skipping the sleep entirely when the deadline has
    /// already passed; either way the read re-checks identity, cancellation
    /// and activity before touching the service. Scheduling ALWAYS
    /// invalidates the previous identity, REALLY cancels the previous owned
    /// task (first load, retry, or refresh — R-DB-01) and ends the waiters
    /// of the intent it superseded; it also occupies the busy slot
    /// synchronously (R-DB-02). The superseded task's settles are
    /// generation-guarded and can never pollute this one.
    @discardableResult
    private func startOwnedRead(
        debounced: Bool, bumpsTicket: Bool, fullPageReload: Bool = false
    ) -> Task<Void, Never> {
        generation += 1
        ownedTask?.cancel()
        finishRefresh(refreshTicket)
        refreshFailedHint = false
        hasPendingOwnedRequest = true
        if debounced {
            isRetapPending = true
        } else if bumpsTicket {
            // Immediate entries (pull/recovery/hint/accessibility) own the
            // ticket their waiters are registered under.
            refreshTicket &+= 1
        }
        let request = generation
        ownedRequest = request
        let ticket = refreshTicket
        let deadline = retapElapsed() + retapMergeWindow
        let sleep = retapMergeSleep
        let elapsed = retapElapsed
        let task = Task { [weak self] in
            guard let self else { return }
            if debounced {
                // Only the time the deadline still has left — never a fresh
                // full-window sleep from whenever the task happens to start.
                let remaining = deadline - elapsed()
                if remaining > .zero {
                    do {
                        try await sleep(remaining)
                    } catch {
                        return
                    }
                }
            }
            await self.performOwnedRead(
                request: request, ticket: ticket, fullPageReload: fullPageReload)
        }
        ownedTask = task
        return task
    }

    /// Awaits the owned read for the given request and propagates CALLER /
    /// view-task cancellation into that same read (R-OWN-01): the SwiftUI
    /// task that started a first load or original retry may be cancelled
    /// without any later drive(active:false) running (view removal, scene
    /// end), and even a service that IGNORES the cancellation must not then
    /// commit. The cancellation is bound to the request identity: a stale
    /// caller's cancellation can never touch a request that has since been
    /// taken over by a re-tap, pull or any newer intent.
    private func awaitOwnedRead(request: Int, _ task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.ownedRequest == request else { return }
                self.ownedTask?.cancel()
            }
        }
    }

    private func finishRefresh(_ ticket: UInt64) {
        for waiter in (refreshWaiters.removeValue(forKey: ticket) ?? [:]).values { waiter.resume() }
    }

    private func cancelPullWaiter(ticket: UInt64, waiterID: UUID) {
        guard var waiters = refreshWaiters[ticket],
            let waiter = waiters.removeValue(forKey: waiterID)
        else { return }
        if waiters.isEmpty {
            refreshWaiters.removeValue(forKey: ticket)
        } else {
            refreshWaiters[ticket] = waiters
        }
        // Cancellation ends this wait only. The single drive remains the
        // request owner; an old waiter cannot clear a newer accepted ticket.
        waiter.resume()
    }

    init(home: any HomeLoading) {
        self.home = home
    }

    /// Single drive entry for the view's one `.task(id:)`, keyed by visibility
    /// and the model-accepted ticket. Recovery buttons share that slot; the
    /// original retry token remains supported for internal callers. Visibility
    /// changes cancel the in-flight await — the first
    /// read and a refresh are cancelled alike by an explicit visibility loss,
    /// never only by onDisappear. Losing visibility is routed FIRST: an
    /// accepted-but-unstarted refresh is dropped (no hidden off-page request)
    /// and the indicator closes. A retry token is consumed exactly once;
    /// rejected re-taps never change the key.
    func drive(active: Bool, retryToken: Int) async {
        // R-HOME-02-R1-01: losing visibility always wins — suspend cancels
        // the merge timer and the in-flight read and drops a pending retap
        // intent (returning never replays it), so an off-page drive can
        // never issue a hidden request. An original-retry intent that
        // already arrived but has not started is likewise consumed WITHOUT
        // running (R-HOME-02-R1-04): returning replays the visibility path
        // only and never auto-retries; a later explicit retry still can.
        isActive = active
        guard active else {
            lastConsumedRetryToken = retryToken
            suspend()
            return
        }
        if retryToken != lastConsumedRetryToken {
            lastConsumedRetryToken = retryToken
            await retry()
            return
        }
        await loadIfNeeded()
    }

    /// Visibility half of the drive contract. `active` triggers the first
    /// read from idle; `false` revokes the generation, closes the refresh
    /// indicator and clears an un-run accepted refresh (returning to the page
    /// never re-fires it), restoring the retained state (or idle).
    func handleVisibility(_ active: Bool) async {
        if active {
            await loadIfNeeded()
        } else {
            suspend()
        }
    }

    /// R-OWN-01-LIFE: page REMOVAL / teardown cleanup. The entry's `.task`
    /// has long returned once the first read finished, and a re-tap's merge
    /// timer / in-flight read is owned ONLY by `ownedTask` afterwards — so
    /// cancelling the (already finished) view task cannot reach it. This
    /// entry is the reliable teardown hook the view calls from
    /// `onDisappear`: it invalidates the current intent, REALLY cancels the
    /// timer/read, ends pull waiters and clears this page's pending/busy/
    /// loading state. Idempotent with the `isActive=false` suspend path
    /// (duplicate notifications are no-ops) and generation-safe: a teardown
    /// racing a NEWER request cannot touch it — a teardown always wins
    /// because it bumps the generation past everything.
    func pageTeardown() {
        suspend()
    }

    /// Original user retry — allowed only from failed/empty; loading accepts
    /// no second action, ready keeps no refresh entry in HOME-01 semantics.
    /// R-DB-01: retries run in the owned task too, so a re-tap really
    /// cancels an in-flight retry.
    func retry() async {
        switch state {
        case .failed, .empty:
            let request = generation + 1
            await awaitOwnedRead(
                request: request,
                startOwnedRead(debounced: false, bumpsTicket: false, fullPageReload: true))
        case .idle, .loading, .ready: break
        }
    }

    /// Synchronous re-tap entry from the App's read-only event counter.
    /// Deduplicates by token (a redelivered SAME token neither re-processes
    /// nor re-arms the window); every DISTINCT real re-tap immediately
    /// invalidates the old identity, cancels the old merge timer/read and
    /// ends superseded waiters, then re-arms "this tap + 300ms" — the
    /// trailing merge (HOME-RETAP-DEBOUNCE, 2026-10-20).
    func requestRefresh(_ token: UInt64) {
        guard token != lastHandledReTapToken else { return }
        lastHandledReTapToken = token
        startOwnedRead(debounced: true, bumpsTicket: false)
    }

    /// Failed/empty recovery reserves the same synchronous immediate slot
    /// as pulls; a second recovery cannot start while busy.
    func requestUserRetry() {
        switch state {
        case .failed, .empty: acceptImmediateRefresh()
        case .idle, .loading, .ready: break
        }
    }

    /// Retry entry for the refresh-failure hint row — a NEW refresh action,
    /// distinct from the original failed/empty retry; still immediate.
    func requestRetryRefresh() {
        guard refreshFailedHint else { return }
        acceptImmediateRefresh()
    }

    private func loadIfNeeded() async {
        switch state {
        case .idle:
            // R-DB-01: the first read runs in the SAME owned task as every
            // other read, so a re-tap (or visibility loss) really cancels it.
            // R-OWN-01: cancelling the awaiting caller cancels its own read
            // too. performOwnedRead from .idle is the original first-load UI
            // path (full-page loading, no indicator, cancel restores idle).
            let request = generation + 1
            await awaitOwnedRead(
                request: request, startOwnedRead(debounced: false, bumpsTicket: false))
        case .loading, .ready, .empty, .failed: break
        }
    }

    /// The owner task's read stage. Re-checks the LATEST identity,
    /// cancellation and page activity BEFORE touching the service (the
    /// debounce may have expired into a superseded or inactive page); with
    /// committed content (ready/empty) the snapshot stays visible behind
    /// `isRefreshing`, without any it reloads through the first-load UI.
    /// Only the current generation may commit or clear flags.
    private func performOwnedRead(request: Int, ticket: UInt64, fullPageReload: Bool = false)
        async
    {
        guard request == generation, isActive, !Task.isCancelled else {
            if request == generation {
                isRetapPending = false
                hasPendingOwnedRequest = false
            }
            return
        }
        isRetapPending = false
        defer { finishRefresh(ticket) }
        let keepsOldContent: Bool
        if fullPageReload {
            // R-OWN-02: the ORIGINAL retry()/drive-retry is a full-page
            // RELOAD with the first-load state model — even from empty the
            // page enters loading, and a failure becomes failed(error),
            // never a retained empty plus refresh hint.
            keepsOldContent = false
            state = .loading
        } else {
            switch state {
            case .ready, .empty:
                keepsOldContent = true
                isRefreshing = true
            case .failed, .idle:
                keepsOldContent = false
                state = .loading
            case .loading:
                // A merged re-tap that superseded a first read/retry (or an
                // in-flight reload): the full-page loading UI already shows.
                keepsOldContent = false
            }
        }
        defer {
            if request == generation {
                isRefreshing = false
                hasPendingOwnedRequest = false
                ownedTask = nil
            }
        }
        do {
            let snapshot = try await home.loadHome()
            guard request == generation, !Task.isCancelled else {
                settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
                return
            }
            commitDisplayState(for: snapshot)
        } catch is CancellationError {
            // Cancelled: close the indicator; a cancellation is never shown
            // as a failure, and a cancelled reload restores retained state.
            settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
        } catch {
            guard request == generation, !Task.isCancelled else {
                settleCancelledRefresh(request: request, keepsOldContent: keepsOldContent)
                return
            }
            if keepsOldContent {
                // Old ready/empty stays; only the hint asks for a retry.
                refreshFailedHint = true
            } else {
                let next = State.failed(error as? HomeLoadFailure ?? .networkUnavailable)
                state = next
                retainedState = next
            }
        }
    }

    /// Terminal settling for a cancelled refresh outcome — including a
    /// service that ignored cancellation and returned a value or a plain
    /// error. Only the request's OWN generation is settled (a superseded
    /// completion must not touch a newer refresh's state or flags); a
    /// reload-style refresh restores the retained state so the page can
    /// never stay stranded in loading.
    private func settleCancelledRefresh(request: Int, keepsOldContent: Bool) {
        guard request == generation else { return }
        isRefreshing = false
        if !keepsOldContent {
            state = retainedState ?? .idle
        }
    }

    private func commitDisplayState(for snapshot: HomeSnapshot) {
        let displayEmpty =
            snapshot.banners.isEmpty
            && snapshot.categories.isEmpty
            && snapshot.featured.isEmpty
            && snapshot.recommendations.isEmpty
            && snapshot.goods.isEmpty
            && snapshot.coupons.isEmpty
        let next: State = displayEmpty ? .empty(snapshot) : .ready(snapshot)
        state = next
        retainedState = next
    }

    /// Visibility lost: invalidate the in-flight generation, drop an un-run
    /// accepted refresh and close the indicator (returning never re-fires
    /// it), and restore the retained state (or idle); the cancelled task's
    /// stale commit is rejected by the generation guard.
    private func suspend() {
        generation += 1
        ownedTask?.cancel()
        ownedTask = nil
        isRetapPending = false
        hasPendingOwnedRequest = false
        finishRefresh(refreshTicket)
        isRefreshing = false
        if case .loading = state {
            state = retainedState ?? .idle
        }
    }
}
