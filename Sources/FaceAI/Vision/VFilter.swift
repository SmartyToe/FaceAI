//
//  ImageAnalyzer.swift
//
//  Created by amir.lahav on 10/11/2019.
//  Copyright © 2019 la-labs. All rights reserved.
//

import Foundation
import Vision
import CoreML
import UIKit

typealias Pipe = (ProcessAsset) throws -> ProcessedAsset
public typealias VisionFilter = (ProcessAsset) throws -> ProcessAsset
typealias CustomFilter<T> = (CustomProcessAsset) throws -> T


public class VFilter {
    
    struct Constant {
        static let lowResImageArea: CGFloat = 1200
    }
    
    static func filter(type: VisionProcessType) -> VisionFilter {
        switch type {
        case .faceDetection:
            return faceRectangle()
        case .objectDetection:
            return tagPhoto
        case .imageQuality:
            return imageQuality
        case .imageFatching:
            return fetchAsset
        }
    }
    
    public static func faceRectangle() -> VisionFilter {
        return { asset in
            return try faceRectangle(asset: asset)
        }
    }
    
    public static func objectDetection() -> VisionFilter {
        return { asset in
            return try tagPhoto(asset: asset)
        }
    }
    
    public static func imageQuality() -> VisionFilter {
        return { asset in
            return try imageQuality(asset: asset)
        }
    }
    
    /// Detect bounding box around faces in image
    ///
    /// - Parameter asset: User image
    ///
    /// - Returns: ImageObservation struct include vision bounding rect, original image, and image size
    private static func faceRectangle(asset: ProcessAsset) throws -> ProcessAsset {
        return try autoreleasepool { () -> ProcessAsset in
            let requestHandler = VNImageRequestHandler(cgImage: (asset.image.cgImage!), options: [:])
            let request = VNDetectFaceRectanglesRequest()
            try requestHandler.perform([request])
            guard let observations = request.results as? [VNFaceObservation] else {
                throw VisionProcessError.facesDetcting
            }
    //            guard !observations.isEmpty else {
//                throw FaceClustaringError.emptyObservation
//            }
            return ProcessAsset(identifier: asset.identifier,
                                image: asset.image, tags: asset.tags,
                                faceQuality: asset.faceQuality,
                                observation: mapBoundignBoxToRects(observation: observations),
                                faces: [])
        }
    }
    
    static func featureDetection(asset: ProcessAsset) throws -> ProcessAsset {
        return try autoreleasepool { () -> ProcessAsset in
            let requestHandler = VNImageRequestHandler(cgImage: (asset.image.cgImage!), options: [:])
            let request = VNDetectFaceLandmarksRequest()
            try requestHandler.perform([request])
            guard let observations = request.results as? [VNFaceObservation] else {
                throw VisionProcessError.facesDetcting
            }
            let faces = observations.compactMap { (observation) -> Face? in
                let area = observation.boundingBox.size.scale(imageSize: asset.image.size).area
                // remove low res face chip
                if area < Constant.lowResImageArea {
                    return nil
                }
                return Face(localIdnetifier: asset.identifier, faceID: "", faceCroppedImage: UIImage(), meanEmbedded: [], faceFeatures: observation, quality: 0)
            }
            return ProcessAsset(identifier: asset.identifier,
                                image: asset.image,
                                tags: asset.tags,
                                faceQuality: asset.faceQuality,
                                observation: mapBoundignBoxToRects(observation: observations),
                                faces: faces)
        }
    }
    
    static func embbedFaces(asset: ProcessAsset) throws -> ProcessAsset {
        return try autoreleasepool { () -> ProcessAsset in
            let url = Bundle.module.url(forResource: "facenet_keras_weights_coreml", withExtension: ".mlmodelc")
            let model = try facenet_keras_weights_coreml(contentsOf: url!, configuration: MLModelConfiguration()).model
            let request = VNCoreMLRequest(model: try VNCoreMLModel(for: model))
            var faces = asset.faces.map({extractChip(face: $0, image: asset.image)})
            faces = try faces.map({ (face) -> Face in
                let MLRequestHandler = VNImageRequestHandler(cgImage: face.faceCroppedImage.cgImage!, options: [:])
                try MLRequestHandler.perform([request])
                return genEmbeddingsHandler(face: face, request: request)
            })
            return ProcessAsset(identifier: asset.identifier,
                                image: asset.image,
                                tags: asset.tags,
                                faceQuality: asset.faceQuality,
                                observation: asset.observation,
                                faces: faces)
        }
    }
    
    static func imageQuality(asset: ProcessAsset) throws -> ProcessAsset {
        return try autoreleasepool { () -> ProcessAsset in
            let requestHandler = VNImageRequestHandler(cgImage: (asset.image.cgImage!), options: [:])
            let request = VNDetectFaceCaptureQualityRequest()
            try requestHandler.perform([request])
//            guard let observation = request.results?.first as? VNFaceObservation else {
//                throw FaceClustaringError.facesDetcting
//            }
            return ProcessAsset(identifier: asset.identifier,
                                image: asset.image,
                                tags: asset.tags,
                                faceQuality: (request.results?.first as? VNFaceObservation)?.faceCaptureQuality ?? 0,
                                observation: asset.observation,
                                faces: [])
        }
    }
    
    static func tagPhoto(asset: ProcessAsset) throws -> ProcessAsset {
        return try autoreleasepool { () -> ProcessAsset in
            let requestHandler = VNImageRequestHandler(cgImage: (asset.image.cgImage!), options: [:])
            let request = VNClassifyImageRequest()
            try requestHandler.perform([request])
            var categories: [String] = []

            if let observations = request.results as? [VNClassificationObservation] {
                categories = observations
                    .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
                    .reduce(into: [String]()) { arr, observation in arr.append(observation.identifier)  }
            }
            
            return ProcessAsset(identifier: asset.identifier,
                                image: asset.image,
                                tags: categories,
                                faceQuality: asset.faceQuality,
                                observation: asset.observation,
                                faces: [])
        }
    }
    
    static func custom<T>(model: MLModel) -> CustomFilter<T> {
        return { asset in
            return try autoreleasepool { () -> T in
                guard let model = try? VNCoreMLModel(for: model) else {
                    throw VisionProcessError.unknown
                }
                let request =  VNCoreMLRequest(model:model)
                request.imageCropAndScaleOption = .centerCrop
                let requestHandler = VNImageRequestHandler(cgImage: (asset.image.cgImage!), options: [:])
                try requestHandler.perform([request])
                guard let results = request.results as? T else {
                    throw VisionProcessError.unknown
                }
                return results
            }
        }
    }
    
    // Fetch image from PHAsset
    static func fetchAsset(asset: ProcessAsset) throws -> ProcessAsset {
        return autoreleasepool { () -> ProcessAsset in
        let imageFetcher = ImageFetcherService()
        if let image = imageFetcher.image(from: asset.identifier) {
            return ProcessAsset(identifier: asset.identifier,
                                image: image, tags: [],
                                faceQuality: 0,
                                observation: [],
                                faces: [])
        }
            return ProcessAsset(identifier: asset.identifier, image: UIImage(), tags: [], faceQuality: 0, observation: [], faces: [])
        }
    }
    
    // Convert PocessAsset To ProcessedAsset
    // Remove main image to reduce ram print
    static func clean(asset: ProcessAsset) throws -> ProcessedAsset {
        ProcessedAsset(asset: asset)
    }
}

private extension VFilter {
    
    static func mapBoundignBoxToRects(observation: [VNFaceObservation]) -> [CGRect] {
        observation.map(convertRect)
    }
    
    static func convertRect(face: VNFaceObservation) -> CGRect {
        return face.boundingBox
    }
    
    static func genEmbeddingsHandler(face: Face, request: VNRequest) -> Face {
        guard let observations = request.results as? [ VNCoreMLFeatureValueObservation] ,
              let firstObserve = observations.first,
              let emb = firstObserve.featureValue.multiArrayValue else {
            return face
        }
        let embbeded =  [buffer2Array(length: emb.count, data: emb.dataPointer, Double.self)]  |> average |> norm_l2
        return Face(localIdnetifier: face.localIdnetifier, faceID: face.faceID, faceCroppedImage: face.faceCroppedImage, meanEmbedded: embbeded, faceFeatures: face.faceFeatures, quality: face.quality)
    }
    
    static func buffer2Array<T>(length: Int, data: UnsafeMutableRawPointer, _: T.Type) -> [T] {
        let ptr = data.bindMemory(to: T.self, capacity: length)
        let buffer = UnsafeBufferPointer(start: ptr, count: length)
        return Array(buffer)
    }
    
    static func norm_l2(emb: [Double]) -> [Double] {
        let sum: Double = emb.reduce(0) { (result, next) in
            return result + next * next
        }
        let emb: [Double] = emb.compactMap({ return $0/sqrt(sum) })
        return emb
    }
    
    static func average(arrays: [[Double]] ) -> [Double] {
        var average:[Double] = []
        if !(arrays.count > 0) {
            return arrays.first!
        }
        for i in 0...arrays.first!.count - 1 {
            var columSum:Double = 0.0
            for j in 0...arrays.count - 1 {
                 columSum += arrays[j][i]
            }
            average.append(columSum/Double(arrays.count))
        }
        return average
    }
    
    static func extractChip(face: Face, image: UIImage) -> Face {
        let chipImage = Interpulation.extractImageChip(image, chipDetail: Interpulation.getFaceChipDetails(det: face.faceFeatures, imageSize: image.size, size: 160, padding: 0.4), observation: face.faceFeatures) ?? UIImage()
        return Face(localIdnetifier: face.localIdnetifier,
             faceID: face.faceID,
             faceCroppedImage: chipImage,
             meanEmbedded: face.meanEmbedded,
             faceFeatures: face.faceFeatures,
             quality: face.quality)
    }
}
