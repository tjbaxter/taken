package com.tombaxter.taken.core.profile

import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.model.asObject
import com.tombaxter.taken.core.model.asString
import com.tombaxter.taken.core.model.opt

/**
 * Profile (REDESIGN.md): a name, optional and kept on this phone next to the log. Nothing is asked at first launch; the
 * avatar on every tab opens it. Ported from Taken/Profile/Profile.swift.
 */
data class Profile(val name: String = "") {
    /** "TB" for Thomas Baxter, "T" for Tom. Null without a name. */
    val initials: String?
        get() {
            val words = name.split(Regex("\\s+")).filter { it.isNotEmpty() && it.first().isLetter() }
            val first = words.firstOrNull()?.first() ?: return null
            if (words.size <= 1) return first.uppercase()
            return (first.toString() + words.last().first()).uppercase()
        }

    companion object {
        /** At most this many characters. */
        const val MAX_NAME_LENGTH = 40

        /** The name as typed, trimmed, spaces collapsed and capped. */
        fun clean(raw: String): String = raw.split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ").take(MAX_NAME_LENGTH)
    }
}

/** profile.json: `{"name": "..."}`. An unreadable name reads as none. */
object ProfileCodec {
    fun encode(profile: Profile): String = TakenJson.obj("name" to TakenJson.string(profile.name)).toString()

    fun decode(text: String): Profile {
        val c = TakenJson.parse(text).asObject()
        return Profile(name = TakenJson.lenient { c.opt("name")?.asString() } ?: "")
    }
}
