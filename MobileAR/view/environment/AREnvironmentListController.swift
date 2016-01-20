// This file is part of the MobileAR Project.
// Licensing information can be found in the LICENSE file.
// (C) 2015 Nandor Licker. All rights reserved.

import UIKit


/**
 View controller responsible with displaying a list of prepared environments.
 */
class AREnvironmentListController : UIViewController, UITableViewDelegate, UITableViewDataSource {
  private var environments : [AREnvironment] = []

  /**
   Called when the view is loaded.
   */
  override func viewDidLoad() {
    super.viewDidLoad();

    // Create the table view.
    let table = UITableView(frame: view.frame, style: .Plain)
    table.registerClass(UITableViewCell.self, forCellReuseIdentifier: "environment")
    table.delegate = self
    table.dataSource = self
    view = table
  }

  /**
   Called before the view is displayed.
   */
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)

    // Hide the toolbar and show the navigation bar.
    navigationController?.hidesBarsOnSwipe = false;
    navigationController?.setNavigationBarHidden(false, animated: animated)

    // Set the title of the view.
    title = "Select"

    // Add a button to navigate to sphere capture.
    navigationItem.rightBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .Add,
        target: self,
        action: Selector("onCapture")
    )

    // Reload the data in the table view.
    environments = AREnvironment.all();
    (view as? UITableView)?.reloadData()
  }

  /**
   Called after the view is displayed.
   */
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
  }

  /**
   Called when the user clicks the Capture button.
   */
  func onCapture() {
    self.navigationController?.pushViewController(
        AREnvironmentCaptureController(),
        animated: true
    )
  }

  /**
   Returns the number of environments.
   */
  func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return environments.count
  }

  /**
   Creates a cell in a table for an item.
   */
  func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let env = environments[indexPath.indexAtPosition(0)]

    var cell = tableView.dequeueReusableCellWithIdentifier("environment") as UITableViewCell!
    cell.textLabel?.text = "LOL"
    return cell
  }

  /**
   Displays the chosen environment.
   */
  func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    let env = environments[indexPath.indexAtPosition(0)]

    self.navigationController?.pushViewController(
        AREnvironmentViewController(),
        animated: true
    )
  }
}
