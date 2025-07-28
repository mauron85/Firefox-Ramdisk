import Cocoa
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var terminationObserver: NSObjectProtocol?
    
    var window: NSWindow!
    var imageView: NSImageView!
    var progressBar: NSProgressIndicator!
    var statusLabel: NSTextField!
    
    let volumeName = "Firefox RAM Disk"
    var mountPoint: String { "/Volumes/\(volumeName)" }
    
    var firefoxProfileSource: String?
    var firefoxProfileDest: String { "\(mountPoint)" }
    
    var ramDiskSizeMB: Int = 512
    var ramDiskBlocks: Int = 512 * 2048
    
    override init() {
        super.init()
        if let defaultProfilePath = getFirefoxProfilePath() {
            firefoxProfileSource = defaultProfilePath
            let profileSizeBytes = folderSize(atPath: defaultProfilePath)
            let profileSizeMB = Int((Double(profileSizeBytes) / 1_048_576).rounded(.up))
            ramDiskSizeMB = max(profileSizeMB + profileSizeMB / 5, 512)
        } else {
            showErrorAndExit("Cannot find default Firefox profile")
        }
        ramDiskBlocks = ramDiskSizeMB * 2048
    }
    
    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // Parse profiles.ini to extract the default profile's path, only processing [Profile*] sections
    func parseProfilesIni(atPath iniPath: String) -> (path: String, isRelative: Bool)? {
        guard let iniContent = try? String(contentsOfFile: iniPath, encoding: .utf8) else {
            return nil
        }
        
        let lines = iniContent.components(separatedBy: .newlines)
        var currentPath: String?
        var currentIsDefault = false
        var currentIsRelative = true
        var inProfileSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("[Profile") {
                // Evaluate previous profile section if it has all required fields
                if currentIsDefault && currentIsRelative && currentPath != nil {
                    return (path: currentPath!, isRelative: true)
                }
                // Reset for new profile section
                currentPath = nil
                currentIsDefault = false
                currentIsRelative = true
                inProfileSection = true
            } else if trimmedLine.hasPrefix("[") {
                // Evaluate previous profile section before switching
                if inProfileSection && currentIsDefault && currentIsRelative && currentPath != nil {
                    return (path: currentPath!, isRelative: true)
                }
                inProfileSection = false
                continue
            } else if !inProfileSection {
                continue // Skip lines outside [Profile*] sections
            } else if trimmedLine.hasPrefix("Name=") {
                // Name is required but not used for return value
                continue
            } else if trimmedLine.hasPrefix("IsRelative=") {
                currentIsRelative = trimmedLine == "IsRelative=1"
            } else if trimmedLine.hasPrefix("Path=") {
                currentPath = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.hasPrefix("Default=1") {
                currentIsDefault = true
            }
        }
        
        // Evaluate the last profile section
        if inProfileSection && currentIsDefault && currentIsRelative && currentPath != nil {
            return (path: currentPath!, isRelative: true)
        }
        
        return nil
    }
    
    func getFirefoxProfilePath() -> String? {
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let profilesIniPath = appSupportURL
                .appendingPathComponent("Firefox")
                .appendingPathComponent("profiles.ini")
                .path
            
            guard let (path, isRelative) = parseProfilesIni(atPath: profilesIniPath) else {
                return nil
            }
            
            if isRelative {
                return appSupportURL
                    .appendingPathComponent("Firefox")
                    .appendingPathComponent(path)
                    .path
            } else {
                return path // Return absolute path directly
            }
        }
        return nil
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupUI()
        runBackgroundTask()
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func setupUI() {
        let screenFrame = NSScreen.main!.frame
        let windowSize = NSSize(width: 400, height: 430)
        let windowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: (screenFrame.height - windowSize.height) / 2,
            width: windowSize.width,
            height: windowSize.height
        )
        
        window = KeyableWindow(
            contentRect: windowRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // ImageView
        imageView = NSImageView(frame: NSRect(x: 0, y: 30, width: 400, height: 400))
        if let firefoxImage = NSImage(named: "fframdisk") {
            imageView.image = firefoxImage
            imageView.imageScaling = .scaleProportionallyUpOrDown
        }
        window.contentView?.addSubview(imageView)
        
        // Progress bar at bottom
        progressBar = NSProgressIndicator(frame: NSRect(x: 100, y: 20, width: 200, height: 20))
        progressBar.style = .bar
        progressBar.controlSize = .large
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        window.contentView?.addSubview(progressBar)
    }
    
    func updateProgress(to percent: Double) {
        DispatchQueue.main.async {
            self.progressBar.doubleValue = percent
        }
    }
    
    func folderSize(atPath path: String) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: UInt64 = 0
        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? UInt64 {
                total += fileSize
            }
        }
        return total
    }
    
    func showErrorAndExit(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = message
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    
    func writeUserJS(withProfile path: String) {
        FirefoxPrefsWriter.write(to: path, prefs: [
            "browser.cache.disk.enable": false,
            "browser.cache.disk.capacity": 0
        ])
    }

    func launchFirefox(withProfile path: String) {
        let firefoxURL = URL(fileURLWithPath: "/Applications/Firefox.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-profile", path]
        
        // Hide the window before launching Firefox
        DispatchQueue.main.async {
            self.window.orderOut(nil) // Hide the window
        }
        
        NSWorkspace.shared.openApplication(at: firefoxURL, configuration: config) { app, error in
            if let error = error {
                print("Failed to launch Firefox: \(error)")
                DispatchQueue.main.async {
                    self.showErrorAndExit("Failed to launch Firefox: \(error.localizedDescription)")
                }
            } else if let app = app {
                print("Launched app with PID: \(app.processIdentifier)")
                
                self.terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main) { [weak self] notification in
                        guard let self = self else { return }
                        if let terminatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                           terminatedApp.processIdentifier == app.processIdentifier {
                            print("Firefox has terminated")
                            self.syncBackProfile()
                            if let observer = self.terminationObserver {
                                NSWorkspace.shared.notificationCenter.removeObserver(observer)
                                self.terminationObserver = nil
                            }
                        }
                    }
            }
        }
    }
    
    func runBackgroundTask() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            // Create RAM disk if missing
            if !fm.fileExists(atPath: self.mountPoint) {
                let attach = Process()
                attach.launchPath = "/usr/bin/hdiutil"
                attach.arguments = ["attach", "-nomount", "ram://\(self.ramDiskBlocks)"]
                let pipe = Pipe()
                attach.standardOutput = pipe
                attach.launch()
                attach.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let diskID = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: .newlines).first else {
                    self.showErrorAndExit("Failed to create RAM disk.")
                    return
                }
                
                let format = Process()
                format.launchPath = "/usr/sbin/diskutil"
                format.arguments = ["erasevolume", "HFS+", self.volumeName, diskID]
                format.launch()
                format.waitUntilExit()
            }
            
            guard let source = self.firefoxProfileSource, fm.fileExists(atPath: source) else {
                self.showErrorAndExit("Firefox profile source does not exist.")
                return
            }
            
            if fm.fileExists(atPath: self.firefoxProfileDest) {
                try? fm.removeItem(atPath: self.firefoxProfileDest)
            }
            
            self.runRsyncWithProgress(from: source, to: self.firefoxProfileDest)
        }
    }
    
    func runRsyncWithProgress(from source: String, to destination: String) {
        let totalSize = self.folderSize(atPath: source)

        let task = Process()
        task.launchPath = "/usr/bin/rsync"
        task.arguments = ["-a", "--progress", source + "/", destination]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        let handle = pipe.fileHandleForReading
        
        var transferredBytes: UInt64 = 0
        
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    
                    let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if let first = parts.first,
                       let currentFileBytes = UInt64(first) {
                        transferredBytes += currentFileBytes
                        let percent = min(Double(transferredBytes) / Double(totalSize) * 100, 100)
                        self.updateProgress(to: percent)
                    }
                }
            } else {
                handle.readabilityHandler = nil
            }
        }
        
        task.terminationHandler = { proc in
            DispatchQueue.main.async {
                if proc.terminationStatus != 0 {
                    self.showErrorAndExit("Copy failed. Possibly not enough space on RAM disk.")
                } else {
                    self.updateProgress(to: 100)
                    self.writeUserJS(withProfile: destination);
                    self.launchFirefox(withProfile: destination)
                }
            }
        }
        
        task.launch()
    }
    
    func showCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Firefox Ramdisk"
        content.body = "Profile sync completed."
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Show immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func syncBackProfile() {
        guard let source = firefoxProfileDest as String?,
              let destination = firefoxProfileSource else {
            return
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/rsync"
        task.arguments = [
            "-Ha",
            "--delete",
            "--exclude=user.js",
            "--exclude=saved-telemetry-pings/"
            , source + "/",
            destination
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { proc in
            // Read all output after process finishes
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()

            DispatchQueue.main.async {
                if proc.terminationStatus != 0 {
                    if let outputString = String(data: outputData, encoding: .utf8) {
                        print("\(outputString)")
                    }
                    self.showErrorAndExit("Failed to sync back Firefox profile.")
                } else {
                    self.showCompletionNotification()
                    NSApp.terminate(nil)
                }
            }
        }
        
        do {
            try task.run()
        } catch {
            print("Failed to start rsync process: \(error)")
            self.showErrorAndExit("Failed to start rsync.")
        }
    }
}
