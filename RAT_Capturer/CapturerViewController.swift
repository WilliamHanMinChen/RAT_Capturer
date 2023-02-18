//
//  TestCapturerViewController.swift
//  THEIA
//
//  Created by William Chen on 2023/1/22.
//

import UIKit
import AVFoundation
import Vision
import Accelerate



class CapturerViewController: ViewController {
    
    //Overlay layer when we detect a test
    private var detectionOverlay: CALayer! = nil

    //Test detection requests
    private var requests = [VNRequest]()
    
    //C and T detection requests
    private var ctRequests = [VNRequest]()
    
    //Pos/Neg requests
    private var interpretationReq = [VNRequest]()
    
    //Text recognition request
    lazy var textDetectionRequest: VNRecognizeTextRequest = {
        let textDetectRequest = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        return textDetectRequest
    }()
    
    
    //Saves the currently processed frame's CMSampleBuffer
    var currentFrameData: CMSampleBuffer?
    //Saves our current frame as CIImage
    var currentFrameCIImage: CIImage?
    //Counter for how many images we have taken
    var imageCounter = 0
    
    //Haptic feedback
    let hardImpact = UIImpactFeedbackGenerator(style: .heavy)
    let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    let softImpact = UIImpactFeedbackGenerator(style: .light)
    
    //Records down the time when we last gave haptic feedback
    var lastImapctTime: Date = Date()
    
    //counter used to process every 1,2, or n frame
    var counter = 0

    
    //Indicating whether we have already attempted to perform a segue or not
    var performedSegue = false
    
    //Scanning sound audio player
    var scanningSoundAudioPlayer: AVAudioPlayer?
    
    
    let ringerChangedSoundID: SystemSoundID = 1103
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()


        
        


    }
    
    
    
    func generateComposition(urls: [URL]) throws -> AVComposition {
        let composition = AVMutableComposition()
        let audioTracks = urls
            .map(AVAsset.init(url:))
            .flatMap { $0.tracks(withMediaType: .audio) }
        
        for audioTrack in audioTracks {
            guard
                let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            
            try compositionTrack.insertTimeRange(
                audioTrack.timeRange,
                of: audioTrack,
                at: .zero
            )
        }
        return composition
    }
    
    
    
    
    
    //MARK: Detecting Test Functions
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        
        let modelName = "detectRATV2"
        
        //Load the Corresponding ML file
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            //This is the model that is being ran and the call back method once the results have been processed
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                    
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        setupCTVision()
        setupPosNegVision()
        
        return error
    }
    
    //MARK: Detecting Test Functions
    @discardableResult
    func setupCTVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        let modelName = "CTFinderV1"
        
        //Output this frame
        //Get file manager
        //Get the paths
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        //Gets the documents directory
        let documentsDirectory = paths[0]
        //Gets our image file's path
        let fileURL = documentsDirectory.appendingPathComponent(imageCounter.description + ".png")
        
        //Load the Corresponding ML file
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            //This is the model that is being ran and the call back method once the results have been processed
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        var CCounter = 0
                        var TCounter = 0
                        //Loop through every result

                        for observation in results where observation is VNRecognizedObjectObservation {
                            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                                continue
                            }
                            
                            if objectObservation.labels[0].identifier == "C" {
                                CCounter += 1
                            } else if objectObservation.labels[0].identifier == "T" {
                                TCounter += 1
                            }
                        }
                        
                        if CCounter == 1 || TCounter == 1 {
                            self.hardImpact.impactOccurred()
                            self.lastImapctTime = Date()
                            //Depending on the distance, we give intervaled feedback
                            self.currentFrameCIImage = self.currentFrameCIImage?.oriented(.right)
                            
                            self.currentFrameCIImage?.saveImage(self.imageCounter.description + ".png", inDirectoryURL: documentsDirectory)
                            
                            self.imageCounter += 1
                            
                        }
                        
                        print("Found \(CCounter)C and \(TCounter)T")
                    }
                    
                })
            })
            self.ctRequests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    @discardableResult
    func setupPosNegVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        
        let modelName = "results_classification"
        
        //Load the Corresponding ML file
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            //This is the model that is being ran and the call back method once the results have been processed
            let classificationRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    guard let observations = request.results as? [VNClassificationObservation] else {
                        // Image classifiers, like MobileNet, only produce classification observations.
                        // However, other Core ML model types can produce other observations.
                        // For example, a style transfer model produces `VNPixelBufferObservation` instances.
                        print("VNRequest produced the wrong result type: \(type(of: request.results)).")
                        return
                    }
                    for observation in observations {
                        print("Result: \(observation.identifier) Confidence: \(observation.confidence)")
                    }
                    
                    
                })
            })
            self.interpretationReq = [classificationRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        
        return error
    }
    
    func handleDetectedText(request: VNRequest?, error: Error?) {
        
        // Check what was found
        guard let results = request?.results as? [VNRecognizedTextObservation] else {
                return
        }
        //Output this frame
        //Get file manager
        //Get the paths
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        //Gets the documents directory
        let documentsDirectory = paths[0]
        //Gets our image file's path
        let fileURL = documentsDirectory.appendingPathComponent(imageCounter.description + ".png")
        
//        //Loop through the results, only save those that have the "2019-nCov" string
//        for result in results {
//            if result.topCandidates(1).first?.string == "2019-nCoV" || result.topCandidates(1).first?.string == "COVID-19"{
//                //Save the image
//                //Print the confidence
//                print("Image saved, confidence: \(result.topCandidates(1).first?.confidence)")
//                currentFrameCIImage?.saveImage(self.imageCounter.description + ".png", inDirectoryURL: documentsDirectory)
//                self.imageCounter += 1
//            }
//
//        }
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            //Object bounds is a tuple with the boundaries of the object
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)

            
            //If there is only one result
            if results.count == 1 && (Double(objectBounds.width) / Double(objectBounds.height)) >= 2.8{
                
                //Output this frame
                //Get file manager
                //Get the paths
                let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                //Gets the documents directory
                let documentsDirectory = paths[0]
                //Gets our image file's path
                let fileURL = documentsDirectory.appendingPathComponent(imageCounter.description + ".png")
                
                
                //Convert it to UI Image
                guard let currentFrameData = currentFrameData else {
                    fatalError("Tried processing data before current frame is set!")
                }
                let imageBuffer = CMSampleBufferGetImageBuffer(currentFrameData)!
                
                let ciimage = CIImage(cvPixelBuffer: imageBuffer)
                
                
                let croppedImage = ciimage.cropped(to: objectBounds)
                
                //Assign our image to be saved
                self.currentFrameCIImage = croppedImage
                
                let exifOrientation = exifOrientationFromDeviceOrientation()
                
                
                
                let context = CIContext(options: nil)
                if let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) {
                    //This is called every frame
                    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: exifOrientation)
                    
                    do {
                        
                        //Do the text recognition requests
                        try handler.perform(self.ctRequests)
                        
                    } catch {
                        print(error)
                    }
                }
                
                
                
                
            }
            
            
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let exifOrientation = exifOrientationFromDeviceOrientation()
        
        
        //This is called every frame

        counter += 1
        //Only process every 3rd frame
        if counter % 3 != 0{
            return
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            //Performs vision requests (images to be processed)
            try imageRequestHandler.perform(self.requests)
            
            self.currentFrameData = sampleBuffer
            
            
        } catch {
            print(error)
        }
    }
    
    override func setupAVCapture() {
        super.setupAVCapture()
        
        // setup Vision parts
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        // start the capture
        startCaptureSession()
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
    
    
    // Convert CIImage to UIImage
    func convert(cmage: CIImage) -> UIImage {
         let context = CIContext(options: nil)
         let cgImage = context.createCGImage(cmage, from: cmage.extent)!
         let image = UIImage(cgImage: cgImage)
         return image
    }
    
}



extension CIImage {

    //https://stackoverflow.com/questions/27896410/given-a-ciimage-what-is-the-fastest-way-to-write-image-data-to-disk
    //Save to file path
    @objc func saveImage(_ name:String, inDirectoryURL:URL? = nil, quality:CGFloat = 1.0) -> String? {
        
        var destinationURL = inDirectoryURL
        
        if destinationURL == nil {
            destinationURL = try? FileManager.default.url(for:.documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
        
        if var destinationURL = destinationURL {
            
            destinationURL = destinationURL.appendingPathComponent(name)
            
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
                
                do {

                    let context = CIContext()

                    try context.writeJPEGRepresentation(of: self, to: destinationURL, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption : quality])
                    
                    let format = CIFormat.RGBA8
                    try context.writePNGRepresentation(of: self, to: destinationURL, format: format, colorSpace: colorSpace)
                    
                    
//                    try context.writePNGRepresentation(of: self, to: destinationURL, format: colorSpace, colorSpace: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption : quality])
                    
                    return destinationURL.path
                    
                } catch {
                    return nil
                }
            }
        }
        
        return nil
    }
}




extension UIImage {
        
    func convertToBuffer() -> CVPixelBuffer? {
        
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer)
        
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixelData,
            width: Int(self.size.width),
            height: Int(self.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: self.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
}

