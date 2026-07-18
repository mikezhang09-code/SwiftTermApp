//
//  UIKitRoot.swift: UIKit APIs to deal with root windows, and root view controllers
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 5/9/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI

/// getCurrentKeyWindow: returns the current key window from the application
@MainActor
func getCurrentKeyWindow () -> UIWindow? {
    func tryGetWindow (desiredState: UIScene.ActivationState) -> UIWindow? {
        return UIApplication.shared.connectedScenes
              .filter { $0.activationState == desiredState }
              .compactMap { $0 as? UIWindowScene }
              .first?.windows
              .filter { $0.isKeyWindow }
              .first
    }
    let states: [UIScene.ActivationState] = [.foregroundActive, .foregroundInactive, .background, .unattached]
    for x in states {
        if let window = tryGetWindow(desiredState: x) {
            return window
        }
    }
    return nil
}

@MainActor
func getParentViewController (hint: UIResponder? = nil) -> UIViewController? {
    var parentResponder = hint
    while parentResponder != nil {
        parentResponder = parentResponder?.next
        if let viewController = parentResponder as? UIViewController {
            return viewController
        }
    }

    // playing with fire here
    return getCurrentKeyWindow()?.rootViewController
}

/// Like `getParentViewController`, but retries for a short while before giving up.
///
/// On the very first connection to a host the SSH handshake can reach the host-key
/// prompt before the terminal view is attached to a window (and before the key window
/// has settled after the navigation push), so a single lookup returns nil and the
/// prompt is silently skipped.  Waiting a few hundred milliseconds lets the view
/// hierarchy settle so the dialog can actually be presented.
@MainActor
func awaitParentViewController (hint: UIResponder? = nil, timeout: TimeInterval = 3.0) async -> UIViewController? {
    let deadline = Date ().addingTimeInterval (timeout)
    while true {
        // Prefer a presentable controller: one that is in a window and not mid-transition
        if let vc = getParentViewController (hint: hint), vc.viewIfLoaded?.window != nil {
            return vc
        }
        if Date () >= deadline {
            // Last resort: whatever we can find, even if not ideally attached
            return getParentViewController (hint: hint)
        }
        try? await Task.sleep (nanoseconds: 100_000_000)
    }
}



