import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ServiceManagement
import CoreLocation
import QuartzCore
import MediaRemoteAdapter

// MARK: - Release updates

enum AppRelease {
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    static let repositoryURL = URL(string: "https://github.com/HouseControlAU/housecontrol-photoscreen")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/HouseControlAU/housecontrol-photoscreen/releases/latest")!
}

@MainActor final class MediaRemoteMonitor: ObservableObject {
    private let controller = MediaController()
    @Published private(set) var isPlaying = false

    init() {
        controller.onTrackInfoReceived = { [weak self] trackInfo in
            let playing = trackInfo?.payload.isPlaying == true
            Task { @MainActor [weak self] in self?.isPlaying = playing }
        }
        controller.startListening()
    }

    deinit { controller.stopListening() }
}

@MainActor final class UpdateChecker: ObservableObject {
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    @Published private(set) var availableVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var updateAssetURL: URL?
    @Published private(set) var status = "Not checked yet"
    @Published private(set) var isChecking = false
    let currentVersion = AppRelease.currentVersion
    private let defaults = UserDefaults.standard

    func checkIfDue() {
        guard let last = defaults.object(forKey: "updatesLastChecked") as? Date else { checkNow(); return }
        if Date().timeIntervalSince(last) >= Self.checkInterval { checkNow() }
    }

    func checkNow() {
        guard !isChecking else { return }
        isChecking = true; status = "Checking for updates…"
        var request = URLRequest(url: AppRelease.latestReleaseAPI)
        request.setValue("HouseControl PhotoScreen/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                self.defaults.set(Date(), forKey: "updatesLastChecked")
                guard error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String, let htmlURL = json["html_url"] as? String, let url = URL(string: htmlURL) else {
                    self.status = "Unable to check for updates"
                    return
                }
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                self.releaseURL = url
                if let assets = json["assets"] as? [[String: Any]],
                   let asset = assets.first(where: { ($0["name"] as? String) == "HouseControl-PhotoScreen-macos.zip" }),
                   let assetURL = asset["browser_download_url"] as? String {
                    self.updateAssetURL = URL(string: assetURL)
                } else {
                    self.updateAssetURL = nil
                }
                if Self.isNewer(version, than: self.currentVersion) { self.availableVersion = version; self.status = "Update available" }
                else { self.availableVersion = nil; self.status = "You are up to date" }
            }
        }.resume()
    }

    func installUpdate() {
        guard let updateAssetURL, let updateURL = URL(string: updateAssetURL.absoluteString) else { status = "No macOS update package is available"; return }
        status = "Downloading update…"
        URLSession.shared.downloadTask(with: updateURL) { [weak self] temporaryURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let temporaryURL else { self.status = "Update download failed"; return }
                do { try self.stageAndLaunchUpdate(zipURL: temporaryURL) }
                catch { self.status = "Update failed: \(error.localizedDescription)" }
            }
        }.resume()
    }

    private func stageAndLaunchUpdate(zipURL: URL) throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("HouseControlPhotoScreen-update-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent("update.zip")
        try fileManager.copyItem(at: zipURL, to: archive)
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); unzip.arguments = ["-x", "-k", archive.path, directory.path]; try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0,
              let appURL = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?.first(where: { ($0 as? URL)?.pathExtension == "app" }) as? URL else { throw NSError(domain: "HouseControlPhotoScreen", code: 1, userInfo: [NSLocalizedDescriptionKey: "The downloaded update is not a valid app bundle"]) }
        let executable = appURL.appendingPathComponent("Contents/MacOS/housecontrol-photoscreen")
        guard fileManager.isExecutableFile(atPath: executable.path) else { throw NSError(domain: "HouseControlPhotoScreen", code: 2, userInfo: [NSLocalizedDescriptionKey: "The downloaded app executable is missing"]) }
        let confirmation = NSAlert()
        confirmation.messageText = "Install update and restart PhotoScreen?"
        confirmation.informativeText = "PhotoScreen will quit, replace its application bundle, and start again with the downloaded version."
        confirmation.alertStyle = .informational
        confirmation.addButton(withTitle: "Install and Restart")
        confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { status = "Update cancelled"; return }
        let script = directory.appendingPathComponent("install-update.sh")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let scriptBody = "#!/bin/sh\nsleep 1\nwhile kill -0 \(currentPID) 2>/dev/null; do sleep 1; done\n/usr/bin/ditto -- \(shellQuote(appURL.path)) \(shellQuote(Bundle.main.bundlePath))\n/usr/bin/open -- \(shellQuote(Bundle.main.bundlePath))\nrm -f \(shellQuote(script.path))\n"
        try scriptBody.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let updater = Process(); updater.executableURL = URL(fileURLWithPath: "/bin/sh"); updater.arguments = [script.path]; updater.standardInput = FileHandle.nullDevice; updater.standardOutput = FileHandle.nullDevice; updater.standardError = FileHandle.nullDevice; try updater.run()
        status = "Installing update…"; NSApp.terminate(nil)
    }

    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        let rhs = installed.split(separator: ".").map { Int($0.filter { $0.isNumber }) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) { let a = index < lhs.count ? lhs[index] : 0; let b = index < rhs.count ? rhs[index] : 0; if a != b { return a > b } }
        return false
    }
}

// MARK: - Settings

enum OSDCorner: String, CaseIterable, Identifiable { case topLeft, topRight, bottomLeft, bottomRight; var id: String { rawValue }; var label: String { rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized } }
enum AnimationStyle: String, CaseIterable, Identifiable { case fade, slide, zoom, kenBurns, none; var id: String { rawValue }; var label: String { rawValue == "kenBurns" ? "Ken Burns" : rawValue.capitalized } }

final class AppSettings: ObservableObject {
    private var isLoading = true

    @Published var folder: URL? { didSet { if let folder { defaults.set(folder.standardizedFileURL.path, forKey: "folder") }; save() } }
    @Published var deleteKeyCode = 51 { didSet { save() } }
    @Published var deleteKeyName = "Not set" { didSet { save() } }
    @Published var deleteEventType = "none" { didSet { save() } }
    @Published var deleteEventSubtype = 0 { didSet { save() } }
    @Published var deleteEventData1 = 0 { didSet { save() } }
    @Published var deleteEventButton = 0 { didSet { save() } }
    @Published var interval: Double = 60 { didSet { save() } }
    @Published var shuffle = true { didSet { save() } }
    @Published var corner: OSDCorner = .bottomLeft { didSet { save() } }
    @Published var showDate = true { didSet { save() } }
    @Published var showLocation = true { didSet { save() } }
    @Published var showFolder = true { didSet { save() } }
    @Published var showTime = true { didSet { save() } }
    @Published var animation: AnimationStyle = .fade { didSet { save() } }
    @Published var deleteEnabled = false { didSet { save() } }
    @Published var permanentDelete = false { didSet { save() } }
    @Published var selectedDisplay = 0 { didSet { save() } }
    @Published var launchAtLogin = false { didSet { save() } }
    @Published var idleStartDelay: Double = 0 { didSet { save() } }

    private let defaults = UserDefaults.standard
    init() {

        folder = defaults.string(forKey: "folder").map { URL(fileURLWithPath: $0) }
        deleteKeyCode = defaults.object(forKey: "deleteKeyCode") as? Int ?? 51
        deleteKeyName = defaults.string(forKey: "deleteKeyName") ?? "Not set"
        deleteEventType = defaults.string(forKey: "deleteEventType") ?? "none"
        deleteEventSubtype = defaults.object(forKey: "deleteEventSubtype") as? Int ?? 0
        deleteEventData1 = defaults.object(forKey: "deleteEventData1") as? Int ?? 0
        deleteEventButton = defaults.object(forKey: "deleteEventButton") as? Int ?? 0
        if let saved = defaults.dictionary(forKey: "secondaryDeleteKey") {
            deleteKeyCode = saved["keyCode"] as? Int ?? deleteKeyCode; deleteKeyName = saved["name"] as? String ?? deleteKeyName; deleteEventType = saved["type"] as? String ?? deleteEventType; deleteEventSubtype = saved["subtype"] as? Int ?? deleteEventSubtype; deleteEventData1 = saved["data1"] as? Int ?? deleteEventData1; deleteEventButton = saved["button"] as? Int ?? deleteEventButton
        }
        if deleteEventType == "keyDown" && deleteKeyCode == 51 && deleteKeyName == "Delete" {
            deleteEventType = "none"; deleteKeyName = "Not set"
        }
        interval = defaults.object(forKey: "interval") as? Double ?? 60
        shuffle = defaults.object(forKey: "shuffle") as? Bool ?? true
        corner = OSDCorner(rawValue: defaults.string(forKey: "corner") ?? "bottomLeft") ?? .bottomLeft
        showDate = defaults.object(forKey: "showDate") as? Bool ?? true
        showLocation = defaults.object(forKey: "showLocation") as? Bool ?? true
        showFolder = defaults.object(forKey: "showFolder") as? Bool ?? true
        showTime = defaults.object(forKey: "showTime") as? Bool ?? true
        animation = AnimationStyle(rawValue: defaults.string(forKey: "animation") ?? "fade") ?? .fade
        deleteEnabled = defaults.object(forKey: "deleteEnabled") as? Bool ?? false
        permanentDelete = defaults.object(forKey: "permanentDelete") as? Bool ?? false
        selectedDisplay = defaults.object(forKey: "selectedDisplay") as? Int ?? 0
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        idleStartDelay = defaults.object(forKey: "idleStartDelay") as? Double ?? 0
        persistLearnedKey()
        isLoading = false
        save()
    }
    private func save() {
        guard !isLoading else { return }
        defaults.set(deleteKeyCode, forKey: "deleteKeyCode"); defaults.set(deleteKeyName, forKey: "deleteKeyName"); defaults.set(deleteEventType, forKey: "deleteEventType"); defaults.set(deleteEventSubtype, forKey: "deleteEventSubtype"); defaults.set(deleteEventData1, forKey: "deleteEventData1"); defaults.set(deleteEventButton, forKey: "deleteEventButton"); defaults.set(interval, forKey: "interval")
        defaults.set(shuffle, forKey: "shuffle"); defaults.set(corner.rawValue, forKey: "corner")
        defaults.set(showDate, forKey: "showDate"); defaults.set(showLocation, forKey: "showLocation")
        defaults.set(showFolder, forKey: "showFolder"); defaults.set(showTime, forKey: "showTime"); defaults.set(animation.rawValue, forKey: "animation")
        defaults.set(deleteEnabled, forKey: "deleteEnabled"); defaults.set(permanentDelete, forKey: "permanentDelete")
        defaults.set(selectedDisplay, forKey: "selectedDisplay"); defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(idleStartDelay, forKey: "idleStartDelay")
    }
    func persistLearnedKey() {
        let saved: [String: Any] = ["keyCode": deleteKeyCode, "name": deleteKeyName, "type": deleteEventType, "subtype": deleteEventSubtype, "data1": deleteEventData1, "button": deleteEventButton]
        defaults.set(saved, forKey: "secondaryDeleteKey")
        defaults.set(deleteKeyCode, forKey: "deleteKeyCode"); defaults.set(deleteKeyName, forKey: "deleteKeyName"); defaults.set(deleteEventType, forKey: "deleteEventType"); defaults.set(deleteEventSubtype, forKey: "deleteEventSubtype"); defaults.set(deleteEventData1, forKey: "deleteEventData1"); defaults.set(deleteEventButton, forKey: "deleteEventButton")
    }
    func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("HouseControl PhotoScreen login item unavailable until packaged as an app: %@", error.localizedDescription) }
    }
}

// MARK: - Photo model

struct PhotoMetadata: Equatable {
    let date: String?
    let location: String?
    let folder: String
}

struct CachedEXIF: Codable {
    let modified: Date
    let date: String?
    let latitude: Double?
    let longitude: Double?
    var location: String?
}

struct PhotoItem: Identifiable, Equatable {
    let id: URL
    let url: URL
    let metadata: PhotoMetadata
}

final class PhotoLibrary {
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
    static func load(from folder: URL, cancelled: @escaping () -> Bool = { false }) -> [PhotoItem] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [PhotoItem] = []
        for item in e {
            if cancelled() { return [] }
            guard let url = item as? URL, extensions.contains(url.pathExtension.lowercased()), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            result.append(PhotoItem(id: url, url: url, metadata: PhotoMetadata(date: nil, location: nil, folder: url.deletingLastPathComponent().lastPathComponent)))
        }
        return result.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
    private static let cacheURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("HouseControl PhotoScreen/exif-cache.json")
    private static var cache: [String: CachedEXIF] = {
        guard let data = try? Data(contentsOf: cacheURL), let value = try? JSONDecoder().decode([String: CachedEXIF].self, from: data) else { return [:] }
        return value
    }()
    private static let cacheLock = NSLock()
    private static func modifiedDate(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
    private static func persistCache() { try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) } }
    static func metadata(for url: URL) -> PhotoMetadata {
        let key = url.path; let modified = modifiedDate(url); cacheLock.lock(); if let entry = cache[key], entry.modified == modified { cacheLock.unlock(); return PhotoMetadata(date: entry.date, location: entry.location, folder: url.deletingLastPathComponent().lastPathComponent) }; cacheLock.unlock()
        var date: String?; var latitude: Double?; var longitude: Double?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] { date = exif[kCGImagePropertyExifDateTimeOriginal] as? String }
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any], let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let lon = gps[kCGImagePropertyGPSLongitude] as? Double { latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat; longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon }
        }
        cacheLock.lock(); cache[key] = CachedEXIF(modified: modified, date: date, latitude: latitude, longitude: longitude, location: nil); persistCache(); cacheLock.unlock()
        return PhotoMetadata(date: date, location: nil, folder: url.deletingLastPathComponent().lastPathComponent)
    }
    static func suburb(for url: URL, completion: @escaping (String?) -> Void) {
        _ = metadata(for: url); let key = url.path; cacheLock.lock(); let entry = cache[key]; cacheLock.unlock(); if let location = entry?.location { completion(location); return }; guard let lat = entry?.latitude, let lon = entry?.longitude else { completion(nil); return }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { places, _ in
            let place = places?.first; let parts = [place?.locality ?? place?.subLocality, place?.administrativeArea, place?.country].compactMap { $0 }.filter { !$0.isEmpty }; let result = parts.isEmpty ? nil : parts.joined(separator: ", ")
            cacheLock.lock(); if var current = cache[key] { current.location = result; cache[key] = current; persistCache() }; cacheLock.unlock(); completion(result)
        }
    }
    static func delete(_ photo: PhotoItem, permanently: Bool) throws {
        guard permanently else { try FileManager.default.trashItem(at: photo.url, resultingItemURL: nil); return }
        try FileManager.default.removeItem(at: photo.url)
    }
    static func rotate(_ photo: PhotoItem, clockwise: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let type = CGImageSourceGetType(source) else { throw NSError(domain: "HouseControlPhotoScreen", code: 20, userInfo: [NSLocalizedDescriptionKey: "Unable to read image for rotation"]) }
        let sourceWidth = image.width; let sourceHeight = image.height; let outputWidth = sourceHeight; let outputHeight = sourceWidth
        guard let context = CGContext(data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NSError(domain: "HouseControlPhotoScreen", code: 21, userInfo: [NSLocalizedDescriptionKey: "Unable to create rotated image"]) }
        context.interpolationQuality = .high
        if clockwise { context.translateBy(x: 0, y: CGFloat(outputHeight)); context.rotate(by: -.pi / 2) } else { context.translateBy(x: CGFloat(outputWidth), y: 0); context.rotate(by: .pi / 2) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard let rotated = context.makeImage() else { throw NSError(domain: "HouseControlPhotoScreen", code: 22, userInfo: [NSLocalizedDescriptionKey: "Unable to create rotated image"]) }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]; properties[kCGImagePropertyOrientation] = 1
        let temporary = photo.url.deletingLastPathComponent().appendingPathComponent(".housecontrol-rotate-\(UUID().uuidString).\(photo.url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else { throw NSError(domain: "HouseControlPhotoScreen", code: 23, userInfo: [NSLocalizedDescriptionKey: "Unable to write rotated image"]) }
        CGImageDestinationAddImage(destination, rotated, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "HouseControlPhotoScreen", code: 24, userInfo: [NSLocalizedDescriptionKey: "Unable to finalize rotated image"]) }
        _ = try FileManager.default.replaceItemAt(photo.url, withItemAt: temporary, backupItemName: nil, options: .usingNewMetadataOnly)
    }
}

// MARK: - Fullscreen slideshow

final class SlideWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) { onKeyDown?(event) }
    override func sendEvent(_ event: NSEvent) {
        if [.systemDefined].contains(event.type) { onKeyDown?(event) }
        else if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { if event.clickCount >= 2 { onDoubleClick?() } else { onKeyDown?(event) } }
        else { super.sendEvent(event) }
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

final class SlideshowController: NSObject, NSWindowDelegate {
    let settings: AppSettings
    private var window: SlideWindow?
    private var timer: Timer?
    private var photos: [PhotoItem] = []
    private var index = 0
    private var imageView = NSImageView()
    private var indexing = false
    private var indexedFolder: URL?
    private var indexGeneration = 0
    private var locationCache: [URL: String] = [:]
    private var locationPending: Set<URL> = []
    private var osd = NSTextField(labelWithString: "")
    private var deletionOSD = NSTextField(labelWithString: "")
    private var clockOSD = NSTextField(labelWithString: "")
    private var clockPanel = NSView()
    private var lastClockText = ""
    private var slideshowInputMonitor: Any?
    private var slideshowLocalKeyMonitor: Any?
    private var clockTimer: Timer?
    private var deleteInProgress = false
    private var rotationInProgress = false
    private var pendingDelete: PhotoItem?
    private var deleteCountdown = 0
    private var deleteCountdownTimer: Timer?
    var isRunning: Bool { window != nil }
    private var deletionMessageToken = UUID()
    init(settings: AppSettings) { self.settings = settings }

    func reindex() {
        guard let folder = settings.folder, !indexing else { return }
        indexing = true; indexGeneration += 1; let generation = indexGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = PhotoLibrary.load(from: folder)
            DispatchQueue.main.async {
                guard let self, generation == self.indexGeneration else { return }
                self.photos = loaded; self.indexedFolder = folder; self.indexing = false
            }
        }
    }

    func start() -> Bool {
        guard let folder = settings.folder, indexedFolder == folder, !photos.isEmpty, !indexing else { NSSound.beep(); return false }
        guard window == nil else { return true }
        present(photos, on: NSScreen.screens[safe: settings.selectedDisplay] ?? NSScreen.main ?? NSScreen.screens[0])
        return window != nil
    }

    private func present(_ loaded: [PhotoItem], on screen: NSScreen) {
        photos = loaded
        if settings.shuffle { photos.shuffle() }
        index = 0
        let w = SlideWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .screenSaver; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; w.isOpaque = true; w.backgroundColor = .black; w.delegate = self
        w.onKeyDown = { [weak self] event in self?.handleKey(event) }; w.onDoubleClick = { [weak self] in self?.stop() }
        let root = NSView(frame: screen.frame); root.wantsLayer = true; root.layer?.backgroundColor = NSColor.black.cgColor; root.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.imageAlignment = .alignCenter; imageView.wantsLayer = true; imageView.frame = root.bounds; imageView.autoresizingMask = []; root.addSubview(imageView)
        let osdShadow = { () -> NSShadow in let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.85); s.shadowBlurRadius = 8; s.shadowOffset = NSSize(width: 0, height: -2); return s }()
        osd.textColor = .white; osd.alignment = .left; osd.font = .systemFont(ofSize: 15, weight: .medium); osd.backgroundColor = .clear; osd.isBezeled = false; osd.drawsBackground = false; osd.shadow = osdShadow; osd.lineBreakMode = .byWordWrapping; osd.maximumNumberOfLines = 4
        deletionOSD.textColor = .white; deletionOSD.alignment = .center; deletionOSD.font = .systemFont(ofSize: 15, weight: .medium); deletionOSD.backgroundColor = .clear; deletionOSD.isBezeled = false; deletionOSD.drawsBackground = false; deletionOSD.shadow = osdShadow; deletionOSD.lineBreakMode = .byWordWrapping; deletionOSD.maximumNumberOfLines = 3; deletionOSD.isHidden = true
        clockOSD.textColor = .white; clockOSD.alignment = .left; clockOSD.drawsBackground = false; clockOSD.isBezeled = false; clockOSD.maximumNumberOfLines = 2; clockOSD.shadow = { let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.8); s.shadowBlurRadius = 8; s.shadowOffset = NSSize(width: 0, height: -2); return s }()
        clockPanel.wantsLayer = true; clockPanel.layer?.backgroundColor = NSColor.clear.cgColor; clockPanel.alphaValue = settings.showTime ? 0.88 : 0
        let monitorMask: NSEvent.EventTypeMask = settings.deleteEventType == "mouse" ? [.keyDown, .systemDefined, .leftMouseDown, .rightMouseDown, .otherMouseDown] : [.keyDown, .systemDefined]
        slideshowLocalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handleKey(event); return nil }
        clockPanel.addSubview(clockOSD); root.addSubview(osd); root.addSubview(deletionOSD); root.addSubview(clockPanel); w.contentView = root; window = w; w.makeKeyAndOrderFront(nil); slideshowInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: monitorMask) { [weak self] event in if event.clickCount >= 2 && [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { self?.stop() } else { self?.handleKey(event) } }; showCurrent(); updateClock(); clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateClock() }
        timer = Timer.scheduledTimer(withTimeInterval: max(5, settings.interval), repeats: true) { [weak self] _ in self?.next() }
    }
    func stop() { timer?.invalidate(); timer = nil; clockTimer?.invalidate(); clockTimer = nil; deleteCountdownTimer?.invalidate(); deleteCountdownTimer = nil; pendingDelete = nil; if let monitor = slideshowInputMonitor { NSEvent.removeMonitor(monitor) }; if let monitor = slideshowLocalKeyMonitor { NSEvent.removeMonitor(monitor) }; slideshowInputMonitor = nil; slideshowLocalKeyMonitor = nil; window?.orderOut(nil); window = nil }
    private func next() { guard !photos.isEmpty else { stop(); return }; index = (index + 1) % photos.count; showCurrent() }
    private func previous() { guard !photos.isEmpty else { stop(); return }; index = (index - 1 + photos.count) % photos.count; showCurrent() }
    private func showCurrent() {
        guard photos.indices.contains(index) else { return }; let p = photos[index]; let image = NSImage(contentsOf: p.url); let metadata = PhotoLibrary.metadata(for: p.url)
        let base = window?.contentView?.bounds ?? imageView.frame
        imageView.layer?.removeAllAnimations()
        imageView.layer?.setAffineTransform(.identity)
        imageView.frame = base; imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5); imageView.layer?.position = CGPoint(x: base.midX, y: base.midY); imageView.alphaValue = 1
        switch settings.animation {
        case .none: imageView.image = image
        case .fade:
            imageView.alphaValue = 0; imageView.image = image
            NSAnimationContext.runAnimationGroup { $0.duration = 1.0; $0.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); imageView.animator().alphaValue = 1 }
        case .slide:
            var start = base; start.origin.x += base.width * 0.12; imageView.frame = start; imageView.image = image
            NSAnimationContext.runAnimationGroup { $0.duration = 1.0; $0.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); imageView.animator().frame = base }
        case .zoom:
            imageView.image = image
            var start = base.insetBy(dx: base.width * 0.08, dy: base.height * 0.08); start.origin.x += base.width * 0.04; start.origin.y += base.height * 0.04; imageView.frame = start
            NSAnimationContext.runAnimationGroup { $0.duration = 1.0; $0.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); imageView.animator().frame = base }
        case .kenBurns:
            imageView.image = image
            let imageAspect: CGFloat = { guard let source = CGImageSourceCreateWithURL(p.url as CFURL, nil), let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil), cgImage.height > 0 else { return max(0.001, image.map { $0.size.width / $0.size.height } ?? 1) }; let properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]; let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1; let swapped = (5...8).contains(orientation); return swapped ? CGFloat(cgImage.height) / CGFloat(cgImage.width) : CGFloat(cgImage.width) / CGFloat(cgImage.height) }()
            let screenAspect = max(0.001, base.width / base.height); let aspectRatio = max(0.001, imageAspect / screenAspect); let kenBurnsScale: CGFloat = aspectRatio >= 1 ? aspectRatio : 1 / aspectRatio
            imageView.bounds = NSRect(origin: .zero, size: base.size); imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5); imageView.layer?.position = CGPoint(x: base.midX, y: base.midY); let duration = max(5, settings.interval); let zoom = CABasicAnimation(keyPath: "transform"); zoom.fromValue = CATransform3DIdentity; zoom.toValue = CATransform3DMakeScale(kenBurnsScale, kenBurnsScale, 1); zoom.duration = duration; zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); imageView.layer?.setAffineTransform(CGAffineTransform(scaleX: kenBurnsScale, y: kenBurnsScale)); imageView.layer?.position = CGPoint(x: base.midX, y: base.midY); imageView.layer?.add(zoom, forKey: "centeredKenBurns")
        }
        var lines: [String] = []
        if settings.showDate, let d = metadata.date { lines.append("Taken: \(d)") }
        if settings.showLocation {
            if let suburb = locationCache[p.url] { lines.append("Location: \(suburb)") }
            else if !locationPending.contains(p.url) { locationPending.insert(p.url); PhotoLibrary.suburb(for: p.url) { [weak self] suburb in DispatchQueue.main.async { guard let self else { return }; self.locationPending.remove(p.url); if let suburb { self.locationCache[p.url] = suburb }; if self.photos.indices.contains(self.index), self.photos[self.index].url == p.url { self.showCurrent() } } } }
        }
        if settings.showFolder { lines.append("Folder: \(metadata.folder)") }
        osd.stringValue = lines.joined(separator: "\n"); positionOSD(); updateClock()
    }
    private func updateClock() {
        guard let content = window?.contentView else { return }
        guard settings.showTime else { clockPanel.isHidden = true; return }
        clockPanel.isHidden = false
        let now = Date(); let time = DateFormatter(); time.locale = Locale(identifier: "en_US_POSIX"); time.dateFormat = "HH:mm"; let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "EEE d MMM"
        let timeString = time.string(from: now).uppercased(); let dateString = date.string(from: now).uppercased(); let clockText = timeString + "\n" + dateString
        let size = min(max(content.bounds.height * 0.10, 48), 180)
        let text = NSMutableAttributedString(string: timeString + "\n", attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.96)])
        text.append(NSAttributedString(string: dateString, attributes: [.font: NSFont.systemFont(ofSize: size * 0.32, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.82)]))
        let changed = !lastClockText.isEmpty && lastClockText != clockText; lastClockText = clockText; clockOSD.attributedStringValue = text; positionClockOSD()
        if changed {
            let target = clockPanel.frame; clockPanel.frame = target.offsetBy(dx: 0, dy: -8); clockPanel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.42; context.timingFunction = CAMediaTimingFunction(name: .easeOut); clockPanel.animator().frame = target; clockPanel.animator().alphaValue = 0.88 }
        } else { clockPanel.alphaValue = 0.88 }
    }
    private func positionClockOSD() {
        guard let content = window?.contentView else { return }; let size = clockOSD.fittingSize; let horizontalPad: CGFloat = 18; let verticalPad: CGFloat = 12; let panelSize = NSSize(width: content.bounds.width, height: size.height + verticalPad * 2); let pad: CGFloat = 30; let opposite: OSDCorner = { switch settings.corner { case .topLeft: return .bottomRight; case .topRight: return .bottomLeft; case .bottomLeft: return .topRight; case .bottomRight: return .topLeft } }(); var y = pad
        if opposite == .topLeft || opposite == .topRight { y = content.bounds.height - panelSize.height - pad }
        clockPanel.frame = NSRect(x: 0, y: y, width: panelSize.width, height: panelSize.height); clockOSD.frame = NSRect(x: horizontalPad, y: verticalPad, width: max(0, size.width), height: size.height)
    }
    private func positionOSD() {
        guard let content = window?.contentView else { return }; let size = osd.fittingSize; let pad: CGFloat = 30; var y = pad
        if settings.corner == .topLeft || settings.corner == .topRight { y = content.bounds.height - size.height - pad }
        osd.alignment = .left
        let leftInset = max(20, content.bounds.width * 0.05)
        osd.frame = NSRect(x: leftInset, y: y, width: max(0, content.bounds.width - leftInset - 20), height: size.height + 14)
    }
    private func positionDeletionOSD() {
        guard let content = window?.contentView else { return }
        let margin: CGFloat = 20; let width = max(0, content.bounds.width - margin * 2); let lineHeight: CGFloat = 20; let height = min(max(lineHeight * 3 + 20, deletionOSD.fittingSize.height + 20), max(40, content.bounds.height - margin * 2)); let y = (content.bounds.height - height) / 2
        deletionOSD.frame = NSRect(x: margin, y: y, width: width, height: height)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { stop(); return true }
}

func systemEventSignature(_ event: NSEvent) -> Int { Int(event.data1) & 0xFFFF0000 }

extension SlideshowController {
    func handleKey(_ event: NSEvent) {
        if pendingDelete != nil {
            if event.type == .keyDown { cancelPendingDelete() }
            return
        }
        if event.type == .systemDefined {
            if settings.deleteEnabled, settings.deleteEventType == "systemDefined", event.subtype.rawValue == settings.deleteEventSubtype, systemEventSignature(event) == settings.deleteEventData1 { deleteCurrent() }
            return
        }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            if settings.deleteEnabled, settings.deleteEventType == "mouse", event.buttonNumber == settings.deleteEventButton { deleteCurrent() }
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { deleteCurrent(); return }
        if settings.deleteEnabled, settings.deleteEventType == "keyDown", Int(event.keyCode) == settings.deleteKeyCode { deleteCurrent(); return }
        if event.keyCode == 126 { rotateCurrent(clockwise: true); return }
        if event.keyCode == 125 { rotateCurrent(clockwise: false); return }
        if event.keyCode == 123 { previous(); return }
        if event.keyCode == 124 { next(); return }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return }
        if key == "q" || event.keyCode == 53 { stop(); return }
        guard settings.deleteEnabled, Int(event.keyCode) == settings.deleteKeyCode else { return }
        deleteCurrent()
    }
    private func deleteCurrent() {
        guard !deleteInProgress, pendingDelete == nil, photos.indices.contains(index) else { return }
        let photo = photos[index]; pendingDelete = photo; deleteCountdown = 10; deletionOSD.stringValue = "Deleting file \(photo.url.lastPathComponent)\nPress any key to cancel\n\(deleteCountdown)"; deletionOSD.isHidden = false; positionDeletionOSD()
        deleteCountdownTimer?.invalidate()
        deleteCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.advanceDeleteCountdown() }
    }
    private func advanceDeleteCountdown() {
        guard let photo = pendingDelete else { return }
        deleteCountdown -= 1; deletionOSD.stringValue = "Deleting file \(photo.url.lastPathComponent)\nPress any key to cancel\n\(deleteCountdown)"; positionDeletionOSD()
        if deleteCountdown <= 0 { deleteCountdownTimer?.invalidate(); deleteCountdownTimer = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in guard let self, self.pendingDelete == photo else { return }; self.performDelete(photo) } }
    }
    private func cancelPendingDelete() {
        guard pendingDelete != nil else { return }; deleteCountdownTimer?.invalidate(); deleteCountdownTimer = nil; pendingDelete = nil; deletionOSD.isHidden = true; showCurrent()
    }
    private func performDelete(_ photo: PhotoItem) {
        guard !deleteInProgress else { return }; pendingDelete = nil; deleteInProgress = true; let permanently = settings.permanentDelete
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try PhotoLibrary.delete(photo, permanently: permanently)
                DispatchQueue.main.async { guard let self else { return }; self.photos.removeAll { $0.url == photo.url }; if self.photos.isEmpty { self.stop() } else { self.index = min(self.index, self.photos.count - 1); self.showCurrent(); self.deletionMessageToken = UUID(); let token = self.deletionMessageToken; self.deletionOSD.stringValue = "Deleted: \(photo.url.lastPathComponent)\n\(photo.url.path)"; self.deletionOSD.isHidden = false; self.positionDeletionOSD(); DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in guard let self, self.deletionMessageToken == token, self.window != nil else { return }; self.deletionOSD.isHidden = true; self.showCurrent() } }; self.deleteInProgress = false }
            } catch { DispatchQueue.main.async { self?.deleteInProgress = false; NSSound.beep() } }
        }
    }
    private func rotateCurrent(clockwise: Bool) {
        guard !rotationInProgress, photos.indices.contains(index) else { return }; rotationInProgress = true; let photo = photos[index]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { try PhotoLibrary.rotate(photo, clockwise: clockwise); DispatchQueue.main.async { guard let self else { return }; self.rotationInProgress = false; if self.photos.indices.contains(self.index), self.photos[self.index].url == photo.url { self.showCurrent() } } }
            catch { DispatchQueue.main.async { self?.rotationInProgress = false; NSSound.beep() } }
        }
    }
}

final class KeyRecorder: ObservableObject {
    @Published var recording = false
    private var monitors: [Any] = []
    private let localEventMask: NSEvent.EventTypeMask = [.keyDown, .systemDefined, .flagsChanged]
    private let globalEventMask: NSEvent.EventTypeMask = [.keyDown, .systemDefined, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    func toggle(settings: AppSettings) {
        if recording { stop(); return }
        recording = true
        let capture: (NSEvent) -> NSEvent? = { [weak self, weak settings] event in
            guard let self, let settings else { return event }
            if event.type == .systemDefined { settings.deleteEventType = "systemDefined"; settings.deleteEventSubtype = Int(event.subtype.rawValue); settings.deleteEventData1 = systemEventSignature(event); settings.deleteEventButton = 0; settings.deleteKeyName = "Remote/system key (\(event.data1))" }
            else if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { settings.deleteEventType = "mouse"; settings.deleteEventSubtype = 0; settings.deleteEventData1 = 0; settings.deleteEventButton = event.buttonNumber; settings.deleteKeyName = "Mouse button \(event.buttonNumber)" }
            else { settings.deleteEventType = "keyDown"; settings.deleteKeyCode = Int(event.keyCode); settings.deleteEventSubtype = 0; settings.deleteEventData1 = 0; settings.deleteEventButton = 0; settings.deleteKeyName = keyName(for: event) }
            settings.persistLearnedKey(); self.stop(); return event
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.recording else { return }
            if let local = NSEvent.addLocalMonitorForEvents(matching: self.localEventMask, handler: capture) { self.monitors.append(local) }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: self.globalEventMask, handler: { event in _ = capture(event) }) { self.monitors.append(global) }
        }
    }
    func stop() { for monitor in monitors { NSEvent.removeMonitor(monitor) }; monitors.removeAll(); recording = false }
    deinit { stop() }
}

func keyName(for event: NSEvent) -> String {
    switch event.keyCode { case 51: return "Delete"; case 117: return "Forward Delete"; case 53: return "Escape"; case 36: return "Return"; case 48: return "Tab"; case 49: return "Space"; case 123: return "Left Arrow"; case 124: return "Right Arrow"; case 125: return "Down Arrow"; case 126: return "Up Arrow"; default: return event.charactersIgnoringModifiers?.isEmpty == false ? event.charactersIgnoringModifiers! : "Key code \(event.keyCode)" }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings; @ObservedObject var updateChecker: UpdateChecker; let start: () -> Void; let reindex: () -> Void
    @State private var showFolder = false
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
            GroupBox("Photo source") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text(settings.folder?.path ?? "No folder selected").lineLimit(1).truncationMode(.middle); Spacer(); Button("Choose Folder…") { showFolder = true } }
                    HStack { Text("Display"); Picker("", selection: $settings.selectedDisplay) { ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { i, s in Text(s.localizedName).tag(i) } }.labelsHidden(); Spacer() }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Slideshow") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Animation"); Picker("", selection: $settings.animation) { ForEach(AnimationStyle.allCases) { Text($0.label).tag($0) } }.labelsHidden(); Spacer() }
                    HStack(spacing: 12) { Text("Seconds"); TextField("Seconds", text: Binding(get: { String(Int(settings.interval)) }, set: { if let value = Double($0), value >= 5 { settings.interval = min(value, 3600) } })).frame(width: 90).multilineTextAlignment(.trailing); Toggle("Shuffle images", isOn: $settings.shuffle); Spacer() }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("OSD") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { HStack(spacing: 6) { Text("Corner"); Picker("", selection: $settings.corner) { ForEach(OSDCorner.allCases) { Text($0.label).tag($0) } }.labelsHidden() }; Toggle("Date picture taken", isOn: $settings.showDate); Spacer() }
                    HStack(spacing: 14) { Toggle("Location from EXIF", isOn: $settings.showLocation); Toggle("Folder name", isOn: $settings.showFolder); Toggle("Large clock and date", isOn: $settings.showTime); Spacer() }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Deletion") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable secondary delete key", isOn: $settings.deleteEnabled)
                    Text("Primary key: Delete / Forward Delete")
                    HStack { Text("Secondary key: \(settings.deleteKeyName)").lineLimit(1); Spacer(); Button(recorder.recording ? "Press a key…" : (settings.deleteEventType == "none" ? "Learn Key" : "Reset Key")) { if recorder.recording { recorder.stop() } else if settings.deleteEventType == "none" { recorder.toggle(settings: settings) } else { settings.deleteEventType = "none"; settings.deleteKeyName = "Not set"; settings.persistLearnedKey() } }.disabled(!settings.deleteEnabled) }
                    Toggle("Permanent deletion (otherwise Trash)", isOn: $settings.permanentDelete).disabled(!settings.deleteEnabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Startup") { VStack(alignment: .leading, spacing: 10) { Toggle("Launch app automatically with macOS", isOn: $settings.launchAtLogin); HStack { Text("Start slideshow after idle (seconds)"); TextField("0 = disabled", text: Binding(get: { settings.idleStartDelay > 0 ? String(Int(settings.idleStartDelay)) : "0" }, set: { if let value = Double($0) { settings.idleStartDelay = min(max(value, 0), 86400) } })).frame(width: 90).multilineTextAlignment(.trailing) }; Text("Set to 0 to disable automatic slideshow start. Login-item registration is applied when packaged as a signed app.").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }
            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current version: \(updateChecker.currentVersion)")
                    if let available = updateChecker.availableVersion {
                        Text("Version \(available) is available.").foregroundStyle(.orange)
                        HStack { Button("Install Update") { updateChecker.installUpdate() }.disabled(updateChecker.updateAssetURL == nil); Button("Check Again") { updateChecker.checkNow() }.disabled(updateChecker.isChecking) }
                    } else {
                        HStack { Text(updateChecker.status).foregroundStyle(.secondary); Spacer(); Button("Check Now") { updateChecker.checkNow() }.disabled(updateChecker.isChecking) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Button("Start PhotoScreen") { start() }; Spacer(); Button("Quit") { NSApp.terminate(nil) }; Button("Done") { NSApp.keyWindow?.close() } }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20).frame(minWidth: 560, minHeight: 560, alignment: .topLeading).scrollIndicators(.visible).onAppear { reindex() }.onChange(of: settings.launchAtLogin) { _ in settings.applyLaunchAtLogin() }.fileImporter(isPresented: $showFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in if case .success(let urls) = result { settings.folder = urls.first; reindex() } }
    }
}

// MARK: - App delegate

@main @MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings(); let updateChecker = UpdateChecker(); let mediaMonitor = MediaRemoteMonitor(); var slideshow: SlideshowController!; var settingsWindow: NSWindow?; var statusItem: NSStatusItem!; var idleTimer: Timer?
    static func main() { let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run() }
    func applicationDidFinishLaunching(_ notification: Notification) { updateChecker.checkIfDue(); slideshow = SlideshowController(settings: settings); slideshow.reindex(); statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); let iconURL = Bundle.main.url(forResource: "HouseControlPhotoScreen", withExtension: "icns"); let icon = iconURL.flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: NSImage.applicationIconName); icon?.size = NSSize(width: 18, height: 18); statusItem.button?.image = icon; statusItem.button?.title = ""; statusItem.button?.imagePosition = .imageOnly; let menu = NSMenu(); menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")); menu.addItem(NSMenuItem(title: "Start PhotoScreen", action: #selector(start), keyEquivalent: "s")); menu.addItem(.separator()); menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")); statusItem.menu = menu; idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkIdleStart() } }
    private func mediaPlaybackLikelyActive() -> Bool {
        if mediaMonitor.isPlaying { return true }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let browserIDs = ["org.mozilla.firefox", "com.google.Chrome", "com.apple.Safari", "com.brave.Browser", "com.microsoft.edgemac"]
        let playerIDs = ["org.videolan.vlc", "com.colliderli.iina", "io.mpv", "com.apple.QuickTimePlayerX"]
        let bundleID = frontmost.bundleIdentifier ?? ""
        let isBrowserOrPlayer = browserIDs.contains(bundleID) || playerIDs.contains(bundleID)
        guard isBrowserOrPlayer else { return false }
        let mediaTerms = ["youtube", "netflix", "prime video", "disney+", "twitch", "vimeo", "video"]
        let display = CGDisplayBounds(CGMainDisplayID())
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let mediaPIDs = Set(NSWorkspace.shared.runningApplications.compactMap { application -> Int32? in
            guard let id = application.bundleIdentifier, (browserIDs + playerIDs).contains(id) else { return nil }
            return application.processIdentifier
        })
        return windows.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  (ownerPID == Int(frontmost.processIdentifier) || mediaPIDs.contains(Int32(ownerPID))) else { return false }
            let title = (window[kCGWindowName as String] as? String ?? "").lowercased()
            if mediaTerms.contains(where: { title.contains($0) }) { return true }
            guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return false }
            let fillsDisplay = bounds.width >= display.width * 0.95 && bounds.height >= display.height * 0.95
            return fillsDisplay
        }
    }
    private func checkIdleStart() { let delay = settings.idleStartDelay; guard delay > 0, !slideshow.isRunning else { return }; let idle = min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved), CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown), CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)); if idle >= delay, !mediaPlaybackLikelyActive() { start() } }
    private func configureSettingsScrollbars(_ view: NSView) { if let scrollView = view as? NSScrollView { scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = false; scrollView.scrollerStyle = .legacy; scrollView.verticalScroller?.isHidden = false }; for subview in view.subviews { configureSettingsScrollbars(subview) } }
    @objc func openSettings() { if settingsWindow == nil { let host = NSHostingController(rootView: SettingsView(settings: settings, updateChecker: updateChecker, start: { [weak self] in self?.start() }, reindex: { [weak self] in self?.slideshow.reindex() })); let w = NSWindow(contentViewController: host); w.title = "HouseControl PhotoScreen"; w.styleMask = [.titled, .closable, .miniaturizable, .resizable]; w.minSize = NSSize(width: 560, height: 560); w.setContentSize(NSSize(width: 600, height: 720)); w.setFrameAutosaveName("HouseControlPhotoScreenSettings"); w.center(); settingsWindow = w; DispatchQueue.main.async { [weak self, weak host] in if let view = host?.view { self?.configureSettingsScrollbars(view) } } }; settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func start() { if !slideshow.isRunning, slideshow.start() { settingsWindow?.orderOut(nil) } }
    @objc func quit() { idleTimer?.invalidate(); NSApp.terminate(nil) }
}

extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
