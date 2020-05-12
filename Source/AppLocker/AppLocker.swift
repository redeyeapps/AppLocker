//
//  AppALConstants.swift
//  AppLocker
//
//  Created by Oleg Ryasnoy on 07.07.17.
//  Copyright © 2017 Oleg Ryasnoy. All rights reserved.
//

import UIKit
import AudioToolbox
import LocalAuthentication

public enum ALConstants {
    static let nibName = "AppLocker"
    static let kLocalizedReason = "Unlock with sensor" // Your message when sensors must be shown
    static let duration = 0.3 // Duration of indicator filling
    static let maxPinLength = 4
    
    enum button: Int {
        case delete = 1000
        case cancel = 1001
    }
}

public typealias onSuccessfulDismissCallback = (_ mode: ALMode?, _ pin: String?) -> () // Cancel dismiss will send mode as nil
public typealias onFailedAttemptCallback = (_ mode: ALMode) -> ()
public struct ALOptions { // The structure used to display the controller
    public var title: String?
    public var subtitle: String?
    public var backgroundImage: UIImage?
    public var image: UIImage?
    public var color: UIColor?
    public var isSensorsEnabled: Bool?
    public var onSuccessfulDismiss: onSuccessfulDismissCallback?
    public var onFailedAttempt: onFailedAttemptCallback?
    public init() {}
}

public enum ALMode { // Modes for AppLocker
    case validate(String?)
    case create
}

public class AppLocker: UIViewController {
    
    // MARK: - Top view
    @IBOutlet weak var backgroundImageView: UIImageView!
    @IBOutlet weak var photoImageView: UIImageView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var submessageLabel: UILabel!
    @IBOutlet var pinIndicators: [Indicator]!
    @IBOutlet weak var cancelButton: UIButton!
    
    // MARK: - Pincode
    private var onSuccessfulDismiss: onSuccessfulDismissCallback?
    private var onFailedAttempt: onFailedAttemptCallback?
    private let context = LAContext()
    private var pin = "" // Entered pincode
    private var reservedPin = "" // Reserve pincode for confirm
    private var validatingPin: String? // Provided pincode for validation
    private var isFirstCreationStep = true
    
    override open var shouldAutorotate: Bool {
        return false
    }

    override open var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        // https://stackoverflow.com/questions/56459329/disable-the-interactive-dismissal-of-presented-view-controller-in-ios-13
        modalPresentationStyle = .fullScreen
    }
    
    fileprivate var mode: ALMode = .validate(nil) {
        didSet {
            switch mode {
            case .validate(let pin):
                validatingPin = pin
                cancelButton.isHidden = true
                isFirstCreationStep = false
            case .create:
                cancelButton.isHidden = true
                isFirstCreationStep = true
                submessageLabel.text = ""
            }
        }
    }
    
    private func precreateSettings () {
        mode = .create
        clearView()
    }
    
    private func drawing(isNeedClear: Bool, tag: Int? = nil) { // Fill or cancel fill for indicators
        let results = pinIndicators.filter { $0.isNeedClear == isNeedClear }
        let pinView = isNeedClear ? results.last : results.first
        pinView?.isNeedClear = !isNeedClear
        
        UIView.animate(withDuration: ALConstants.duration, animations: {
            pinView?.backgroundColor = isNeedClear ? .clear : .white
        }) { _ in
            isNeedClear ? self.pin = String(self.pin.dropLast()) : self.pincodeChecker(tag ?? 0)
        }
    }
    
    private func pincodeChecker(_ pinNumber: Int) {
        if pin.count < ALConstants.maxPinLength {
            pin.append("\(pinNumber)")
            if pin.count == ALConstants.maxPinLength {
                switch mode {
                case .create:
                    createModeAction()
                case .validate:
                    validateModeAction()
                }
            }
        }
    }
    
    // MARK: - Modes
    private func createModeAction() {
        if isFirstCreationStep {
            isFirstCreationStep = false
            reservedPin = pin
            clearView()
            submessageLabel.text = "Confirm your pincode"
        } else {
            confirmPin()
        }
    }
    
    private func validateModeAction() {
        if pin == validatingPin {
            dismiss(animated: true) {
                self.onSuccessfulDismiss?(self.mode, self.pin)
            }
        } else {
            onFailedAttempt?(mode)
            incorrectPinAnimation()
        }
    }
    
    private func confirmPin() {
        if pin == reservedPin {
            dismiss(animated: true) {
                self.onSuccessfulDismiss?(self.mode, self.pin)
            }
        } else {
            onFailedAttempt?(mode)
            incorrectPinAnimation()
            precreateSettings()
        }
    }
    
    private func incorrectPinAnimation() {
        pinIndicators.forEach { view in
            view.shake(delegate: self)
            view.backgroundColor = .clear
        }
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    fileprivate func clearView() {
        pin = ""
        pinIndicators.forEach { view in
            view.isNeedClear = false
            UIView.animate(withDuration: ALConstants.duration, animations: {
                view.backgroundColor = .clear
            })
        }
    }
    
    // MARK: - Touch ID / Face ID
    fileprivate func checkSensors() {
        if case .validate = mode {} else { return }
        
        var policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics // iOS 8+ users with Biometric and Custom (Fallback button) verification
        
        // Depending the iOS version we'll need to choose the policy we are able to use
        if #available(iOS 9.0, *) {
            // iOS 9+ users with Biometric and Passcode verification
            policy = .deviceOwnerAuthentication
        }
        
        var err: NSError?
        // Check if the user is able to use the policy we've selected previously
        guard context.canEvaluatePolicy(policy, error: &err) else {return}
        
        // The user is able to use his/her Touch ID / Face ID 👍
        context.evaluatePolicy(policy, localizedReason: ALConstants.kLocalizedReason, reply: {  success, error in
            if success {
                DispatchQueue.main.async { [weak self] in
                    guard let `self` = self else { return }
                    self.dismiss(animated: true) {
                        self.onSuccessfulDismiss?(self.mode, nil)
                    }
                }
            }
        })
    }
    
    // MARK: - Keyboard
    @IBAction func keyboardPressed(_ sender: UIButton) {
        switch sender.tag {
        case ALConstants.button.delete.rawValue:
            drawing(isNeedClear: true)
        case ALConstants.button.cancel.rawValue:
            clearView()
            dismiss(animated: true) {
                self.onSuccessfulDismiss?(nil, nil)
            }
        default:
            drawing(isNeedClear: false, tag: sender.tag)
        }
    }
    
}

// MARK: - CAAnimationDelegate
extension AppLocker: CAAnimationDelegate {
    public func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        clearView()
    }
}

// MARK: - Present
public extension AppLocker {
    // Present AppLocker
    class func present(with mode: ALMode, and config: ALOptions? = nil, over viewController: UIViewController? = nil) {
        let vc = viewController ?? UIApplication.shared.keyWindow?.rootViewController
        guard let root = vc,
            
            let locker = Bundle(for: self.classForCoder()).loadNibNamed(ALConstants.nibName, owner: self, options: nil)?.first as? AppLocker else {
                return
        }
        locker.messageLabel.text = config?.title ?? ""
        locker.submessageLabel.text = config?.subtitle ?? ""
        locker.view.backgroundColor = config?.color ?? .black
        locker.mode = mode
        locker.onSuccessfulDismiss = config?.onSuccessfulDismiss
        locker.onFailedAttempt = config?.onFailedAttempt
        
        if config?.isSensorsEnabled ?? false {
            locker.checkSensors()
        }
        
        if let image = config?.image {
            locker.photoImageView.image = image
        } else {
            locker.photoImageView.isHidden = true
        }
        
        if let backgroundImage = config?.backgroundImage {
            locker.backgroundImageView.image = backgroundImage
        } else {
            locker.backgroundImageView.isHidden = true
        }
        
        root.present(locker, animated: true, completion: nil)
    }
}
