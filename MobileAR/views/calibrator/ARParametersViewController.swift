// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit

class ARParametersViewController : UIViewController {
  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)

    // Set the title of the view.
    title = "Calibration"

    // White background colour.
    view.backgroundColor = UIColor.whiteColor()

    // Display the intrinsic matrix & distortion in MathML.
    var content : String = ""
    if let params = try? ARParameters.loadFromFile() {
        content =
          "<div>" +
            "<h3>Intrinsic matrix K</h3>" +
            "<math xmlns='http://www.w3.org/1998/Math/MathML' fontfamily='helvetica'>" +
              "<mrow>" +
                "<mo>[</mo>" +
                "<mtable>" +
                  "<mtr>" +
                    "<mtd><mn>\(params.fx)</mn></mtd>" +
                    "<mtd><mn>0</mn></mtd>" +
                    "<mtd><mn>\(params.cx)</mn></mtd>" +
                  "</mtr>" +
                  "<mtr>" +
                    "<mtd><mn>0</mn></mtd>" +
                    "<mtd><mn>\(params.fy)</mn></mtd>" +
                    "<mtd><mn>\(params.cy)</mn></mtd>" +
                  "</mtr>" +
                  "<mtr>" +
                    "<mtd><mn>0</mn></mtd>" +
                    "<mtd><mn>0</mn></mtd>" +
                    "<mtd><mn>1</mn></mtd>" +
                  "</mtr>" +
                "</mtable>" +
                "<mo>]</mo>" +
              "</mrow>" +
            "</math>" +
          "</div>" +
          "<div>" +
            "<h3>Distortion</h3>" +
            "<math xmlns='http://www.w3.org/1998/Math/MathML' fontfamily='helvetica'>" +
              "<mtable>" +
                "<mtr>" +
                  "<mtd><msub><mi>k</mi><mn>1</mn></msub></mrow></mtd>" +
                  "<mtd><mo>=</mo></mtd>" +
                  "<mtd><mn>\(params.k1)</mn></mtd>" +
                "</mtr>" +
                "<mtr>" +
                  "<mtd><msub><mi>k</mi><mn>2</mn></msub></mrow></mtd>" +
                  "<mtd><mo>=</mo></mtd>" +
                  "<mtd><mn>\(params.k2)</mn></mtd>" +
                "</mtr>" +
                "<mtr>" +
                  "<mtd><msub><mi>r</mi><mn>1</mn></msub></mrow></mtd>" +
                  "<mtd><mo>=</mo></mtd>" +
                  "<mtd><mn>\(params.r1)</mn></mtd>" +
                "</mtr>" +
                "<mtr>" +
                  "<mtd><msub><mi>r</mi><mn>2</mn></msub></mrow></mtd>" +
                  "<mtd><mo>=</mo></mtd>" +
                  "<mtd><mn>\(params.r2)</mn></mtd>" +
                "</mtr>" +
              "</mtable>" +
            "</math>" +
          "</div>"
    } else {
      content = "<div><h3>Camera not calibrated</h3></div>"
    }

    // Display content in a WebView.
    let webView = UIWebView(frame: self.view.frame)
    webView.loadHTMLString(
        "<!DOCTYPE html>" +
        "<html>" +
          "<head>" +
            "<style>" +
              "body { font-family: \"Helvetica\"; }" +
              "div { text-align: center }" +
            "</style>" +
          "</head>" +
          "<body>\(content)</body>" +
        "</html>",
        baseURL: nil
    )
    self.view.addSubview(webView)
  }
}
