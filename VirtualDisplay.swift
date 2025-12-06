import Cocoa

// MARK: - App Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuItems: [String: NSMenuItem] = [:]
    private var currentResolution: String?

    private let resolutions: [(key: String, width: Int, height: Int, label: String)] = [
        ("4k", 3840, 2160, "3840×2160 (4K)"),
        ("1080p", 1920, 1080, "1920×1080 (1080p)"),
        ("720p", 1280, 720, "1280×720 (720p)")
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        handleLaunchArguments()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📺"

        let menu = NSMenu()

        for res in resolutions {
            let item = NSMenuItem(title: res.label, action: #selector(resolutionSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = res.key
            menu.addItem(item)
            menuItems[res.key] = item
        }

        menu.addItem(NSMenuItem.separator())

        let disableItem = NSMenuItem(title: "Disable", action: #selector(disable), keyEquivalent: "")
        disableItem.target = self
        disableItem.isHidden = true
        menu.addItem(disableItem)
        menuItems["disable"] = disableItem

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func handleLaunchArguments() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--start"), idx + 1 < args.count {
            let res = args[idx + 1]
            DispatchQueue.main.async { self.enableResolution(res) }
        }
    }

    @objc private func resolutionSelected(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if currentResolution != nil {
            relaunch(with: key)
        } else {
            enableResolution(key)
        }
    }

    private func enableResolution(_ key: String) {
        guard let res = resolutions.first(where: { $0.key == key }) else { return }

        if VirtualDisplayManager.shared.createDisplay(width: res.width, height: res.height, name: "Virtual \(key) Display") {
            currentResolution = key
            updateMenuState()
            statusItem.button?.title = "🖥️"
        }
    }

    private func updateMenuState() {
        for res in resolutions {
            menuItems[res.key]?.state = (res.key == currentResolution) ? .on : .off
        }
        menuItems["disable"]?.isHidden = (currentResolution == nil)
    }

    private func relaunch(with resolution: String? = nil) {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        if let res = resolution {
            task.arguments = ["--start", res]
        }
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func disable() {
        relaunch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Virtual Display Manager

class VirtualDisplayManager {
    static let shared = VirtualDisplayManager()
    private var display: AnyObject?

    func createDisplay(width: Int, height: Int, name: String, ppi: Int = 100) -> Bool {
        guard let DescriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let DisplayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let ModeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let SettingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            print("Failed to load CGVirtualDisplay classes - requires macOS with private API support")
            return false
        }

        // Configure display descriptor
        let descriptor = DescriptorClass.init()
        descriptor.setValue(UInt32(1), forKey: "vendorID")
        descriptor.setValue(UInt32(1), forKey: "productID")
        descriptor.setValue(UInt32(1), forKey: "serialNum")
        descriptor.setValue(name, forKey: "name")
        descriptor.setValue(UInt32(width), forKey: "maxPixelsWide")
        descriptor.setValue(UInt32(height), forKey: "maxPixelsHigh")

        let physicalSize = CGSize(
            width: 25.4 * Double(width) / Double(ppi),
            height: 25.4 * Double(height) / Double(ppi)
        )
        descriptor.setValue(NSValue(size: physicalSize), forKey: "sizeInMillimeters")

        // Color primaries (standard sRGB)
        descriptor.setValue(NSValue(point: NSPoint(x: 0.6797, y: 0.3203)), forKey: "redPrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.2559, y: 0.6983)), forKey: "greenPrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.1494, y: 0.0557)), forKey: "bluePrimary")
        descriptor.setValue(NSValue(point: NSPoint(x: 0.3125, y: 0.3291)), forKey: "whitePoint")
        descriptor.setValue(DispatchQueue.global(qos: .userInitiated), forKey: "queue")

        // Create display instance
        let allocSelector = NSSelectorFromString("alloc")
        guard let allocated = (DisplayClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() as? NSObject,
              let displayObj = allocated.perform(NSSelectorFromString("initWithDescriptor:"), with: descriptor)?.takeUnretainedValue() as? NSObject else {
            return false
        }

        // Configure display mode
        let settings = SettingsClass.init()
        settings.setValue(UInt32(0), forKey: "hiDPI")

        guard let modeAllocated = (ModeClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() as? NSObject else {
            return false
        }

        typealias ModeInitFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
        let modeSelector = NSSelectorFromString("initWithWidth:height:refreshRate:")
        let modeInit = unsafeBitCast(modeAllocated.method(for: modeSelector), to: ModeInitFunc.self)

        guard let mode = modeInit(modeAllocated, modeSelector, UInt32(width), UInt32(height), 60.0) as? NSObject else {
            return false
        }

        settings.setValue([mode], forKey: "modes")
        _ = displayObj.perform(NSSelectorFromString("applySettings:"), with: settings)

        // Retain to prevent deallocation
        _ = Unmanaged.passRetained(displayObj)
        display = displayObj

        let displayID = displayObj.value(forKey: "displayID") as? UInt32 ?? 0
        print("Created virtual display \(width)×\(height) with ID: \(displayID)")

        return true
    }
}
