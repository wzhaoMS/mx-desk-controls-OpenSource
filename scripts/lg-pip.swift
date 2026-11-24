import Foundation
import IOKit.hid
import Darwin

enum PipFailure: Error {
    case assertion(String)
    case usage
    case unavailable
    case transport(String)
    case unsupportedFirmware
    case layoutNotReady(expected: UInt16, observed: UInt16?)
}

struct VCPReply: Equatable {
    let maximum: UInt16
    let current: UInt16
}

func queryFrame(_ feature: UInt8) throws -> [UInt8] {
    guard [0x10, 0xd7, 0xc9].contains(feature) else { throw PipFailure.usage }
    let packet: [UInt8] = [0x6e, 0x51, 0x82, 0x01, feature]
    return [0x73, 0x74] + packet + [packet.reduce(0, ^), 0x65, 0x64]
}

func navigationFrames() -> [[UInt8]] {
    let reset: [UInt8] = [0x73, 0x74, 0x6e, 0x51, 0x84, 0x03, 0xf0, 0, 1, 0x49, 0x65, 0x64]
    let keys: [UInt8] = [0x43, 0x40, 0x40, 0x44, 0x40, 0x44, 0x40, 0x44]
    return [reset] + keys.map { key in
        let packet: [UInt8] = [0x6e, 0x51, 0x84, 0x03, 0xf0, 4, key]
        return [0x73, 0x74] + packet + [packet.reduce(0, ^), 0x65, 0x64]
    }
}

func parseReply(_ bytes: [UInt8], feature: UInt8) -> VCPReply? {
    guard [0x10, 0xd7, 0xc9].contains(feature), bytes.count >= 11, bytes.count <= 512 else { return nil }
    for offset in 0...(bytes.count - 11) {
        let packet = Array(bytes[offset..<(offset + 11)])
        guard packet[0] == 0x6e, packet[1] == 0x88, packet[2] == 2,
              packet[3] == 0, packet[4] == feature,
              packet.reduce(UInt8(0x50), ^) == 0 else { continue }
        let maximum = UInt16(packet[6]) * 256 + UInt16(packet[7])
        let current = UInt16(packet[8]) * 256 + UInt16(packet[9])
        if feature == 0xd7 && maximum != 255 { continue }
        if feature == 0x10 && (maximum != 100 || current > 100) { continue }
        return VCPReply(maximum: maximum, current: current)
    }
    return nil
}

func hidQueryReports(_ feature: UInt8) throws -> [[UInt8]] {
    let payload = Array(try queryFrame(feature).dropFirst(3).dropLast(2))
    var submit: [UInt8] = [8, 1, 0x55, 3, UInt8(payload.count), 0, 3, 0x37] + payload
    submit += [UInt8](repeating: 0, count: 64 - submit.count)
    var collect = submit
    collect[1] = 2
    collect[3] = 4
    collect[4] = 11
    collect[6] = 11
    return [submit, collect]
}

func hidNavigationReport(_ frame: [UInt8]) throws -> [UInt8] {
    guard navigationFrames().contains(frame) else { throw PipFailure.usage }
    let payload = Array(frame.dropFirst(3).dropLast(2))
    var submit: [UInt8] = [8, 1, 0x55, 3, UInt8(payload.count), 0, 3, 0x37] + payload
    submit += [UInt8](repeating: 0, count: 64 - submit.count)
    return submit
}

func supportedHidInterface(_ properties: [String: Int]) -> Bool {
    properties["VendorID"] == 0x043e && properties["ProductID"] == 0x9a8a &&
    properties["PrimaryUsagePage"] == 0xff00 && properties["PrimaryUsage"] == 1 &&
    properties["MaxInputReportSize"] == 64 && properties["MaxOutputReportSize"] == 64
}

final class HidInbox {
    var accepting = false
    var reports: [[UInt8]] = []
}

final class HidConnection {
    let device: IOHIDDevice
    let deadline: Double
    let inbox = HidInbox()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    init(device: IOHIDDevice, deadline: Double) {
        self.device = device
        self.deadline = deadline
        buffer.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, type, reportID, bytes, count in
            guard let context, result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
                  reportID == 0, count > 0, count <= 64 else { return }
            let inbox = Unmanaged<HidInbox>.fromOpaque(context).takeUnretainedValue()
            if inbox.accepting && inbox.reports.count < 16 {
                inbox.reports.append(Array(UnsafeBufferPointer(start: bytes, count: count)))
            }
        }, Unmanaged.passUnretained(inbox).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    func close() {
        inbox.accepting = false
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        buffer.deinitialize(count: 64)
        buffer.deallocate()
    }

    func pause(_ duration: Double) throws {
        let readyAt = ProcessInfo.processInfo.systemUptime + duration
        while ProcessInfo.processInfo.systemUptime < readyAt {
            try checkDeadline(deadline)
            CFRunLoopRunInMode(.defaultMode, min(0.025, max(0, readyAt - ProcessInfo.processInfo.systemUptime)), false)
        }
    }

    func submit(_ report: [UInt8]) throws {
        try checkDeadline(deadline)
        guard report.count == 64 else { throw PipFailure.usage }
        let result = report.withUnsafeBufferPointer { bytes in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, bytes.baseAddress!, report.count)
        }
        guard result == kIOReturnSuccess else { throw PipFailure.transport("HID submit failed: \(result)") }
        try checkDeadline(deadline)
    }

    func query(_ feature: UInt8) throws -> VCPReply? {
        let reports = try hidQueryReports(feature)
        inbox.accepting = false
        try pause(0.03)
        inbox.reports.removeAll(keepingCapacity: true)
        inbox.accepting = true
        defer { inbox.accepting = false }
        try submit(reports[0])
        try pause(0.05)
        try submit(reports[1])
        let expires = min(deadline, ProcessInfo.processInfo.systemUptime + 0.75)
        while ProcessInfo.processInfo.systemUptime < expires {
            if let reply = inbox.reports.compactMap({ parseReply($0, feature: feature) }).first { return reply }
            try pause(0.025)
        }
        return nil
    }

    func sendNavigation(_ frame: [UInt8]) throws -> Bool {
        let report = try hidNavigationReport(frame)
        guard try query(0x10) != nil else { throw PipFailure.transport("HID brightness baseline missing; OSD event not sent") }
        try submit(report)
        return true
    }
}

func runHid(enable: Bool) throws -> [String: Any] {
    let previousTermination = signal(SIGTERM) { _ in interrupted = 1 }
    let previousInterrupt = signal(SIGINT) { _ in interrupted = 1 }
    defer {
        _ = signal(SIGTERM, previousTermination)
        _ = signal(SIGINT, previousInterrupt)
    }
    let deadline = ProcessInfo.processInfo.systemUptime + operationBudget
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, ["VendorID": 0x043e, "ProductID": 0x9a8a,
        "PrimaryUsagePage": 0xff00, "PrimaryUsage": 1] as CFDictionary)
    let candidates = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    let supported = candidates.filter { device in
        var properties: [String: Int] = [:]
        for name in ["VendorID", "ProductID", "PrimaryUsagePage", "PrimaryUsage", "MaxInputReportSize", "MaxOutputReportSize"] {
            properties[name] = (IOHIDDeviceGetProperty(device, name as CFString) as? NSNumber)?.intValue
        }
        return supportedHidInterface(properties)
    }
    guard supported.count == 1, let device = supported.first else { throw PipFailure.unavailable }
    try checkDeadline(deadline)
    guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        throw PipFailure.transport("HID control interface could not open")
    }
    defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
    let connection = HidConnection(device: device, deadline: deadline)
    defer { connection.close() }
    if enable {
        let result = try enablePip(query: connection.query, send: connection.sendNavigation, pause: connection.pause)
        return ["ok": true, "transport": "hid", "submittedFrames": result.submittedFrames,
            "layoutValue": result.layoutValue, "effectVerified": false]
    }
    guard let brightness = try connection.query(0x10), let firmware = try connection.query(0xc9),
          let layout = try connection.query(0xd7) else { throw PipFailure.transport("HID read-only preflight did not receive all replies") }
    return ["ok": true, "transport": "hid", "brightness": brightness.current, "firmwareValue": firmware.current,
            "layoutValue": layout.current, "submittedFrames": 0]
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw PipFailure.assertion(message) }
}

func enablePip(query: (UInt8) throws -> VCPReply?, send: ([UInt8]) throws -> Bool,
               pause: (Double) throws -> Void) throws -> (submittedFrames: Int, layoutValue: UInt16) {
    var firmware: UInt16?
    for attempt in 0..<3 {
        firmware = try query(0xc9)?.current
        if firmware != nil { break }
        if attempt < 2 { try pause(0.5) }
    }
    guard let firmware else { throw PipFailure.transport("firmware reply missing") }
    guard firmware == 0x0306 else { throw PipFailure.unsupportedFirmware }
    func waitForLayout(_ value: UInt16) throws -> UInt16 {
        var observed: UInt16?
        for attempt in 0..<3 {
            observed = try query(0xd7)?.current
            if let observed, observed == value { return observed }
            if attempt < 2 { try pause(0.5) }
        }
        throw PipFailure.layoutNotReady(expected: value, observed: observed)
    }
    _ = try waitForLayout(1)
    let frames = navigationFrames()
    for (index, frame) in frames.enumerated() {
        guard try send(frame) else { throw PipFailure.transport("OSD submission failed; sequence stopped") }
        if index < frames.count - 1 { try pause(0.65) }
    }
    try pause(3)
    let layoutValue = try waitForLayout(0)
    return (frames.count, layoutValue)
}

nonisolated(unsafe) private var interrupted: sig_atomic_t = 0
private let operationBudget: Double = 50

func checkDeadline(_ deadline: Double) throws {
    guard interrupted == 0, ProcessInfo.processInfo.systemUptime < deadline else {
        throw PipFailure.transport("cancelled or deadline exceeded")
    }
}

func selfTest() throws {
    let hidProperties = ["VendorID": 0x043e, "ProductID": 0x9a8a, "PrimaryUsagePage": 0xff00,
                         "PrimaryUsage": 1, "MaxInputReportSize": 64, "MaxOutputReportSize": 64]
    try require(supportedHidInterface(hidProperties), "exact verified LG HID interface admitted")
    for name in hidProperties.keys {
        var changed = hidProperties
        changed[name] = changed[name]! + 1
        try require(!supportedHidInterface(changed), "every HID identity and report size must match")
    }
    try require(!supportedHidInterface([:]), "missing HID metadata is not an allowed device")
    let hidQuery = try hidQueryReports(0xd7)
    try require(hidQuery.count == 2 && hidQuery.allSatisfy { $0.count == 64 }, "two bounded HID query reports")
    try require(Array(hidQuery[0].prefix(13)) == [8, 1, 0x55, 3, 5, 0, 3, 0x37, 0x51, 0x82, 1, 0xd7, 0x6b], "verified HID submit envelope")
    try require(Array(hidQuery[1].prefix(8)) == [8, 2, 0x55, 4, 11, 0, 11, 0x37], "read-only HID collection envelope")
    let menu = try hidNavigationReport(navigationFrames()[1])
    try require(menu.count == 64 && Array(menu.prefix(15)) == [8, 1, 0x55, 3, 7, 0, 3, 0x37, 0x51, 0x84, 3, 0xf0, 4, 0x43, 0x0f], "one HID submit for one Menu event")
    do {
        _ = try hidNavigationReport([0x73, 0x74, 0x6e, 0x51, 0x84, 3, 0xd6, 0, 4, 0x6a, 0x65, 0x64])
        throw PipFailure.assertion("arbitrary HID setting admitted")
    } catch PipFailure.usage {}
    try require(operationBudget >= 45, "total timeout covers all bounded exchanges and menu pacing")
    try require(try queryFrame(0xd7) == [0x73, 0x74, 0x6e, 0x51, 0x82, 0x01, 0xd7, 0x6b, 0x65, 0x64], "fixed layout GET")
    try require(try queryFrame(0xc9) == [0x73, 0x74, 0x6e, 0x51, 0x82, 0x01, 0xc9, 0x75, 0x65, 0x64], "fixed firmware GET")
    do {
        _ = try queryFrame(0xd6)
        throw PipFailure.assertion("unsupported query accepted")
    } catch PipFailure.usage {}
    let frames = navigationFrames()
    try require(frames.count == 9, "one reset and exactly eight OSD events")
    try require(frames[0] == [0x73, 0x74, 0x6e, 0x51, 0x84, 0x03, 0xf0, 0, 1, 0x49, 0x65, 0x64], "navigation reset is not factory reset")
    try require(frames.dropFirst().map { $0[8] } == [0x43, 0x40, 0x40, 0x44, 0x40, 0x44, 0x40, 0x44], "calibrated reverse-wrap navigation")
    for frame in frames {
        try require(frame.count == 12 && frame[5] == 3 && frame[6] == 0xf0, "only normal F0 writes")
        try require(frame[2...9].reduce(UInt8(0), ^) == 0, "DDC checksum")
    }
    let off: [UInt8] = [0x6e, 0x88, 2, 0, 0xd7, 1, 0, 255, 0, 1, 0x9c]
    try require(parseReply(off, feature: 0xd7) == VCPReply(maximum: 255, current: 1), "validated single-picture reply")
    try require(parseReply([0, 0] + off, feature: 0xd7)?.current == 1, "bounded framing prefix")
    try require(parseReply(Array(off.dropLast()), feature: 0xd7) == nil, "incomplete reply rejected")
    try require(parseReply(off, feature: 0xc9) == nil, "wrong feature rejected")
    var corrupt = off
    corrupt[9] = 0
    try require(parseReply(corrupt, feature: 0xd7) == nil, "corrupt checksum rejected")
    try require(parseReply([UInt8](repeating: 0, count: 513) + off, feature: 0xd7) == nil, "bounded reply length")
    var requested: [UInt8] = []
    var sent: [[UInt8]] = []
    var modes: [UInt16] = [0, 1, 0]
    let sentCount = try enablePip(query: { feature in
        requested.append(feature)
        return feature == 0xc9 ? VCPReply(maximum: 65535, current: 0x0306) : VCPReply(maximum: 255, current: modes.removeFirst())
    }, send: { frame in sent.append(frame); return true }, pause: { _ in })
    try require(sentCount.submittedFrames == 9 && sent == navigationFrames(), "exactly one fixed navigation sequence")
    try require(sentCount.layoutValue == 0, "return the successful final layout readback")
    try require(requested == [0xc9, 0xd7, 0xd7, 0xd7], "only reads repeat while waiting for off")
    for firmware in [UInt16(0x0305), 0x0307] {
        var writes = 0
        do {
            _ = try enablePip(query: { _ in VCPReply(maximum: 65535, current: firmware) },
                              send: { _ in writes += 1; return true }, pause: { _ in })
            throw PipFailure.assertion("uncalibrated firmware accepted")
        } catch PipFailure.unsupportedFirmware {}
        try require(writes == 0, "firmware gate prevents every OSD write")
    }
    var blockedWrites = 0
    do {
        _ = try enablePip(query: { feature in
            VCPReply(maximum: 65535, current: feature == 0xc9 ? 0x0306 : 0)
        }, send: { _ in blockedWrites += 1; return true }, pause: { _ in })
        throw PipFailure.assertion("non-off layout accepted")
    } catch PipFailure.layoutNotReady(let expected, let observed) {
        try require(expected == 1 && observed == 0, "pre-navigation layout failure is stage-qualified")
    }
    try require(blockedWrites == 0, "unknown active layout never enters the menu")
    var attemptedWrites = 0
    do {
        _ = try enablePip(query: { feature in
            VCPReply(maximum: 65535, current: feature == 0xc9 ? 0x0306 : 1)
        }, send: { _ in attemptedWrites += 1; return attemptedWrites != 4 }, pause: { _ in })
        throw PipFailure.assertion("failed menu submission accepted")
    } catch PipFailure.transport {}
    try require(attemptedWrites == 4, "a failed OSD submission is never repeated or followed by another key")
    var firmwareReads = 0
    var layoutReads = 0
    let delayedCount = try enablePip(query: { feature in
        if feature == 0xc9 {
            firmwareReads += 1
            return firmwareReads < 3 ? nil : VCPReply(maximum: 65535, current: 0x0306)
        }
        layoutReads += 1
        return VCPReply(maximum: 255, current: layoutReads == 1 ? 1 : 0)
    }, send: { _ in true }, pause: { _ in })
    try require(firmwareReads == 3 && delayedCount.submittedFrames == 9, "missing firmware replies may repeat only the read")
    var missingReads = 0
    var missingWrites = 0
    do {
        _ = try enablePip(query: { _ in missingReads += 1; return nil },
                          send: { _ in missingWrites += 1; return true }, pause: { _ in })
        throw PipFailure.assertion("missing firmware accepted")
    } catch PipFailure.transport {}
    try require(missingReads == 3 && missingWrites == 0, "missing firmware fails before OSD with bounded reads")
    var finalReads = 0
    var finalWrites = 0
    do {
        _ = try enablePip(query: { feature in
            if feature == 0xc9 { return VCPReply(maximum: 65535, current: 0x0306) }
            finalReads += 1
            return finalReads == 1 ? VCPReply(maximum: 255, current: 1) : nil
        }, send: { _ in finalWrites += 1; return true }, pause: { _ in })
        throw PipFailure.assertion("missing final layout accepted")
    } catch PipFailure.layoutNotReady(let expected, let observed) {
        try require(expected == 0 && observed == nil && finalWrites == 9, "post-navigation failure identifies completed writes and missing readback")
    }
    print("PASS: fixed LG GETs, calibrated one-shot navigation, checksums, and bounded reply matching")
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--self-test"] {
        try selfTest()
    } else if arguments == ["--probe-hid"] || arguments == ["--enable"] {
        let result = try runHid(enable: arguments == ["--enable"])
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    } else { throw PipFailure.usage }
} catch {
    let result: [String: Any] = ["ok": false, "error": String(describing: error)]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    exit(1)
}