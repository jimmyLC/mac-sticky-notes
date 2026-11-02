import Foundation

/// Free allows a limited number of memos; Pro has no limit.
public enum Plan: String, Codable, Sendable {
    case free
    case pro

    public static let freeMemoLimit = 10

    public var memoLimit: Int? {
        self == .free ? Self.freeMemoLimit : nil
    }

    public func canCreateMemo(currentCount: Int) -> Bool {
        guard let limit = memoLimit else { return true }
        return currentCount < limit
    }

    /// Text for the plan tag: "FREE 3/10" or "PRO".
    public func tagText(currentCount: Int) -> String {
        guard let limit = memoLimit else { return "PRO" }
        return "FREE \(currentCount)/\(limit)"
    }
}
