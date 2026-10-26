import AppKit
import GameController
import SwitchMacRuntime

@MainActor final class LauncherControllers {
    private weak var model: MacModel?
    private var observers: [NSObjectProtocol] = []
    private var controllers: [GCController] = []
    private var timer: Timer?
    private var navigation = ControllerNavigation()
    init(model: MacModel) {
        self.model = model
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updatePolling() }
            })
        }
        refresh()
    }
    private var acceptsInput: Bool {
        guard NSApp.isActive, let window = NSApp.keyWindow, window.isVisible,
              NSApp.modalWindow == nil, model?.message == nil, model?.isLaunching == false else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
        return true
    }
    private func refresh() {
        for controller in controllers {
            controller.extendedGamepad?.buttonA.pressedChangedHandler = nil
            controller.extendedGamepad?.buttonB.pressedChangedHandler = nil
            controller.extendedGamepad?.buttonMenu.pressedChangedHandler = nil
        }
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        model?.controllerNames = controllers.map { $0.vendorName ?? "Game controller" }
        for controller in controllers {
            controller.handlerQueue = .main
            controller.extendedGamepad?.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in guard let self, self.acceptsInput else { return }; self.model?.controllerConfirm() }
            }
            controller.extendedGamepad?.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in guard let self, self.acceptsInput else { return }; self.model?.controllerBack() }
            }
            controller.extendedGamepad?.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in guard let self, self.acceptsInput, self.model?.panel == nil else { return }; self.model?.panel = .library }
            }
        }
        updatePolling()
    }
    private func updatePolling() {
        navigation.reset(); timer?.invalidate(); timer = nil
        if NSApp.isActive && !controllers.isEmpty {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
            timer.tolerance = 0.01; RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }
    private func poll() {
        guard acceptsInput, model?.panel == nil else { navigation.reset(); return }
        var x: Float = 0, y: Float = 0
        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }
            for input in [pad.dpad, pad.leftThumbstick] {
                let ix = input.xAxis.value, iy = input.yAxis.value
                if max(abs(ix), abs(iy)) > max(abs(x), abs(y)) { x = ix; y = iy }
            }
        }
        if let direction = navigation.update(x: x, y: y, now: ProcessInfo.processInfo.systemUptime) { model?.controllerMove(direction) }
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        for c in controllers {
            c.extendedGamepad?.buttonA.pressedChangedHandler = nil
            c.extendedGamepad?.buttonB.pressedChangedHandler = nil
            c.extendedGamepad?.buttonMenu.pressedChangedHandler = nil
        }
        controllers = []
    }
}
