import Foundation
import Combine

@MainActor
final class PhotoFeedViewModel: ObservableObject {
    @Published private(set) var state: PhotoFeedState

    let intent: PhotoQueryIntent
    private let facade: PhotoStoreFacade
    private var cancellable: AnyCancellable?

    init(intent: PhotoQueryIntent, facade: PhotoStoreFacade = .shared) {
        self.intent = intent
        self.facade = facade
        self.state = facade.feedState(for: intent)
        bind()
    }

    func requestNextPage() {
        facade.requestNextPage(intent: intent)
    }

    private func bind() {
        cancellable = facade.$feeds
            .compactMap { $0[self.intent] }
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.state = state
            }
    }
}
