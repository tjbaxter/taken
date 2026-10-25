package com.tombaxter.taken.core

import com.tombaxter.taken.core.catalog.AddPlan
import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.catalog.FrequencyChoice
import com.tombaxter.taken.core.catalog.Preset
import com.tombaxter.taken.core.catalog.Suggest
import com.tombaxter.taken.core.model.Frequency
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ported from TakenTests/CatalogTests.swift: the chips, the type-ahead names, their codes, and what is left out. */
class CatalogTests {

    @Test
    fun testTheListIsAboutThreeHundredIngredientLevelNames() {
        assertTrue(Catalog.entries.size in 250..300, "${Catalog.entries.size} names")
        assertEquals(299, Catalog.entries.size, "the iPhone's 299, copied as data")
        for (entry in Catalog.entries) {
            assertEquals(entry.name.trim(), entry.name, entry.name)
            assertFalse(entry.name.contains("  "), entry.name)
            val first = entry.name.first()
            assertTrue(first.isUpperCase() || first.isDigit(), "title case: ${entry.name}")
        }
    }

    @Test
    fun testNamesAndCodesAreUniqueAndChipCodesAreThreeCharacters() {
        val names = Catalog.entries.map { Catalog.lookupKey(it.name) }
        assertEquals(names.size, names.toSet().size, "names are unique in any case")
        val codes = Catalog.entries.map { it.code }
        assertEquals(codes.size, codes.toSet().size, "codes are unique: ${codes.groupBy { it }.filter { it.value.size > 1 }.keys}")
        for (entry in Catalog.entries) {
            assertEquals(entry.code, Catalog.sanitizeCode(entry.code), "${entry.name}: A-Z and 0-9")
            assertTrue(entry.code.length in 1..4, entry.name)
        }
        for (preset in Catalog.presets) assertEquals(3, preset.code.length, preset.name)
    }

    @Test
    fun testTheChipGridGainsBirthControlAndTheTwoGLP1s() {
        val names = Catalog.presets.map { it.name }
        assertEquals(27, names.size, "27 chips plus + CUSTOM")
        assertEquals(
            listOf("Finasteride", "Minoxidil", "Birth Control", "Metformin", "Semaglutide", "Tirzepatide", "Electrolytes"),
            names.subList(14, 21),
        )
        assertEquals(Catalog.entries.filter { it.isChip }.map { Preset(it.name, it.code) }, Catalog.presets, "the grid is the chip entries, in order")
        for (name in listOf(
            "Vitamin D3", "Fish Oil", "Omega-3", "Magnesium", "Creatine", "Multivitamin", "Zinc", "Vitamin C", "Vitamin B12",
            "Iron", "Probiotic", "Ashwagandha", "Melatonin", "Collagen", "Finasteride", "Minoxidil", "Metformin", "Electrolytes",
            "Vitamin K2", "Folate", "Calcium", "Turmeric", "CoQ10", "L-Theanine",
        )) {
            assertTrue(names.contains(name), name)
        }
        assertEquals("SEM", Catalog.code("Semaglutide"))
        assertEquals("TRZ", Catalog.code("Tirzepatide"))
        assertEquals("BCP", Catalog.code("Birth control"))
        assertEquals("VD3", Catalog.code("Vitamin D3"))
    }

    @Test
    fun testOnlyTheInjectableGLP1sStartWeekly() {
        assertEquals(listOf("Semaglutide", "Tirzepatide"), Catalog.entries.filter { it.weekly }.map { it.name })
        // Rybelsus and the Wegovy pill are once-daily tablets: typed or picked, they start on Daily.
        assertEquals("Oral Semaglutide", Catalog.entryMatching("Rybelsus")?.name)
        assertEquals("Oral Semaglutide", Catalog.entryMatching("wegovy pill")?.name)
        assertEquals("OSM", Catalog.code("Rybelsus"))
        for (name in listOf("Rybelsus", "rybelsus ", "Oral Semaglutide", "Wegovy Pill")) {
            assertEquals(FrequencyChoice.DAILY, AddPlan.defaultChoice(name), name)
        }
        for (name in listOf("Semaglutide", "Ozempic", "Wegovy", "Tirzepatide", "Mounjaro", "Zepbound")) {
            assertEquals(FrequencyChoice.WEEKLY, AddPlan.defaultChoice(name), name)
        }
        val picked = Suggest.rank("rybelsus").firstOrNull()
        assertEquals("Oral Semaglutide", picked?.entry?.name)
        assertEquals("Rybelsus", picked?.alias)
        val drafts = AddPlan.drafts(emptyList(), listOf(picked?.entry?.name ?: ""), emptyMap(), emptyMap(), weekday = 5)
        assertEquals(listOf<Frequency>(Frequency.Daily(1)), drafts.map { it.frequency }, "the Rybelsus suggestion adds a daily item")
        val wegovy = Suggest.rank("wegovy").map { it.entry.name }
        assertTrue(
            wegovy.contains("Semaglutide") && wegovy.contains("Oral Semaglutide"),
            "Wegovy shows the injection and the pill, so the person picks which: $wegovy",
        )
    }

    @Test
    fun testAliasesFindTheirEntryAndBrandsAreNeverChipLabels() {
        assertEquals("Tirzepatide", Catalog.entryMatching("Mounjaro")?.name)
        assertEquals("Semaglutide", Catalog.entryMatching(" ozempic ")?.name)
        assertEquals("Acetaminophen", Catalog.entryMatching("Paracetamol")?.name)
        assertEquals("Turmeric", Catalog.entryMatching("tumeric")?.name, "a misspelling finds it too")
        assertNull(Catalog.entryNamed("Mounjaro"), "a brand is never a name")
        assertEquals("TRZ", Catalog.code("Mounjaro"))
        assertEquals("TRZ", Catalog.code("Zepbound"))
        assertEquals("SEM", Catalog.code("Wegovy"))

        val names = Catalog.entries.map { Catalog.lookupKey(it.name) }.toSet()
        val others = HashMap<String, String>()
        for (entry in Catalog.entries) {
            for (other in entry.aliases + entry.misspellings) {
                val key = Catalog.lookupKey(other)
                assertFalse(names.contains(key), "$other is another entry's name")
                assertNull(others[key], "$other is an alias of ${others[key] ?: ""} and ${entry.name}")
                others[key] = entry.name
            }
        }
        val brands = listOf("ozempic", "wegovy", "rybelsus", "mounjaro", "zepbound", "propecia", "rogaine", "glucophage")
        for (preset in Catalog.presets) assertFalse(brands.contains(Catalog.lookupKey(preset.name)), preset.name)
    }

    /** None is approved; typing one still works through the + Add row. */
    @Test
    fun testNoResearchPeptideOrUnapprovedGLP1IsListed() {
        val banned = listOf(
            "retatrutide", "cagrisema", "cagrilintide", "bpc", "tb500", "ghkcu", "cjc1295", "ipamorelin", "motsc", "semax",
            "epitalon", "epithalon", "sermorelin", "peptide",
        )
        for (entry in Catalog.entries) {
            for (text in listOf(entry.name) + entry.aliases + entry.misspellings) {
                // Letters and digits only, so "BPC-157" and "TB 500" are caught however they are written.
                val folded = Catalog.lookupKey(text).filter { it.isLetterOrDigit() }
                for (term in banned) assertFalse(folded.contains(term), "$text in ${entry.name}")
            }
        }
    }

    @Test
    fun testEveryNameKeepsTheCopyRules() {
        for (entry in Catalog.entries) {
            for (text in listOf(entry.name) + entry.aliases) assertCopyRules(text)
        }
    }

    @Test
    fun testCodesForNamesTheCatalogDoesNotKnowAreDerivedAsBefore() {
        assertEquals("LMN", Catalog.code("Lion's Mane"))
        assertEquals("BRB", Catalog.code("Berberine"))
        assertEquals("GTN", Catalog.code("Grandma's Tonic"))
        assertEquals("ITM", Catalog.code("   "))
        assertEquals("MGL", Catalog.derivedCode("Magnesium Glycinate"), "derived, but the entry has its own")
        assertEquals("MGG", Catalog.code("Magnesium Glycinate"))
    }
}
