@testable import SwiftAssRenderer

final class MockDispatchQueue: DispatchQueueType {
    let executeAsyncFunc = FuncCheck<Void>()
    func executeAsync(_ work: @escaping () -> Void) {
        executeAsyncFunc.call()
        work()
    }
}

final class MockDeferredDispatchQueue: DispatchQueueType, @unchecked Sendable {
    private(set) var pendingWork: [() -> Void] = []

    func executeAsync(_ work: @escaping () -> Void) {
        pendingWork.append(work)
    }

    func runPendingWork() {
        while !pendingWork.isEmpty {
            pendingWork.removeFirst()()
        }
    }
}
