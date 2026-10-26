package com.tombaxter.taken.core.catalog

import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.ItemDraft
import kotlin.math.floor

/** How often an item is taken, as the Add sheet and the item sheet offer it. Ported from Taken/Views/AddSheet.swift. */
enum class FrequencyChoice(val title: String) {
    DAILY("Daily"),
    ALTERNATE("Every other day"),
    WEEKLY("Weekly"),
    TWICE("2x daily"),
    THRICE("3x daily"),
    DAYS("Days");

    /**
     * The frequency to save. Days with none picked is every day, so an item is never added that is never due. Weekly is
     * the one weekday `weekday` (Calendar numbering, 1 is Sunday), saved as a one-day Days set.
     */
    fun frequency(weekdays: Set<Int>, weekday: Int): Frequency = when (this) {
        DAILY -> Frequency.Daily(1)
        TWICE -> Frequency.Daily(2)
        THRICE -> Frequency.Daily(3)
        ALTERNATE -> Frequency.AlternateDays
        WEEKLY -> Frequency.Weekdays(setOf(weekday.coerceIn(1, 7)))
        DAYS -> if (weekdays.isEmpty()) Frequency.Daily(1) else Frequency.Weekdays(weekdays)
    }

    companion object {
        /** Monday to Friday until other days are picked. */
        val defaultDays: Set<Int> = setOf(2, 3, 4, 5, 6)

        fun of(frequency: Frequency): FrequencyChoice = when (frequency) {
            is Frequency.Daily -> if (frequency.times >= 3) THRICE else if (frequency.times == 2) TWICE else DAILY
            Frequency.AlternateDays -> ALTERNATE
            is Frequency.Weekdays -> if (frequency.days.size == 1) WEEKLY else DAYS
        }
    }
}

/** What the Add sheet hands to the stack: every picked chip and every other name, each with its own frequency. */
object AddPlan {
    /**
     * How often a pick starts: Weekly for a weekly catalog entry (Semaglutide, Tirzepatide, or a brand of their
     * injections), else Daily, so Oral Semaglutide (Rybelsus, the Wegovy pill) starts on Daily.
     */
    fun defaultChoice(name: String): FrequencyChoice =
        if (Catalog.entryMatching(name)?.weekly == true) FrequencyChoice.WEEKLY else FrequencyChoice.DAILY

    /**
     * `extras` are picks that are not chips: a suggestion, the typed text as a row, or text left in the field. Choices
     * and days are kept under each pick's name; a weekly pick's day is in `weekly`, else `weekday`, the weekday of the
     * day being lived. A name picked twice, in any case, is added once.
     */
    fun drafts(
        selected: List<String>,
        extras: List<String>,
        choices: Map<String, FrequencyChoice>,
        days: Map<String, Set<Int>>,
        weekly: Map<String, Int> = emptyMap(),
        weekday: Int,
    ): List<ItemDraft> {
        val seen = HashSet<String>()
        val drafts = ArrayList<ItemDraft>()
        for (key in selected + extras) {
            val name = key.trim()
            if (name.isEmpty() || !seen.add(Catalog.lookupKey(name))) continue
            val choice = choices[key] ?: defaultChoice(name)
            val frequency = choice.frequency(days[key] ?: FrequencyChoice.defaultDays, weekly[key] ?: weekday)
            drafts.add(ItemDraft(name = name, code = Catalog.entryMatching(name)?.code, frequency = frequency))
        }
        return drafts
    }

    /** How many suggestion rows fit under the pinned field, never a scroll: floor((available + 1) / (rowHeight + 1)). */
    fun rowCapacity(available: Float, rowHeight: Float): Int {
        if (available <= 0f || rowHeight <= 0f) return 0
        return floor((available + 1f) / (rowHeight + 1f)).toInt()
    }
}

/** The Add sheet's words, in one place so the copy tests cover every one. */
object AddCopy {
    const val TITLE = "Add to stack"
    const val SUBTITLE = "Tap what you take."
    const val HOW_OFTEN = "How often"
    const val ADD = "Add"
    const val CUSTOM_CHIP = "Custom item"
    const val FIELD_PROMPT = "Search or type a name"
    const val FIELD_LABEL = "Name"
    const val CLEAR = "Clear"
    const val IN_STACK = "In your stack"
    const val SELECTED_VALUE = "Selected"
    const val NOT_SELECTED_VALUE = "Not selected"

    /** The last row: what was typed, added as it is. */
    fun literal(text: String): String = "Add “$text”"

    /** What TalkBack hears once typing pauses. */
    fun suggestions(count: Int): String = when (count) {
        0 -> "No suggestions"
        1 -> "1 suggestion"
        else -> "$count suggestions"
    }

    val all: List<String>
        get() = listOf(
            TITLE, SUBTITLE, HOW_OFTEN, ADD, CUSTOM_CHIP, FIELD_PROMPT, FIELD_LABEL, CLEAR, IN_STACK, SELECTED_VALUE,
            NOT_SELECTED_VALUE, "+ " + literal("Lion's Mane"), suggestions(0), suggestions(1), suggestions(4),
        ) + FrequencyChoice.entries.map { it.title }
}
