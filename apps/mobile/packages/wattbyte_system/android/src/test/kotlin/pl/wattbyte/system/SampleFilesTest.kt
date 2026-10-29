package pl.wattbyte.system

import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** H-05 / G-11: the charging worker's samples are deleted only after the app confirmed it stored them. */
class SampleFilesTest {
    private lateinit var dir: File
    private lateinit var files: SampleFiles

    @BeforeTest
    fun setUp() {
        dir = Files.createTempDirectory("wb-samples").toFile()
        files = SampleFiles(dir)
    }

    @AfterTest
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun names() = dir.list()!!.sorted()

    @Test
    fun `nothing to hand over is null`() {
        assertNull(files.peek())
        files.append("a")
        assertNotNull(files.peek())
    }

    @Test
    fun `peek does not delete anything - the same lines come back until they are acknowledged`() {
        files.append("a")
        files.append("b")
        val first = files.peek()!!
        assertEquals(listOf("a", "b"), first.lines)
        // The app crashed before storing them: nothing was acknowledged, the next pass sees them again.
        val again = files.peek()!!
        assertEquals(listOf("a", "b"), again.lines)
        assertEquals(first.token, again.token)
        files.ack(again.token)
        assertNull(files.peek())
        assertEquals(emptyList<String>(), names())
    }

    @Test
    fun `samples appended while a batch is out are kept and delivered after it`() {
        files.append("a")
        val batch = files.peek()!!
        files.append("b") // the worker keeps recording while Dart is busy
        files.ack(batch.token) // acknowledges only what it was given
        val next = files.peek()!!
        assertEquals(listOf("b"), next.lines)
        assertTrue(next.token > batch.token)
        files.ack(next.token)
        assertNull(files.peek())
    }

    @Test
    fun `an unacknowledged batch is delivered first, together with newer samples, in order`() {
        files.append("a")
        files.peek() // never acknowledged
        files.append("b")
        val batch = files.peek()!!
        assertEquals(listOf("a", "b"), batch.lines)
        files.ack(batch.token)
        assertNull(files.peek())
    }

    @Test
    fun `acknowledging an old token does not delete a newer batch`() {
        files.append("a")
        val old = files.peek()!!
        files.append("b")
        val newer = files.peek()!!
        files.ack(old.token) // removes what that token covered ("a") and nothing newer
        val rest = files.peek()!!
        assertEquals(listOf("b"), rest.lines)
        assertEquals(newer.token, rest.token)
    }

    @Test
    fun `a torn last line is returned as is for the caller to drop and does not stop the others`() {
        File(dir, SampleFiles.LIVE).writeText("a\nb\n{\"timeMs\":12")
        val batch = files.peek()!!
        assertEquals(3, batch.lines.size)
        assertEquals("a", batch.lines[0])
    }

    @Test
    fun `tokens never repeat, also with a frozen clock, so a late ack cannot hit a newer batch`() {
        val frozen = SampleFiles(dir, clock = { 1000L })
        frozen.append("a")
        val one = frozen.peek()!!
        frozen.ack(one.token)
        frozen.append("b")
        val two = frozen.peek()!!
        assertTrue(two.token > one.token)
        frozen.ack(one.token) // the stale acknowledgement of the first batch arrives late
        assertEquals(listOf("b"), frozen.peek()!!.lines)
    }

    @Test
    fun `an empty live file is cleaned up and is not a batch`() {
        File(dir, SampleFiles.LIVE).writeText("")
        assertNull(files.peek())
        assertEquals(emptyList<String>(), names())
    }

    @Test
    fun `concurrent appends and hand-overs lose nothing and deliver at least once`() {
        val total = 400
        val delivered = java.util.Collections.synchronizedSet(HashSet<String>())
        val writer = Thread { for (i in 0 until total) files.append("s$i") }
        val reader = Thread {
            repeat(200) {
                files.peek()?.let { b ->
                    delivered.addAll(b.lines)
                    files.ack(b.token)
                }
            }
        }
        writer.start(); reader.start(); writer.join(); reader.join()
        files.peek()?.let { b -> delivered.addAll(b.lines); files.ack(b.token) }
        assertEquals(total, delivered.size)
        assertNull(files.peek())
    }
}
