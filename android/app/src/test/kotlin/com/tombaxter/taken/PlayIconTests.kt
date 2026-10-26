package com.tombaxter.taken

import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import javax.imageio.ImageIO
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Play store's icon, android/store-assets/icon-512.png (SPEC-ANDROID 14.2), against Google Play's published spec
 * (https://developer.android.com/distribute/google-play/resources/icon-design-specifications): 512 x 512, "32-bit PNG",
 * sRGB, at most 1024 KB, a "Full square" with no rounding ("Google Play dynamically handles masking"). brand/icon.py
 * renders it from the iPhone icon's artwork, and android.yml's icons job checks it is what icon.py renders. Plain JVM.
 */
class PlayIconTests {
    private val file = File("../store-assets/icon-512.png")

    /** The PNG's chunk types, in order. */
    private fun chunks(bytes: ByteArray): List<String> {
        val types = ArrayList<String>()
        var at = 8
        while (at + 8 <= bytes.size) {
            val length = ByteBuffer.wrap(bytes, at, 4).int
            types.add(String(bytes, at + 4, 4, Charsets.US_ASCII))
            at += 12 + length
        }
        return types
    }

    @Test
    fun testThePlayIconIsA512SquareOpaque32BitPng() {
        val bytes = file.readBytes()
        assertTrue(bytes.size <= 1024 * 1024, "at most 1024 KB: ${bytes.size} bytes")
        val signature = byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 0x0D, 0x0A, 0x1A, 0x0A)
        assertTrue(bytes.copyOfRange(0, 8).contentEquals(signature), "a PNG")
        val header = ByteBuffer.wrap(bytes, 16, 8)
        assertEquals(512, header.int, "512 wide")
        assertEquals(512, header.int, "512 high")
        assertEquals(8, bytes[24].toInt(), "8 bits a channel")
        assertEquals(6, bytes[25].toInt(), "RGBA: a 32-bit PNG")
        val types = chunks(bytes)
        assertEquals("IHDR", types.first())
        assertTrue("iCCP" in types || "sRGB" in types, "an sRGB colour profile: $types")

        val image = ImageIO.read(file)
        var transparent = 0
        for (y in 0 until image.height) {
            for (x in 0 until image.width) if ((image.getRGB(x, y) ushr 24) != 0xFF) transparent += 1
        }
        assertEquals(0, transparent, "opaque everywhere: a full square, never rounded")
        // The corners are the icon's canvas, so Play's own mask shows no edge of a rounded shape inside the square.
        for ((x, y) in listOf(0 to 0, 511 to 0, 0 to 511, 511 to 511)) {
            val rgb = image.getRGB(x, y) and 0xFFFFFF
            assertTrue(((rgb shr 16) and 0xFF) < 0x14 && ((rgb shr 8) and 0xFF) < 0x14 && (rgb and 0xFF) < 0x14, "a dark canvas corner")
        }
    }
}
