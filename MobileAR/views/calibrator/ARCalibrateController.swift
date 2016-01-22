// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class ARCalibrateController : UIViewController, ARCameraDelegate, ARCalibratorDelegate  {
  // UI Elements.
  private var imageView : UIImageView!
  private var spinnerView : UIActivityIndicatorView!
  private var textView : UILabel!
  private var progressView : UIProgressView!

  // Camera wrapper.
  private var camera : ARCamera!

  // Calibrator context.
  private var calibrator : ARCalibrator!

  /**
   Called when the view is first loaded.
   */
  override func viewDidLoad() {
    super.viewDidLoad()

    createUI()
  }

  /**
   Called before the view is going to be presented.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Reset the calibrator.
    calibrator = ARCalibrator(delegate: self)

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = true;
    navigationController?.setNavigationBarHidden(false, animated: animated)
    navigationController?.setToolbarHidden(true, animated: animated)

    // Set the background colour to black.
    view.backgroundColor = UIColor.blackColor()

    // Set the title.
    title = "Calibrate"

    // Add a button to navigat to the calibration parameters view.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Action,
        target: self,
        action: Selector("onViewParameters")
    )
    guard let _ = try? ARParameters.loadFromFile() else {
      navigationItem.rightBarButtonItem?.enabled = false
      return
    }
  }

  /**
   Called after the view was presented.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)

    createCamera()
    camera?.start()
  }

  /**
   Called before the view is going to be hidden.
   */
  override func viewWillDisappear(animated: Bool) {
    super.viewDidDisappear(animated)

    camera?.stop()
  }

  /**
   Called when the user wants to display the calibration params.
   */
  func onViewParameters() {
    navigationController?.pushViewController(ARParametersViewController(), animated: true)
  }

  /**
   Sets up the user interface.
   */
  private func createUI() {

    let frame = self.view.frame

    // Create an image in the center.
    var imageRect = CGRect()
    imageRect.size.width = frame.size.width
    imageRect.size.height = frame.size.height
    imageRect.origin.x = (frame.size.width - imageRect.size.width) / 2
    imageRect.origin.y = 0
    imageView = UIImageView(frame: imageRect)
    view.addSubview(imageView)

    // Progress bar on top of the image.
    var progressRect = CGRect()
    progressRect.size.width = 100
    progressRect.size.height = 0
    progressRect.origin.x = (frame.size.width - progressRect.size.width) / 2
    progressRect.origin.y = (frame.size.height - progressRect.size.height) / 2
    progressView = UIProgressView(frame: progressRect)
    progressView!.hidden = true
    view.addSubview(progressView)

    // Spinner shown during calibration.
    var spinnerRect = CGRect()
    spinnerRect.size.width = 20
    spinnerRect.size.height = 20
    spinnerRect.origin.x = (frame.size.width - spinnerRect.size.width) / 2
    spinnerRect.origin.y = (frame.size.height - spinnerRect.size.height) / 2
    spinnerView = UIActivityIndicatorView(frame: spinnerRect)
    view.addSubview(spinnerView)

    // Text view indicating status.
    var textRect = CGRect()
    textRect.size.width = 200
    textRect.size.height = 20
    textRect.origin.x = (frame.size.width - textRect.size.width) / 2
    textRect.origin.y = (frame.size.height - textRect.size.height) / 2 + 20
    textView = UILabel(frame: textRect)
    textView!.textColor = UIColor.whiteColor()
    textView!.textAlignment = .Center
    textView!.text = ""
    textView!.hidden = true
    view.addSubview(textView)
  }

  /**
   Called when the calibration process is completed.
   */
  func onComplete(rms: Float, params: ARParameters) {
    dispatch_async(dispatch_get_main_queue()) {
      self.textView.hidden = true
      self.progressView.hidden = true
      self.spinnerView.stopAnimating()

      let alert = UIAlertController(
          title: "Save",
          message: "Reprojection Error = \(rms)",
          preferredStyle: .Alert
      )

      alert.addAction(UIAlertAction(
         title: "Use",
          style: .Default)
      { (UIAlertAction) in
        self.navigationItem.rightBarButtonItem?.enabled = true
        ARParameters.saveToFile(params)
      })

      alert.addAction(UIAlertAction(
          title: "Retry",
          style: .Destructive)
      { (UIAlertAction) in
        self.calibrator = ARCalibrator(delegate: self)
      })

      self.presentViewController(alert, animated: true, completion: nil)
    }
  }

  /**
   Called when an image is processed by the calibrator.
   */
  func onProgress(progress: Float) {
    dispatch_async(dispatch_get_main_queue()) {
      if (progress < 1.0) {
        self.textView.hidden = false
        self.textView.text = "Capturing data"

        self.progressView.hidden = false
        self.progressView.progress = progress

        self.spinnerView.stopAnimating()
      } else {
        self.textView.hidden = false
        self.textView.text = "Calibrating"

        self.progressView.hidden = true

        self.spinnerView.startAnimating()
      }
    }
  }

  /**
   Handles a frame from the camera.
   */
  func onFrame(frame: UIImage) {
    dispatch_async(dispatch_get_main_queue()) {
      self.imageView.image = self.calibrator.findPattern(frame)
    }
  }

  /**
   Create the camera. If the user does not provide permission, ask for it.
   */
  func createCamera() {

    if let cam = try? ARCamera(delegate: self) {
      camera = cam
      return
    }

    let alert = UIAlertController(
        title: "Camera Permission",
        message: "Please enable the camera in Settings > MobileAR",
        preferredStyle: .Alert
    )

    alert.addAction(UIAlertAction(
        title: "Okay",
        style: .Default)
    { (UIAlertAction) in self.createCamera() })

    alert.addAction(UIAlertAction(
        title: "Back",
        style: .Cancel)
    { (UIAlertAction) in self.navigationController?.popToRootViewControllerAnimated(true) })

    presentViewController(alert, animated: true, completion: nil)
  }
}
