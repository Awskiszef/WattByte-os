// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Marks files as excluded from iCloud / iTunes backups, and so from a restore onto another device (audit H-06). Pure
/// Foundation so `Tests/BackupExclusion/main.swift` can run it on a Mac.
enum BackupExclusion {
  /// Applies the exclusion to every path that exists. Returns the paths it could not mark.
  static func apply(to paths: [String]) -> [String] {
    var failed: [String] = []
    for path in paths where FileManager.default.fileExists(atPath: path) {
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do { try url.setResourceValues(values) } catch { failed.append(path) }
    }
    return failed
  }

  static func isExcluded(_ path: String) -> Bool {
    (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
  }
}
