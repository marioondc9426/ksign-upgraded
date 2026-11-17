//
//  TweakPreflight.swift
//  Ksign
//
//  looks inside a signed app for the usual reasons a tweaked app crashes on launch
//  (missing libraries, wrong architecture, tweak that is never loaded, iOS too old...)
//  it only reads the files, nothing is run
//

import Foundation
import UIKit

struct PreflightIssue: Identifiable {
	enum Level: Int { case error = 0, warning = 1, info = 2 }

	let id = UUID()
	let level: Level
	let title: String
	let detail: String
}

enum TweakPreflight {
	// MARK: Mach-O reading
	private struct Slice {
		var cpuType: UInt32
		var cpuSubtype: UInt32
		var isDylib: Bool
		var deps: [(path: String, weak: Bool)]
		var rpaths: [String]

		var archName: String {
			switch (cpuType, cpuSubtype & 0x00FFFFFF) {
			case (0x0100000C, 2): return "arm64e"
			case (0x0100000C, _): return "arm64"
			case (0x0000000C, _): return "armv7"
			case (0x01000007, _): return "x86_64"
			case (0x00000007, _): return "i386"
			default: return String(format: "cpu 0x%X", cpuType)
			}
		}
		var isArm64e: Bool { cpuType == 0x0100000C && (cpuSubtype & 0x00FFFFFF) == 2 }
		var isArm64: Bool { cpuType == 0x0100000C && (cpuSubtype & 0x00FFFFFF) != 2 }
	}

	private static func _u32(_ data: Data, _ offset: Int, big: Bool = false) -> UInt32? {
		guard offset >= 0, offset + 4 <= data.count else { return nil }
		let b = data.subdata(in: offset..<offset + 4).map { UInt32($0) }
		return big
			? (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3])
			: (b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0])
	}

	private static func _readAt(_ handle: FileHandle, _ offset: UInt64, _ length: Int) -> Data? {
		do {
			try handle.seek(toOffset: offset)
			guard let data = try handle.read(upToCount: length), data.count == length else { return nil }
			return data
		} catch { return nil }
	}

	private static func _cString(_ data: Data, at offset: Int, end: Int) -> String? {
		guard offset >= 0, offset < end, end <= data.count else { return nil }
		let bytes = data.subdata(in: offset..<end)
		let trimmed = bytes.prefix { $0 != 0 }
		return String(data: Data(trimmed), encoding: .utf8)
	}

	/// slices of a Mach-O file (thin or fat), nil when it is not one
	private static func _slices(of url: URL) -> [Slice]? {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
		defer { try? handle.close() }
		guard let head = _readAt(handle, 0, 8), let magicLE = _u32(head, 0) else { return nil }

		var offsets: [UInt64] = []
		if magicLE == 0xBEBAFECA {   // FAT_MAGIC (big endian on disk)
			let count = Int(_u32(head, 4, big: true) ?? 0)
			guard count > 0, count < 16, let table = _readAt(handle, 8, count * 20) else { return nil }
			for i in 0..<count {
				if let off = _u32(table, i * 20 + 8, big: true) { offsets.append(UInt64(off)) }
			}
		} else if magicLE == 0xFEEDFACF {
			offsets = [0]
		} else {
			return nil
		}

		var result: [Slice] = []
		for base in offsets {
			guard
				let header = _readAt(handle, base, 32),
				_u32(header, 0) == 0xFEEDFACF,
				let cpu = _u32(header, 4), let sub = _u32(header, 8),
				let fileType = _u32(header, 12),
				let ncmds = _u32(header, 16), let sizeofcmds = _u32(header, 20),
				sizeofcmds < 4_000_000,
				let cmds = _readAt(handle, base + 32, Int(sizeofcmds))
			else { continue }

			var slice = Slice(cpuType: cpu, cpuSubtype: sub, isDylib: fileType == 6, deps: [], rpaths: [])
			var cursor = 0
			for _ in 0..<Int(ncmds) {
				guard let cmd = _u32(cmds, cursor), let size = _u32(cmds, cursor + 4), size >= 8 else { break }
				let end = min(cursor + Int(size), cmds.count)
				switch cmd {
				case 0x0C, 0x8000_0018, 0x8000_001F, 0x8000_0023:
					if let nameOffset = _u32(cmds, cursor + 8), let name = _cString(cmds, at: cursor + Int(nameOffset), end: end) {
						slice.deps.append((name, cmd == 0x8000_0018))
					}
				case 0x8000_001C:
					if let pathOffset = _u32(cmds, cursor + 8), let path = _cString(cmds, at: cursor + Int(pathOffset), end: end) {
						slice.rpaths.append(path)
					}
				default: break
				}
				cursor += Int(size)
			}
			result.append(slice)
		}
		return result.isEmpty ? nil : result
	}

	// MARK: Resolving
	private static func _isSystem(_ path: String) -> Bool {
		path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/") || path.hasPrefix("/Developer/")
	}

	private static func _looksJailbreakOnly(_ path: String) -> Bool {
		let lower = path.lowercased()
		return lower.contains("substrate") || lower.contains("ellekit") || lower.contains("libhooker")
			|| lower.contains("/var/jb") || lower.contains("tweakinject") || lower.contains("substitute")
	}

	private static func _exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

	private static func _expand(_ path: String, loader: URL, executableDir: URL) -> URL? {
		if path.hasPrefix("@executable_path") {
			return executableDir.appendingPathComponent(String(path.dropFirst("@executable_path".count)))
		}
		if path.hasPrefix("@loader_path") {
			return loader.deletingLastPathComponent().appendingPathComponent(String(path.dropFirst("@loader_path".count)))
		}
		return path.hasPrefix("/") ? URL(fileURLWithPath: path) : nil
	}

	private static func _resolves(_ dep: String, loader: URL, rpaths: [String], executableDir: URL) -> Bool {
		if dep.hasPrefix("@rpath/") {
			let rest = String(dep.dropFirst("@rpath/".count))
			for rpath in rpaths {
				if let base = _expand(rpath, loader: loader, executableDir: executableDir), _exists(base.appendingPathComponent(rest)) {
					return true
				}
			}
			return false
		}
		guard let url = _expand(dep, loader: loader, executableDir: executableDir) else { return false }
		return _exists(url)
	}

	// MARK: Main entry
	/// `appDirectory` is the `.app` folder (or the folder that contains it)
	static func run(appDirectory: URL, deviceVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> [PreflightIssue] {
		let fm = FileManager.default
		var issues: [PreflightIssue] = []

		var app = appDirectory
		if app.pathExtension != "app" {
			let children = (try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? []
			guard let found = children.first(where: { $0.pathExtension == "app" }) else {
				return [PreflightIssue(level: .error, title: String.localized("App not found"), detail: appDirectory.path)]
			}
			app = found
		}

		// Info.plist
		guard
			let info = NSDictionary(contentsOf: app.appendingPathComponent("Info.plist")),
			let executableName = info["CFBundleExecutable"] as? String
		else {
			return [PreflightIssue(level: .error, title: String.localized("Info.plist is missing or has no CFBundleExecutable"), detail: "")]
		}

		if let minimum = info["MinimumOSVersion"] as? String {
			let parts = minimum.split(separator: ".").compactMap { Int($0) }
			let wanted = (parts.count > 0 ? parts[0] : 0, parts.count > 1 ? parts[1] : 0)
			let have = (deviceVersion.majorVersion, deviceVersion.minorVersion)
			if wanted.0 > have.0 || (wanted.0 == have.0 && wanted.1 > have.1) {
				issues.append(PreflightIssue(
					level: .error,
					title: String.localized("The app needs a newer iOS"),
					detail: "MinimumOSVersion \(minimum), this device has \(have.0).\(have.1)"
				))
			}
		}

		let executable = app.appendingPathComponent(executableName)
		guard let mainSlices = _slices(of: executable) else {
			issues.append(PreflightIssue(level: .error, title: String.localized("The main binary is missing or is not a Mach-O file"), detail: executableName))
			return issues
		}
		let mainHasArm64e = mainSlices.contains { $0.isArm64e }

		// every Mach-O we should look at: the executable, loose dylibs and frameworks
		var targets: [URL] = [executable]
		var injected: [URL] = []
		if let enumerator = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
			for case let url as URL in enumerator {
				let relative = url.path.replacingOccurrences(of: app.path + "/", with: "")
				if relative.hasPrefix("_CodeSignature") || relative.hasPrefix("SC_Info") { continue }
				let isDylib = url.pathExtension == "dylib"
				let parent = url.deletingLastPathComponent()
				let isFrameworkBinary = parent.pathExtension == "framework"
					&& url.lastPathComponent == parent.deletingPathExtension().lastPathComponent
				guard isDylib || isFrameworkBinary else { continue }
				targets.append(url)
				// only things in the app folder or Frameworks are what a tweak adds
				if parent.path == app.path || parent.lastPathComponent == "Frameworks" || parent.deletingLastPathComponent().lastPathComponent == "Frameworks" {
					injected.append(url)
				}
			}
		}

		var referenced = Set<String>()
		for url in targets {
			guard let slices = _slices(of: url) else { continue }
			for slice in slices {
				for dep in slice.deps { referenced.insert((dep.path as NSString).lastPathComponent) }
			}
		}

		// dependencies
		for url in targets {
			guard let slices = _slices(of: url), let slice = slices.first(where: { $0.isArm64 || $0.isArm64e }) ?? slices.first else { continue }
			let name = url.lastPathComponent

			for dep in slice.deps {
				if _isSystem(dep.path) { continue }
				if _resolves(dep.path, loader: url, rpaths: slice.rpaths, executableDir: app) { continue }

				if _looksJailbreakOnly(dep.path) {
					issues.append(PreflightIssue(
						level: dep.weak ? .warning : .error,
						title: String.localized("Needs a jailbreak library"),
						detail: "\(name) -> \(dep.path)\n" + String.localized("Turn on 'replace Substrate with ElleKit' in the signing options or add the library to the app.")
					))
				} else {
					issues.append(PreflightIssue(
						level: dep.weak ? .warning : .error,
						title: String.localized("Library not found"),
						detail: "\(name) -> \(dep.path)" + (dep.weak ? " (weak, optional)" : "\n" + String.localized("The app crashes at launch with 'Library not loaded'."))
					))
				}
			}
		}

		// architecture of what was injected
		for url in injected {
			guard let slices = _slices(of: url) else { continue }
			let names = slices.map { $0.archName }.joined(separator: ", ")
			if !slices.contains(where: { $0.isArm64 || $0.isArm64e }) {
				issues.append(PreflightIssue(level: .error, title: String.localized("Wrong architecture"), detail: "\(url.lastPathComponent): \(names)\n" + String.localized("Only arm64 and arm64e run on iPhones.")))
			} else if mainHasArm64e && !slices.contains(where: { $0.isArm64e }) {
				issues.append(PreflightIssue(level: .warning, title: String.localized("arm64 tweak in an arm64e app"), detail: "\(url.lastPathComponent): \(names)\n" + String.localized("On A12 or newer the app runs as arm64e and may refuse an arm64-only library.")))
			}
		}

		// loose dylibs nobody loads
		for url in injected where url.pathExtension == "dylib" && !referenced.contains(url.lastPathComponent) {
			issues.append(PreflightIssue(level: .warning, title: String.localized("Tweak is not loaded"), detail: "\(url.lastPathComponent) " + String.localized("is inside the app but no binary loads it, so it does nothing.")))
		}

		// signature / profile
		if !fm.fileExists(atPath: app.appendingPathComponent("_CodeSignature/CodeResources").path) {
			issues.append(PreflightIssue(level: .info, title: String.localized("No code signature folder"), detail: String.localized("Normal for ad-hoc signing, a problem for a real certificate.")))
		}
		if !fm.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path) {
			issues.append(PreflightIssue(level: .info, title: String.localized("No embedded.mobileprovision"), detail: String.localized("Fine with AppSync or TrollStore, an app signed with a certificate needs it.")))
		}

		if issues.isEmpty {
			issues.append(PreflightIssue(level: .info, title: String.localized("No problems found"), detail: String(format: String.localized("%lld binaries checked."), targets.count)))
		}
		return issues.sorted { $0.level.rawValue < $1.level.rawValue }
	}

	/// the whole report as text (for Copy / Share)
	static func report(app: AppInfoPresentable, issues: [PreflightIssue], options: Options?) -> String {
		var lines: [String] = []
		let device = UIDevice.current
		lines.append("Ksign+ tweak test")
		lines.append("App: \(app.name ?? "?") \(app.version ?? "") (\(app.identifier ?? "?"))")
		lines.append("Device: \(device.model), iOS \(device.systemVersion)")
		if let options {
			lines.append("Tweaks: " + (options.injectionFiles.isEmpty ? "none" : options.injectionFiles.map { $0.lastPathComponent }.joined(separator: ", ")))
		}
		lines.append("")
		for issue in issues {
			let tag = issue.level == .error ? "[ERROR]" : issue.level == .warning ? "[WARN] " : "[INFO] "
			lines.append("\(tag) \(issue.title)")
			if !issue.detail.isEmpty { lines.append("        " + issue.detail.replacingOccurrences(of: "\n", with: "\n        ")) }
		}
		return lines.joined(separator: "\n")
	}
}
