//
//  PhotosAuthorizationService.swift
//  FaceAI
//
//  Created by amir.lahav on 21/09/2020.
//

import Photos

public final class PhotosAuthorizationService {
    
    public static func checkPhotoLibraryPermission(completion: @escaping (Result<Void, PhotosAuthorizationError>) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited: completion(Result.success(()))
        //handle authorized status
        case .denied, .restricted : completion(Result.failure(.denied))
        //handle denied status
        case .notDetermined:
            // ask for permissions
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    switch status {
                    case .authorized, .limited: completion(Result.success(()))
                    case .denied, .restricted: completion(Result.failure(.denied))
                    case .notDetermined: completion(Result.failure(.notDetermined))
                        fatalError("should not be here \(PhotosAuthorizationService.self)")
                    @unknown default:
                        fatalError("should not be here \(PhotosAuthorizationService.self)")
                    }
                }
            }
        @unknown default:
            fatalError("should not be here \(PhotosAuthorizationService.self)")
        }
    }
}
