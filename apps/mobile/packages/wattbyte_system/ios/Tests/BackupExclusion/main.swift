// Run on a Mac:
//   swiftc Classes/BackupExclusion.swift Tests/BackupExclusion/main.swift -o /tmp/check_backup && /tmp/check_backup
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
  if ok { print("ok   \(what)") } else { print("FAIL \(what)"); failures += 1 }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wb-backup-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let db = dir.appendingPathComponent("wattbyte.db").path
let wal = db + "-wal"
FileManager.default.createFile(atPath: db, contents: Data("db".utf8))
FileManager.default.createFile(atPath: wal, contents: Data("wal".utf8))
let missing = db + "-shm"

check(!BackupExclusion.isExcluded(db), "a new file is part of the backup")
let failed = BackupExclusion.apply(to: [db, wal, missing])
check(failed.isEmpty, "marking succeeds; a missing file is skipped, not a failure")
check(BackupExclusion.isExcluded(db), "the database is excluded")
check(BackupExclusion.isExcluded(wal), "the log is excluded")
check(!FileManager.default.fileExists(atPath: missing), "nothing was created for the missing file")
check(BackupExclusion.apply(to: ["/nonexistent/path"]).isEmpty, "a path that does not exist is skipped")
check(BackupExclusion.apply(to: []).isEmpty, "no paths, no work")
exit(failures == 0 ? 0 : 1)
