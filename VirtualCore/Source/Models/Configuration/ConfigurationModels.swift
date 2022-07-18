//
//  ConfigurationModels.swift
//  VirtualCore
//
//  Created by Guilherme Rambo on 17/07/22.
//

import Foundation
import SystemConfiguration

public struct VBDisplayDevice: Identifiable, Hashable, Codable {
    public init(id: UUID = UUID(), name: String = "Default", width: Int = 1920, height: Int = 1080, pixelsPerInch: Int = 144) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.pixelsPerInch = pixelsPerInch
    }
    
    public var id = UUID()
    public var name = "Default"
    public var width = 1920
    public var height = 1080
    public var pixelsPerInch = 144
}

public struct VBNetworkDevice: Identifiable, Hashable, Codable {
    public init(id: String = "Default", name: String = "Default", kind: VBNetworkDevice.Kind = Kind.NAT, macAddress: String = VZMACAddress.randomLocallyAdministered().string.uppercased()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.macAddress = macAddress
    }
    
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        case NAT
        case bridge
        
        public var name: String {
            switch self {
            case .NAT: return "NAT"
            case .bridge: return "Bridge"
            }
        }
    }

    public var id = "Default"
    public var name = "Default"
    public var kind = Kind.NAT
    public var macAddress = VZMACAddress.randomLocallyAdministered().string.uppercased()
}

public struct VBPointingDevice: Hashable, Codable {
    public enum Kind: Int, Identifiable, CaseIterable, Codable {
        public var id: RawValue { rawValue }

        public var warning: String? {
            guard self == .trackpad else { return nil }
            return "Trackpad is only recognized by VMs running macOS 13 and later."
        }

        public var isSupportedByGuest: Bool {
            if #available(macOS 13.0, *) {
                return true
            } else {
                return self == .mouse
            }
        }

        case mouse
        case trackpad
    }

    public var kind = Kind.mouse
}

public struct VBSoundDevice: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name = "Default"
    public var enableOutput = true
    public var enableInput = true
}

public struct VBMacDevice: Hashable, Codable {
    public var cpuCount: Int
    public var memorySize: UInt64
    public var pointingDevice: VBPointingDevice
    public var displayDevices: [VBDisplayDevice]
    public var networkDevices: [VBNetworkDevice]
    public var soundDevices: [VBSoundDevice]
    public var NVRAM = [VBNVRAMVariable]()
}

public struct VBSharedFolder: Identifiable, Hashable, Codable {
    public var id = UUID()
    public var name: String { url.lastPathComponent }
    public var url: URL
    public var isReadOnly = true
}

public struct VBMacConfiguration: Hashable, Codable {

    public var hardware = VBMacDevice.default
    public var sharedFolders = [VBSharedFolder]()

}

// MARK: - Default Devices

public extension VBMacConfiguration {
    static var `default`: VBMacConfiguration { .init() }
}

public extension VBMacDevice {
    static var `default`: VBMacDevice {
        VBMacDevice(
            cpuCount: .vb_suggestedVirtualCPUCount,
            memorySize: .vb_suggestedMemorySize,
            pointingDevice: .default,
            displayDevices: [.default],
            networkDevices: [.default],
            soundDevices: [.default]
        )
    }
}

public extension VBPointingDevice {
    static var `default`: VBPointingDevice { .init() }
}

public extension VBNetworkDevice {
    static var `default`: VBNetworkDevice { .init() }
}

public extension VBSoundDevice {
    static var `default`: VBSoundDevice { .init() }
}

public extension VBDisplayDevice {
    static var `default`: VBDisplayDevice { .matchHost }

    static var fallback: VBDisplayDevice { .init() }

    static var matchHost: VBDisplayDevice {
        guard let screen = NSScreen.main else { return .fallback }

        guard let resolution = screen.deviceDescription[.resolution] as? NSSize else { return .fallback }
        guard let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }

        let pointHeight = size.height - screen.safeAreaInsets.top

        return VBDisplayDevice(
            id: UUID(),
            name: ProcessInfo.processInfo.vb_hostName,
            width: Int(size.width * screen.backingScaleFactor),
            height: Int(pointHeight * screen.backingScaleFactor),
            pixelsPerInch: Int(resolution.width)
        )
    }

    static var sizeToFit: VBDisplayDevice {
        guard let screen = NSScreen.main,
              let size = screen.deviceDescription[.size] as? NSSize else { return .fallback }

        let reference = VZMacGraphicsDisplayConfiguration(for: screen, sizeInPoints: size)

        return VBDisplayDevice(
            id: UUID(),
            name: ProcessInfo.processInfo.vb_hostName,
            width: reference.widthInPixels,
            height: reference.heightInPixels,
            pixelsPerInch: reference.pixelsPerInch
        )
    }
}

// MARK: - Presets

public struct VBDisplayPreset: Identifiable, Hashable {
    public var id: String { name }
    public var name: String
    public var device: VBDisplayDevice
    public var warning: String? = nil
    public var isAvailable = true
}

public extension VBDisplayPreset {
    static var presets: [VBDisplayPreset] {
        [
            VBDisplayPreset(name: "Full HD", device: .init(name: "1920x1080@144", width: 1920, height: 1080, pixelsPerInch: 144)),
            VBDisplayPreset(name: "4.5K Retina", device: .init(name: "4480x2520", width: 4480, height: 2520, pixelsPerInch: 218)),
            // This preset is only relevant for displays with a notch.
            VBDisplayPreset(name: "Match \"\(ProcessInfo.processInfo.vb_mainDisplayName)\"", device: .matchHost, warning: "If things look small in the VM after boot, go to System Preferences and select a HiDPI scaled reslution for the display.", isAvailable: ProcessInfo.processInfo.vb_mainDisplayHasNotch),
            VBDisplayPreset(name: "Size to fit in \"\(ProcessInfo.processInfo.vb_mainDisplayName)\"", device: .sizeToFit)
        ]
    }
    
    static var availablePresets: [VBDisplayPreset] { presets.filter(\.isAvailable) }
}

public struct VBNetworkDeviceBridgeInterface: Identifiable {
    public var id: String
    public var name: String
    
    init(_ interface: VZBridgedNetworkInterface) {
        self.id = interface.identifier
        self.name = interface.localizedDisplayName ?? interface.identifier
    }
}

public extension VBNetworkDevice {
    static var defaultBridgeInterfaceID: String? {
        VZBridgedNetworkInterface.networkInterfaces.first?.identifier
    }
    
    static var bridgeInterfaces: [VBNetworkDeviceBridgeInterface] {
        VZBridgedNetworkInterface.networkInterfaces.map(VBNetworkDeviceBridgeInterface.init)
    }
    
    static var appSupportsBridgedNetworking: Bool {
        NSApplication.shared.hasEntitlement("com.apple.vm.networking")
    }
}

// MARK: - Helpers

public extension VBNetworkDevice {
    static func validateMAC(_ address: String) -> Bool {
        VZMACAddress(string: address) != nil
    }
}

public extension VBMacDevice {
    static let minimumCPUCount: Int = VZVirtualMachineConfiguration.minimumAllowedCPUCount

    static let maximumCPUCount: Int = {
        min(ProcessInfo.processInfo.processorCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)
    }()

    static let virtualCPUCountRange: ClosedRange<Int> = {
        minimumCPUCount...maximumCPUCount
    }()

    static let minimumMemorySizeInGigabytes = 2

    static let maximumMemorySizeInGigabytes: Int = {
        let value = Swift.min(ProcessInfo.processInfo.physicalMemory, VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        return Int(value / 1024 / 1024 / 1024)
    }()

    static let memorySizeRangeInGigabytes: ClosedRange<Int> = {
        minimumMemorySizeInGigabytes...maximumMemorySizeInGigabytes
    }()
}

public extension VBDisplayDevice {

    static let minimumDisplayDimension = 800

    static var maximumDisplayWidth = 6016

    static var maximumDisplayHeight = 3384

    static let displayWidthRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayWidth
    }()

    static let displayHeightRange: ClosedRange<Int> = {
        minimumDisplayDimension...maximumDisplayHeight
    }()

    static let minimumDisplayPPI = 80

    static let maximumDisplayPPI = 218

    static let displayPPIRange: ClosedRange<Int> = {
        minimumDisplayPPI...maximumDisplayPPI
    }()

}

extension Int {

    static let vb_suggestedVirtualCPUCount: Int = {
        let totalAvailableCPUs = ProcessInfo.processInfo.processorCount

        var virtualCPUCount = totalAvailableCPUs <= 1 ? 1 : totalAvailableCPUs / 2
        virtualCPUCount = Swift.max(virtualCPUCount, VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        virtualCPUCount = Swift.min(virtualCPUCount, VZVirtualMachineConfiguration.maximumAllowedCPUCount)

        return virtualCPUCount
    }()

}

extension UInt64 {

    static let vb_suggestedMemorySize: UInt64 = {
        let hostMemory = ProcessInfo.processInfo.physicalMemory
        var memorySize = hostMemory / 2
        memorySize = Swift.max(memorySize, VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        memorySize = Swift.min(memorySize, VZVirtualMachineConfiguration.maximumAllowedMemorySize)

        return memorySize
    }()

}

public extension ProcessInfo {
    var vb_hostName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as? String ?? "This Mac"
    }
    
    var vb_mainDisplayName: String {
        guard let screen = NSScreen.main else { return "\(vb_hostName)" }
        return screen.localizedName
    }
    
    var vb_mainDisplayHasNotch: Bool { NSScreen.main?.auxiliaryTopLeftArea != nil }
}
