import Foundation

/// 将所有 PhotoKit 请求集中到一个串行队列，避免在主线程上阻塞 UI。
enum PhotoKitThread {
    private static let queue = DispatchQueue(label: "com.phototidy.photokit", qos: .userInitiated)

    static func perform(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    static func performAfter(delay: DispatchTimeInterval, work: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
