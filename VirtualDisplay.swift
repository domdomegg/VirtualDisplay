import Cocoa
import Foundation

// Store displays in a way that prevents deallocation
var displayStorage: [Int: AnyObject] = [:]
var displayCounter = 0

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var item4k: NSMenuItem!
    var item1080p: NSMenuItem!
    var item720p: NSMenuItem!
    var restartItem: NSMenuItem!
    var currentDisplayId: Int? = nil
    var currentRes: String? = nil

    let ppi = 100

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "📺"
        }

        let menu = NSMenu()

        item4k = NSMenuItem(title: "3840×2160 (4K)", action: #selector(enable4k), keyEquivalent: "")
        item4k.target = self
        menu.addItem(item4k)

        item1080p = NSMenuItem(title: "1920×1080 (1080p)", action: #selector(enable1080p), keyEquivalent: "")
        item1080p.target = self
        menu.addItem(item1080p)

        item720p = NSMenuItem(title: "1280×720 (720p)", action: #selector(enable720p), keyEquivalent: "")
        item720p.target = self
        menu.addItem(item720p)

        menu.addItem(NSMenuItem.separator())

        restartItem = NSMenuItem(title: "Disable", action: #selector(restart), keyEquivalent: "")
        restartItem.target = self
        restartItem.isHidden = true
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Check for --start argument to auto-enable a resolution
        let args = CommandLine.arguments
        if let startIdx = args.firstIndex(of: "--start"), startIdx + 1 < args.count {
            let res = args[startIdx + 1]
            DispatchQueue.main.async {
                if res == "4k" {
                    self.enable4k()
                } else if res == "1080p" {
                    self.enable1080p()
                } else if res == "720p" {
                    self.enable720p()
                }
            }
        }
    }

    func enableDisplay(width: Int, height: Int, name: String, res: String) {
        // If already have a display, restart with new resolution
        if currentDisplayId != nil {
            restartWithRes(res)
            return
        }

        if let display = createVirtualDisplay(width: width, height: height, ppi: ppi, hiDPI: false, name: name) {
            displayCounter += 1
            currentDisplayId = displayCounter
            currentRes = res
            displayStorage[displayCounter] = display

            item4k.state = (res == "4k") ? .on : .off
            item1080p.state = (res == "1080p") ? .on : .off
            item720p.state = (res == "720p") ? .on : .off
            restartItem.isHidden = false

            if let button = statusItem.button {
                button.title = "🖥️"
            }
            print("Virtual display enabled: \(res)")
        }
    }

    @objc func enable4k() {
        enableDisplay(width: 3840, height: 2160, name: "Virtual 4K Display", res: "4k")
    }

    @objc func enable1080p() {
        enableDisplay(width: 1920, height: 1080, name: "Virtual 1080p Display", res: "1080p")
    }

    @objc func enable720p() {
        enableDisplay(width: 1280, height: 720, name: "Virtual 720p Display", res: "720p")
    }

    func restartWithRes(_ res: String) {
        // Relaunch the app with resolution argument
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["--start", res]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc func restart() {
        // Relaunch the app
        let url = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        do {
            try NSWorkspace.shared.launchApplication(at: url, options: [.newInstance], configuration: [:])
        } catch {
            // Fallback: use Process
            let task = Process()
            task.executableURL = url
            try? task.run()
        }
        NSApp.terminate(nil)
    }

    @objc func quit() {
        displayStorage.removeAll()
        NSApp.terminate(nil)
    }
}

func createVirtualDisplay(width: Int, height: Int, ppi: Int, hiDPI: Bool, name: String) -> AnyObject? {
    guard let DescriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
          let DisplayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
          let ModeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
          let SettingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
        print("Failed to load CGVirtualDisplay classes")
        return nil
    }

    let descriptor = DescriptorClass.init()
    descriptor.setValue(UInt32(1), forKey: "vendorID")
    descriptor.setValue(UInt32(1), forKey: "productID")
    descriptor.setValue(UInt32(1), forKey: "serialNum")
    descriptor.setValue(name, forKey: "name")
    descriptor.setValue(NSValue(size: CGSize(width: 25.4 * Double(width) / Double(ppi),
                                              height: 25.4 * Double(height) / Double(ppi))),
                        forKey: "sizeInMillimeters")
    descriptor.setValue(UInt32(width), forKey: "maxPixelsWide")
    descriptor.setValue(UInt32(height), forKey: "maxPixelsHigh")

    descriptor.setValue(NSValue(point: NSPoint(x: 0.6797, y: 0.3203)), forKey: "redPrimary")
    descriptor.setValue(NSValue(point: NSPoint(x: 0.2559, y: 0.6983)), forKey: "greenPrimary")
    descriptor.setValue(NSValue(point: NSPoint(x: 0.1494, y: 0.0557)), forKey: "bluePrimary")
    descriptor.setValue(NSValue(point: NSPoint(x: 0.3125, y: 0.3291)), forKey: "whitePoint")
    descriptor.setValue(DispatchQueue.global(qos: .userInitiated), forKey: "queue")

    let allocSelector = NSSelectorFromString("alloc")
    guard let allocated = (DisplayClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() as? NSObject else {
        return nil
    }

    let initSelector = NSSelectorFromString("initWithDescriptor:")
    guard let display = allocated.perform(initSelector, with: descriptor)?.takeUnretainedValue() as? NSObject else {
        return nil
    }

    let settings = SettingsClass.init()
    settings.setValue(hiDPI ? UInt32(1) : UInt32(0), forKey: "hiDPI")

    let modeWidth = hiDPI ? width / 2 : width
    let modeHeight = hiDPI ? height / 2 : height

    guard let modeAllocated = (ModeClass as AnyObject).perform(allocSelector)?.takeUnretainedValue() as? NSObject else {
        return nil
    }

    typealias InitFunc = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
    let initModeSelector = NSSelectorFromString("initWithWidth:height:refreshRate:")
    let impl = modeAllocated.method(for: initModeSelector)
    let initMethod = unsafeBitCast(impl, to: InitFunc.self)
    guard let mode = initMethod(modeAllocated, initModeSelector, UInt32(modeWidth), UInt32(modeHeight), 60.0) as? NSObject else {
        return nil
    }

    settings.setValue([mode], forKey: "modes")

    _ = display.perform(NSSelectorFromString("applySettings:"), with: settings)

    let displayID = display.value(forKey: "displayID") as? UInt32 ?? 0
    print("Created virtual display with ID: \(displayID)")

    // Extra retain to prevent premature deallocation
    _ = Unmanaged.passRetained(display)

    return display
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
