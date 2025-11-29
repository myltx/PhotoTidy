import Foundation
import Photos
import Combine

final class PermissionsManager: ObservableObject {
    @Published var status: PHAuthorizationStatus

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.status = status
            }
        }
    }
}
