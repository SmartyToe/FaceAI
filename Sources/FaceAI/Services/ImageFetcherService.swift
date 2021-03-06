//
//  ImageFetcherService.swift
//  
//
//  Created by amir.lahav on 21/09/2020.
//

import Foundation
import Photos
import UIKit

class ImageFetcherService {
    
    private let imgManager = PHImageManager.default()
    private let options: ImageFetcherOptions
    
    /// This service help to fetch image from PHAssets
    /// - Parameter options: class options include image size etc.
    init(options: ImageFetcherOptions = ImageFetcherOptions()) {
        self.options = options
    }
    
    func image(from phAsset: PHAsset) -> UIImage?  {

        return autoreleasepool { () -> UIImage? in
            var myImage:UIImage?
                let semaphore = DispatchSemaphore(value: 0)
                
            imgManager.requestImageDataAndOrientation(for: phAsset, options: options.rquestOptions) { [self] (data, str, ori, _) in
                    myImage = data?.downSmaple(to: CGSize(width: options.downsampleImageSize, height: options.downsampleImageSize), scale: UIScreen.main.scale)
                    semaphore.signal()
                }
            _ = semaphore.wait(wallTimeout: .distantFuture)
            return myImage
        }
    }
    
    func image(from identifier: String) -> UIImage?  {

        return autoreleasepool { () -> UIImage? in
            var myImage:UIImage?
                let semaphore = DispatchSemaphore(value: 0)
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
                return nil
            }
            imgManager.requestImageDataAndOrientation(for: asset, options: options.rquestOptions) { [self] (data, str, ori, _) in
                    myImage = data?.downSmaple(to: CGSize(width: options.downsampleImageSize, height: options.downsampleImageSize), scale: UIScreen.main.scale)
                    semaphore.signal()
                }
            _ = semaphore.wait(wallTimeout: .distantFuture)
            return myImage
        }
    }
    
    private func cgImage(from phAsset: PHAsset) -> CGImage? {

        return autoreleasepool { () -> CGImage? in
            var myImage:CGImage?
                let semaphore = DispatchSemaphore(value: 0)
                
            imgManager.requestImageDataAndOrientation(for: phAsset, options: options.rquestOptions) { [self] (data, str, ori, _) in
                myImage = data?.downSmaple(to: CGSize(width: options.downsampleImageSize, height: options.downsampleImageSize), scale: UIScreen.main.scale)
                    semaphore.signal()
                }
                _ = semaphore.wait(wallTimeout: .distantFuture)
            return myImage
        }
    }
    
    private func image(form localPath: String) -> UIImage? {
        UIImage(contentsOfFile: localPath)
    }
}
