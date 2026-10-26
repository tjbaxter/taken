package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.todo.ChunkOutcome
import com.tombaxter.taken.core.todo.ChunkSorting
import com.tombaxter.taken.core.todo.NoteSorter
import com.tombaxter.taken.core.todo.RawTodo
import com.tombaxter.taken.core.todo.SortedChunk
import com.tombaxter.taken.core.todo.SpokenNote
import com.tombaxter.taken.core.todo.TodoContext
import com.tombaxter.taken.core.todo.TodoDraft
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoSorting
import com.tombaxter.taken.core.todo.TodoValidation

/**
 * The fifteen fixed notes of the iPhone's on-device sorting eval (Taken/Todo/TodoEval.swift), kept here as test
 * fixtures. The eval itself is an owner-only internal tool and is left out of Android (SPEC-ANDROID 7.1 and 18); its
 * notes and pass rules still pin the grounding and validation rules the tests below run against.
 */
object TodoEval {
    const val PASS_BAR = 14
    const val PART_LIMIT = 15.0

    /** Monday 19 October 2026, 10:00 in London, the day starting at 04:00: the same "now" on every run. */
    val context: TodoContext get() = TodoContext(at(2026, 10, 19, 10), london, 4)

    sealed class ExpectedDue {
        data object None : ExpectedDue()
        data class At(val day: DayKey, val hour: Int, val minute: Int) : ExpectedDue()
        data class Day(val day: DayKey) : ExpectedDue()
        data class On(val day: DayKey) : ExpectedDue()
    }

    data class Case(
        val id: Int,
        val note: String,
        val counts: IntRange,
        val dues: List<ExpectedDue>? = null,
        val keeps: List<String> = emptyList(),
        val wholeNote: Boolean = false,
        val timed: Boolean = false,
        val expected: String,
    )

    private fun case(
        id: Int, note: String, count: Int = 1, counts: IntRange? = null, dues: List<ExpectedDue>? = null,
        keeps: List<String> = emptyList(), wholeNote: Boolean = false, timed: Boolean = false, expected: String,
    ) = Case(id, note, counts ?: count..count, dues, keeps, wholeNote, timed, expected)

    private val monday = DayKey(2026, 10, 19)

    val twoMinuteRamble = "Okay so it's Monday and I've got loads on, let me just get it all out. I've been putting most of this off " +
        "since the weekend and it's starting to pile up. First thing, I need to call Dr Patel about the blood test " +
        "results, they said to ring after ten. Then I should email Marcus the revised budget for the Lisbon trip, he's " +
        "been waiting since last week and I feel bad about it. The kitchen tap is still dripping, which is driving me " +
        "mad, so book a plumber, maybe the one Hannah recommended. Honestly the weather has been grim all week and I " +
        "keep forgetting my umbrella. Anyway, that's not important right now. Tomorrow. Pick up the dry cleaning from " +
        "Clean Express before they close at six. Oh and renew the car insurance with Admiral, the letter came on " +
        "Saturday. I was thinking about the garden as well but that can wait until spring, there's no point now. Cancel " +
        "the Netflix trial before it renews, I never watch it anyway. Order a birthday present for Sophie, she's into " +
        "pottery at the moment so something from that shop on Etsy would be good. Text Raj about five a side, I think " +
        "we're short of players again. It was a good game last week though, we nearly won for once. My back has been a " +
        "bit sore after the gym so I'm taking it easy this week. On Friday. Pay the window cleaner, I owe him for two " +
        "visits now. And finally, back up the photos from my phone to the laptop, it's nearly full and I don't want to " +
        "lose anything from the holiday. That's about it I think, it felt like more in my head."

    val fiveMinuteRamble = "Right, it's been one of those weeks so I'm just going to talk through everything and hope it sorts itself out. " +
        "I've had about four hours of sleep and my brain is all over the place, so bear with me. Work first. I need to " +
        "send Elena the slides for the quarterly review, she wants them before the meeting so that's the priority. The " +
        "meeting itself got moved to Wednesday afternoon, which is annoying because I had the dentist then. So I have " +
        "to rebook the dentist, the practice on Mill Road, and ask for a morning slot next week if they have one. Then " +
        "there's the contract with Brightwater, legal sent comments back and I haven't even opened them yet. Review the " +
        "Brightwater contract comments and reply to legal by Thursday. I keep saying I'll do it and then something else " +
        "comes up, it's the story of my life at the moment. Also chase Daniel for the invoice from September, accounts " +
        "keep asking me about it and it's not even my invoice. Honestly I don't know why that one always lands on me, I " +
        "think it's because I answered the first email. Book the team lunch for Friday, somewhere near the office, " +
        "maybe the Italian place on the corner, it needs to fit twelve people. And update the project tracker before " +
        "standup tomorrow, nobody has touched it since the offsite and it looks terrible. Last time I looked there were " +
        "tasks on it from August that nobody had closed, which says it all really. Okay, home stuff now. The boiler " +
        "made that noise again this morning, the clanking one, so call British Gas and get an engineer out. It's " +
        "probably nothing but I'd rather know before it gets properly cold. Last winter it went out the week before " +
        "Christmas and we had no hot water for three days, which was miserable. The car is due its MOT at the end of " +
        "the month, so book the MOT at the garage in town, the one we used last year. Buy a new phone charger, the " +
        "cable by the bed has gone frayed and it's started to look a bit dodgy. I don't want it catching fire in the " +
        "night or anything dramatic like that. I was going to fix the shelf in the hall at the weekend but I don't " +
        "think I have the right screws, so get screws for the hall shelf from the hardware shop. Mum's birthday is on " +
        "the twenty third, I nearly forgot again, which would not have gone down well. Last year my card got there two " +
        "days late and I'm still hearing about it. Order flowers for Mum from Bloom and Wild and get them delivered on " +
        "the day. Then there's the recycling, which I always forget, so put the green bin out on Tuesday night. Money " +
        "stuff, which I hate. I always feel like I'm behind on something, even when I'm not. Transfer the rent to " +
        "Callum by the first, he sent a reminder already which was a bit embarrassing to be honest. Cancel the Fitzone " +
        "gym membership, I never use it and I think there's a thirty day notice period so it has to be soon. I think " +
        "that's the boring list done, at least for now. Social things. Reply to Jess about the wedding, she needs " +
        "numbers by the end of next week and I still haven't asked about plus ones. Text Owen happy birthday, it's " +
        "today and I always leave it until midnight. Book tickets for the Arctic Monkeys gig before they sell out, the " +
        "presale opens at ten tomorrow morning. And I promised I'd send Grandad the photos from the holiday, so print " +
        "the holiday photos for Grandad, he doesn't really do email. I was also thinking about learning Spanish again " +
        "before the trip in the summer, but that's more of a someday thing, not a to-do, so I won't count it. My knee " +
        "has been sore when I run so maybe I'll take a week off and see how it goes, I don't want to make it worse " +
        "before the half marathon. It's only six weeks away now and I've barely done any long runs, so that's a worry " +
        "for another day. Last few things. Pick up the parcel from the post office, the card said it's there until " +
        "Saturday. And renew my passport, it runs out in March and the summer trip needs six months left on it. That " +
        "really is everything, I think, unless I remember something in the shower like I always do."

    val cases: List<Case> = listOf(
        case(1, "Order Reach toothbrushes on Amazon", dues = listOf(ExpectedDue.None), keeps = listOf("Reach"), expected = "1 to-do, no due, keeps Reach"),
        case(2, "order reach toothbrushes on amazon", dues = listOf(ExpectedDue.None), keeps = listOf("order", "reach", "toothbrushes"), expected = "1 to-do"),
        case(3, "Reach out to Dan about the contract and order Reach floss", count = 2, expected = "2 to-dos"),
        case(
            4, "Today by 4 pm I need to email Sam the invoice, call the bank and pick up my prescription from Boots", count = 3,
            dues = List(3) { ExpectedDue.At(monday, 16, 0) }, expected = "3 to-dos, each due today at 16:00",
        ),
        case(5, "Buy oat milk, bananas and coffee", expected = "1 to-do"),
        case(6, "Restock Always pads and Native deodorant", keeps = listOf("Always", "Native"), expected = "1 to-do, keeps Always and Native"),
        case(
            7, "Um so I was thinking I should finally book the dentist, it's been ages. Oh and text Jess back about Saturday",
            count = 2, dues = listOf(ExpectedDue.None, ExpectedDue.None), expected = "2 to-dos, no due",
        ),
        case(8, "Remind me to renew my passport on Friday", dues = listOf(ExpectedDue.Day(monday.adding(4))), expected = "1 to-do, due Friday, no time"),
        case(
            9, "Call mum at 8 tonight, and tomorrow take the car in for its MOT", count = 2,
            dues = listOf(ExpectedDue.At(monday, 20, 0), ExpectedDue.Day(monday.adding(1))), expected = "2 to-dos",
        ),
        case(10, "Gym at 6", dues = listOf(ExpectedDue.At(monday, 18, 0)), expected = "1 to-do, due today at 18:00"),
        case(
            11, "Honestly today was mad, the meeting ran over and I'm knackered. Anyway the main thing is send the Q3 deck to Priya by Thursday",
            dues = listOf(ExpectedDue.On(monday.adding(3))), expected = "1 to-do, due Thursday 22 October",
        ),
        case(12, "Note to self, the wifi password is on the fridge", wholeNote = true, expected = "No to-do made up"),
        case(13, "I should send messages to my LinkedIn leads", dues = listOf(ExpectedDue.None), keeps = listOf("send", "messages", "leads"), expected = "1 to-do"),
        case(14, twoMinuteRamble, counts = 9..11, keeps = listOf("Patel", "Marcus", "Admiral", "Sophie", "Raj", "Netflix"), timed = true, expected = "9 to 11 to-dos"),
        case(
            15, fiveMinuteRamble, counts = 18..22,
            keeps = listOf("Elena", "Brightwater", "Daniel", "British Gas", "Callum", "Fitzone", "Jess", "Owen", "Grandad"),
            timed = true, expected = "18 to 22 to-dos",
        ),
    )

    /** Whether what was saved for a case is what should be. A long ramble also needs every part sorted in time. */
    fun passes(test: Case, drafts: List<TodoDraft>, partSeconds: List<Double> = emptyList()): Boolean {
        if (test.wholeNote) return drafts == TodoValidation.asSaid(test.note)
        if (test.timed && (partSeconds.isEmpty() || partSeconds.any { it > PART_LIMIT })) return false
        if (drafts.size !in test.counts) return false
        val said = drafts.flatMap { SpokenNote.tokens(it.title) }.toSet()
        if (!test.keeps.all { word -> SpokenNote.tokens(word).all { it in said } }) return false
        val dues = test.dues ?: return true
        val left = drafts.map { it.due }.toMutableList()
        for (expected in dues) {
            val match = left.indexOfFirst { matches(it, expected) }
            if (match < 0) return false
            left.removeAt(match)
        }
        return true
    }

    fun matches(due: TodoDue?, expected: ExpectedDue): Boolean = when {
        due == null && expected == ExpectedDue.None -> true
        due is TodoDue.Time && expected is ExpectedDue.At -> {
            val local = due.at.atZone(london)
            DayKey.calendarDateOf(due.at, london) == expected.day && local.hour == expected.hour && local.minute == expected.minute
        }
        due is TodoDue.Day && expected is ExpectedDue.Day -> due.day == expected.day
        due is TodoDue.Day && expected is ExpectedDue.On -> due.day == expected.day
        due is TodoDue.Time && expected is ExpectedDue.On -> DayKey.calendarDateOf(due.at, london) == expected.day
        else -> false
    }

    data class Outcome(val model: List<RawTodo>?, val saved: List<TodoDraft>, val sorting: TodoSorting, val parts: List<SortedChunk>)

    /** Each part's seconds for the timing check; a part with no answer in time never passes it. */
    fun partSeconds(parts: List<SortedChunk>): List<Double> =
        parts.map { if (it.outcome == ChunkOutcome.TimedOut) Double.POSITIVE_INFINITY else it.seconds }

    /** A note as the app sorts it: a long ramble part by part as it closes, then the rest at the stop. */
    suspend fun sort(test: Case, sorter: ChunkSorting, context: TodoContext, budget: NoteSorter.Budget = NoteSorter.Budget.STANDARD): Outcome {
        val noteSorter = NoteSorter(sorter, context, budget)
        if (test.timed) {
            noteSorter.listen(test.note)
            noteSorter.settle()
        }
        val parts = noteSorter.finish(test.note)
        val note = TodoValidation.assemble(test.note, parts, context)
        val answers = parts.flatMap { (it.outcome as? ChunkOutcome.Model)?.tasks ?: emptyList() }
        val sorted = parts.any { it.outcome is ChunkOutcome.Model }
        return Outcome(if (sorted) answers else null, note.drafts, note.sorting, parts)
    }
}
