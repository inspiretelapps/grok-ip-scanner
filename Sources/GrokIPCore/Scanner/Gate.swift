actor Gate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ available: Int) {
        self.available = max(1, available)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }
}
