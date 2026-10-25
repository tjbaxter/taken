package com.tombaxter.taken.core

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.catalog.Suggest
import com.tombaxter.taken.core.catalog.SuggestRow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/SuggestTests.swift: type-ahead in the Add sheet: spelling-tolerant matches from the bundled
 * list, the typed text as its own row, and rows that fit the space.
 */
class SuggestTests {

    private fun top(query: String): String? = Suggest.rank(query).firstOrNull()?.entry?.name

    @Test
    fun testTumAndTumericPutTurmericFirst() {
        assertEquals("Turmeric", top("tum"), "three letters allow no typo, so the known misspelling finds it")
        assertEquals("Turmeric", top("tumeric"))
        assertEquals("Turmeric", top("Tur"))
        assertNull(Suggest.rank("tumeric").firstOrNull()?.alias, "a misspelling is never shown")
    }

    @Test
    fun testTyposWordsAndOtherNamesFindTheRightEntry() {
        assertEquals("Ashwagandha", top("ashwaganda"))
        assertEquals("Ashwagandha", top("ashwagnadha"), "a swap of two letters is one typo")
        assertEquals("Vitamin D3", top("vit d"))
        assertEquals("Lion's Mane", top("lions mane"))
        assertEquals("Lion's Mane", top("lion"))
        assertEquals("CoQ10", top("coq10"))
        assertEquals("Omega-3", top("omega3"))
        assertEquals("Vitamin B12", top("b12"))
        assertEquals("Magnesium", top("magnisium"))
        assertEquals("Glucosamine", top("glucosomine"))
        assertEquals("Melatonin", top("Mélatonin"), "accents fold")
        assertEquals("L-Theanine", top("theanine"), "a later word matches too")

        val ozem = Suggest.rank("ozem").firstOrNull()
        assertEquals("Semaglutide", ozem?.entry?.name)
        assertEquals("Ozempic", ozem?.alias, "the brand shows faint after the generic name")
        assertEquals("Tirzepatide", Suggest.rank("mounj").firstOrNull()?.entry?.name)
        assertEquals("Mounjaro", Suggest.rank("mounj").firstOrNull()?.alias)
        assertEquals("Acetaminophen", top("paracetamol"))
        assertNull(Suggest.rank("vitamin d").firstOrNull()?.alias, "no alias hint when the name itself matches")
    }

    @Test
    fun testTheTypoBudgetGrowsWithLength() {
        assertEquals(listOf(0, 0, 0, 1, 1, 1, 1, 2, 2), (1..9).map { Suggest.typoBudget(it) })
        assertEquals(1, Suggest.prefixDistance("teh", "the", limit = 2), "a swap is one typo")
        assertEquals(1, Suggest.prefixDistance("magnesim", "magnesiumglycinate", limit = 1), "against any prefix of the name")
        assertEquals(2, Suggest.prefixDistance("zzqx", "zinc", limit = 1), "past the limit")

        val zinx = Suggest.match(Suggest.Folded("zinx"), Suggest.Folded("Zinc"), budget = 1)
        assertEquals(3, zinx?.first)
        assertEquals(1, zinx?.second)
        val xinc = Suggest.match(Suggest.Folded("xinc"), Suggest.Folded("Zinc"), budget = 1)
        assertEquals(2, xinc?.second, "a first-letter typo counts once against the budget and twice for ranking")
        assertNull(Suggest.match(Suggest.Folded("zic"), Suggest.Folded("Zinc"), budget = Suggest.typoBudget(3)), "no typo under four letters")
    }

    @Test
    fun testChipsAndWeightBreakTies() {
        assertEquals(listOf("Vitamin D3", "Vitamin C", "Vitamin B12", "Vitamin K2"), Suggest.rank("vitamin").map { it.entry.name })
        assertEquals("Magnesium", Suggest.rank("magnesium").firstOrNull()?.entry?.name)
        assertEquals(4, Suggest.rank("magnesium").size, "up to four matches")
        assertEquals("Fish Oil", Suggest.rank("oil").firstOrNull()?.entry?.name)
    }

    @Test
    fun testNothingMatchingLeavesOnlyTheTypedRow() {
        assertTrue(Suggest.rank("zzqx").isEmpty())
        val rows = Suggest.rows(Suggest.rank("zzqx"), literal = Suggest.literal("zzqx"), capacity = 5)
        assertEquals(listOf<SuggestRow>(SuggestRow.Literal("zzqx", owned = false)), rows)
        assertNull(Suggest.literal("turmeric"), "an exact catalog name is its own row")
        assertNull(Suggest.literal("   "))
        assertEquals("Ozempic", Suggest.literal(" Ozempic "), "a brand typed in full can be added as it is")
        assertTrue(Suggest.rank("").isEmpty(), "nothing shows while the field is empty")
        assertTrue(Suggest.rank(" - ").isEmpty())
    }

    @Test
    fun testOwnedItemsShowFaintAndCannotBePicked() {
        val owned = setOf(Catalog.lookupKey("Zinc"), Catalog.lookupKey("Grandma's Tonic"))
        val zinc = Suggest.rank("zin", owned = owned)
        assertEquals("Zinc", zinc.firstOrNull()?.entry?.name)
        assertEquals(true, zinc.firstOrNull()?.owned)
        val rows = Suggest.rows(zinc, literal = Suggest.literal("zin"), owned = owned, capacity = 5)
        assertFalse(rows[0].isEnabled)
        val pick = assertNotNull(Suggest.firstPick(rows))
        assertNotEquals("Zinc", pick.name, "Return skips what is already in the stack")

        val tonic = Suggest.rows(emptyList(), literal = Suggest.literal("grandma's tonic"), owned = owned, capacity = 5)
        assertEquals(listOf<SuggestRow>(SuggestRow.Literal("grandma's tonic", owned = true)), tonic)
        assertNull(Suggest.firstPick(tonic))
    }

    @Test
    fun testRowsFitTheSpaceWithTheTypedRowLast() {
        val matches = Suggest.rank("vitamin")
        val literal = Suggest.literal("vitamin")
        assertEquals("vitamin", literal)
        assertEquals(5, Suggest.rows(matches, literal = literal, capacity = 9).size, "four matches and the typed row")
        val three = Suggest.rows(matches, literal = literal, capacity = 3)
        assertEquals(listOf("Vitamin D3", "Vitamin C", "vitamin"), three.map { it.name })
        assertEquals(listOf("Vitamin D3"), Suggest.rows(matches, literal = literal, capacity = 1).map { it.name })
        assertTrue(Suggest.rows(matches, literal = literal, capacity = 0).isEmpty())
        assertEquals("Vitamin D3", Suggest.firstPick(three)?.name, "Return picks row 1")
    }

    @Test
    fun testWhatWasTypedIsMutedAndTheCompletionStandsOut() {
        fun s(text: String, typed: Boolean) = Suggest.Segment(text, typed)
        assertEquals(listOf(s("Tur", true), s("meric", false)), Suggest.segments("Turmeric", "tur"))
        assertEquals(
            listOf(s("Vit", true), s("amin ", false), s("D", true), s("3", false)),
            Suggest.segments("Vitamin D3", "vit d"),
        )
        assertEquals(listOf(s("Fish ", false), s("Oil", true)), Suggest.segments("Fish Oil", "oil"))
        assertEquals(listOf(s("Turmeric", false)), Suggest.segments("Turmeric", "tumeric"))
        assertEquals(listOf(s("Turmeric", false)), Suggest.segments("Turmeric", ""))
    }

    @Test
    fun testNoResearchPeptideIsEverSuggested() {
        for (term in listOf("retatrutide", "cagrisema", "bpc-157", "tb-500", "ipamorelin", "sermorelin", "semax", "epitalon")) {
            for (suggestion in Suggest.rank(term)) {
                assertFalse(Suggest.Folded(suggestion.entry.name).compact.contains(Suggest.Folded(term).compact), term)
            }
            assertNotNull(Suggest.literal(term), "$term can still be typed and added as it is")
        }
    }
}
