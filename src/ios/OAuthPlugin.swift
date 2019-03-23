/**
 * Copyright 2019 Ayogo Health Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import os.log
import Foundation
import AuthenticationServices
import SafariServices

@objc protocol OAuthSessionProvider {
    init(_ endpoint : URL, callbackScheme : String)
    func start() -> Void
    func cancel() -> Void
}

@available(iOS 12.0, *)
class ASWebAuthenticationSessionOAuthSessionProvider : OAuthSessionProvider {
    private var aswas : ASWebAuthenticationSession

    required init(_ endpoint : URL, callbackScheme : String) {
        self.aswas = ASWebAuthenticationSession(url: endpoint, callbackURLScheme: callbackScheme, completionHandler: { (callBack:URL?, error:Error?) in
            if let incomingUrl = callBack {
                NotificationCenter.default.post(name: NSNotification.Name.CDVPluginHandleOpenURL, object: incomingUrl)
            }
        })
    }

    func start() {
        self.aswas.start()
    }

    func cancel() {
        self.aswas.cancel()
    }
}

@available(iOS 11.0, *)
class SFAuthenticationSessionOAuthSessionProvider : OAuthSessionProvider {
    private var sfas : SFAuthenticationSession

    required init(_ endpoint : URL, callbackScheme : String) {
        self.sfas = SFAuthenticationSession(url: endpoint, callbackURLScheme: callbackScheme, completionHandler: { (callBack:URL?, error:Error?) in
            if let incomingUrl = callBack {
                NotificationCenter.default.post(name: NSNotification.Name.CDVPluginHandleOpenURL, object: incomingUrl)
            }
        })
    }

    func start() {
        self.sfas.start()
    }

    func cancel() {
        self.sfas.cancel()
    }
}

@available(iOS 9.0, *)
class SFSafariViewControllerOAuthSessionProvider : OAuthSessionProvider {
    private var sfvc : SFSafariViewController

    var viewController : UIViewController?
    var delegate : SFSafariViewControllerDelegate?

    required init(_ endpoint : URL, callbackScheme : String) {
        self.sfvc = SFSafariViewController(url: endpoint)
    }

    func start() {
        if self.delegate != nil {
            self.sfvc.delegate = self.delegate
        }

        self.viewController?.present(self.sfvc, animated: true, completion: nil)
    }

    func cancel() {
        self.sfvc.dismiss(animated: true, completion:nil)
    }
}

class SafariAppOAuthSessionProvider : OAuthSessionProvider {
    var url : URL;

    required init(_ endpoint : URL, callbackScheme : String) {
        self.url = endpoint
    }

    func start() {
        UIApplication.shared.openURL(url)
    }

    // We can't do anything here
    func cancel() { }
}


@objc(CDVOAuthPlugin)
class OAuthPlugin : CDVPlugin, SFSafariViewControllerDelegate {
    var authSystem : OAuthSessionProvider?
    var callbackScheme : String?
    var logger : OSLog?

    override func pluginInitialize() {
        let appID = Bundle.main.bundleIdentifier!

        self.callbackScheme = "\(appID)://oauth_callback"
        self.logger = OSLog(subsystem: appID, category: "Cordova")

        NotificationCenter.default.addObserver(self,
                selector: #selector(OAuthPlugin._handleOpenURL(_:)),
                name: NSNotification.Name.CDVPluginHandleOpenURL,
                object: nil)
    }


    @objc func startOAuth(_ command : CDVInvokedUrlCommand) {
        guard let authEndpoint = command.argument(at: 0) as? String else {
            self.commandDelegate.send(CDVPluginResult(status: .error), callbackId: command.callbackId)
            return
        }

        guard let url = URL(string: authEndpoint) else {
            self.commandDelegate.send(CDVPluginResult(status: .error), callbackId: command.callbackId)
            return
        }

        if #available(iOS 12.0, *) {
            self.authSystem = ASWebAuthenticationSessionOAuthSessionProvider(url, callbackScheme:self.callbackScheme!)
        } else if #available(iOS 11.0, *) {
            self.authSystem = SFAuthenticationSessionOAuthSessionProvider(url, callbackScheme:self.callbackScheme!)
        } else if #available(iOS 9.0, *) {
            self.authSystem = SFSafariViewControllerOAuthSessionProvider(url, callbackScheme:self.callbackScheme!)

            if let sfvc = self.authSystem as? SFSafariViewControllerOAuthSessionProvider {
                sfvc.delegate = self
                sfvc.viewController = self.viewController
            }
        } else {
            self.authSystem = SafariAppOAuthSessionProvider(url, callbackScheme:self.callbackScheme!)
        }

        self.authSystem?.start()

        self.commandDelegate.send(CDVPluginResult(status: .ok), callbackId: command.callbackId)
        return
    }


    internal func parseToken(from url: URL) {
        self.authSystem?.cancel()
        self.authSystem = nil

        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter({$0.name == "access_token"}).first?.value else {
            return
        }

        os_log("OAuth called back with access token. %{private}@", log: self.logger!, type: .info, token)

        self.webViewEngine.evaluateJavaScript("window.dispatchEvent(new MessageEvent('message', { data: 'access_token:\(token)' }));", completionHandler: nil)
    }


    @objc internal func _handleOpenURL(_ notification : NSNotification) {
        guard let url = notification.object as? URL else {
            return
        }

        if !url.absoluteString.hasPrefix(self.callbackScheme!) {
            return
        }

        self.parseToken(from: url)
    }


    @available(iOS 9.0, *)
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
       self.authSystem?.cancel()
       self.authSystem = nil
    }
}
