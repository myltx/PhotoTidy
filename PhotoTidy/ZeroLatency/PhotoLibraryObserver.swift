import Foundation
import Photos

final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private weak var fetchResult: PHFetchResult<PHAsset>?
    var onChange: ((PHFetchResultChangeDetails<PHAsset>) -> Void)?

    func startObserving(fetchResult: PHFetchResult<PHAsset>) {
        stopObserving()
        self.fetchResult = fetchResult
        PHPhotoLibrary.shared().register(self)
    }

    func stopObserving() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        fetchResult = nil
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let fetchResult,
              let details = changeInstance.changeDetails(for: fetchResult) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(details)
        }
    }
}
