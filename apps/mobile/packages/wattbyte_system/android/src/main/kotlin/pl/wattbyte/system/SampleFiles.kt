// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

package pl.wattbyte.system

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The file layer of [SampleStore], free of Android classes so a plain JVM test can drive it.
 *
 * Hand-over is two-phase (audit H-05, G-11): [peek] never deletes anything. It renames the live file to a numbered
 * `.pending` file and returns the content of every pending file; the caller persists it and only then calls [ack],
 * which deletes the files it was given. A crash, a failing database or a killed background task in between leaves the
 * pending files in place and the next [peek] returns them again (at-least-once; inserting a sample twice is a no-op in
 * the app's database: unique (time, source) + ignore). Samples appended while a batch is out go to a fresh live file.
 */
class SampleFiles(private val dir: File, private val clock: () -> Long = System::currentTimeMillis) {
    private val lock = Any()
    private var lastToken = 0L

    class Batch(val token: Long, val lines: List<String>)

    private fun live() = File(dir, LIVE)

    private fun pendingFiles(): List<Pair<Long, File>> =
        (dir.listFiles() ?: emptyArray())
            .mapNotNull { f ->
                val m = PENDING.matchEntire(f.name) ?: return@mapNotNull null
                m.groupValues[1].toLong() to f
            }
            .sortedBy { it.first }

    fun append(line: String) = synchronized(lock) {
        live().appendText(line + "\n")
    }

    /** Everything not acknowledged yet, oldest first; null when there is nothing. */
    fun peek(): Batch? = synchronized(lock) {
        val current = live()
        if (current.exists()) {
            if (current.length() > 0) {
                // Tokens only grow, also after everything was acknowledged: a late ack of an old batch must never match a newer one.
                val next = maxOf((pendingFiles().lastOrNull()?.first ?: 0L) + 1, lastToken + 1, clock())
                lastToken = next
                Files.move(current.toPath(), File(dir, pendingName(next)).toPath(), StandardCopyOption.ATOMIC_MOVE)
            } else {
                current.delete()
            }
        }
        val files = pendingFiles()
        if (files.isEmpty()) return null
        Batch(files.last().first, files.flatMap { (_, f) -> f.readLines() })
    }

    /** Deletes the pending files up to and including [token]; a newer batch (a later token) is untouched. */
    fun ack(token: Long) = synchronized(lock) {
        pendingFiles().filter { it.first <= token }.forEach { it.second.delete() }
    }

    companion object {
        const val LIVE = "wattbyte_samples.jsonl"
        private val PENDING = Regex("""wattbyte_samples\.(\d{16})\.pending""")
        private fun pendingName(seq: Long) = "wattbyte_samples.${seq.toString().padStart(16, '0')}.pending"
    }
}
