package com.tombaxter.taken.core.catalog

import java.text.Normalizer
import java.util.Locale

/** A quick-pick chip in the Add sheet. */
data class Preset(val name: String, val code: String)

/**
 * One name the Add sheet knows: a chip, or a type-ahead suggestion. Names are ingredient-level and spelled as RxNorm
 * (medicines, US names, with the UK name as an alias) or the NIH supplement label database spells them. The app never
 * looks a name up anywhere: the list ships in the app. Ported from Shared/Catalog.swift, the 299 entries copied as data.
 */
data class CatalogEntry(
    /** The name the stack shows, in title case. */
    val name: String,
    /** The short tag on the widgets and the nudge. Unique across the catalog. */
    val code: String,
    /** Other names it goes by (a brand, a chemical name, a UK name), shown faint after the name when one matches. */
    val aliases: List<String>,
    /** Common misspellings: they find the entry but are never shown, and rank as one typo. */
    val misspellings: List<String>,
    /** One of the quick-pick chips. */
    val isChip: Boolean,
    /** Taken once a week on a set day (the injectable GLP-1s), so the Add sheet starts it on Weekly. */
    val weekly: Boolean,
    /** How widely it is taken, 1 to 9: orders matches that are otherwise equal. */
    val weight: Int,
)

@Suppress("FunctionName")
private fun CatalogEntry(
    name: String,
    code: String? = null,
    aliases: List<String> = emptyList(),
    misspellings: List<String> = emptyList(),
    chip: Boolean = false,
    weekly: Boolean = false,
    weight: Int = 1,
): CatalogEntry = CatalogEntry(
    name = name, code = code ?: CatalogCodes.derivedCode(name), aliases = aliases, misspellings = misspellings,
    isChip = chip, weekly = weekly, weight = weight,
)

/** The code rules, apart from the data so the data can use them while it is built. */
object CatalogCodes {
    private fun isCodeCharacter(c: Char): Boolean = c in 'A'..'Z' || c in '0'..'9'

    /** Code tags are 1 to 4 characters, A-Z and 0-9. */
    fun sanitizeCode(raw: String): String = raw.uppercase(Locale.ROOT).filter(::isCodeCharacter).take(4)

    /** Initials plus consonants: "Lion's Mane" is LMN, "Berberine" is BRB. */
    fun derivedCode(name: String): String {
        val words = name.trim().uppercase(Locale.ROOT).replace("'", "")
            .split(Regex("[^A-Z0-9]+")).filter { it.isNotEmpty() }
        val first = words.firstOrNull() ?: return "ITM"
        val result = StringBuilder().append(first.first())
        if (words.size >= 2) {
            for (word in words.drop(1).take(2)) result.append(word.first())
            if (result.length < 3) {
                for (c in words.last().drop(1)) if (result.length < 3 && c !in "AEIOU") result.append(c)
            }
        } else {
            val rest = first.drop(1)
            for (c in rest) if (result.length < 3 && c !in "AEIOU") result.append(c)
            for (c in rest) if (result.length < 3 && c in "AEIOU") result.append(c)
        }
        val code = sanitizeCode(result.toString())
        return code.ifEmpty { "ITM" }
    }
}

object Catalog {
    /**
     * The chips, in the grid's order. Generic names only; Semaglutide and Tirzepatide start on Weekly (the daily tablet is
     * Oral Semaglutide, in the medicines).
     */
    private val chips: List<CatalogEntry> = listOf(
        CatalogEntry("Vitamin D3", code = "VD3", aliases = listOf("Vitamin D", "Cholecalciferol"), chip = true, weight = 9),
        CatalogEntry("Fish Oil", code = "FSH", chip = true, weight = 9),
        CatalogEntry("Omega-3", code = "OM3", aliases = listOf("DHA", "EPA"), chip = true, weight = 8),
        CatalogEntry("Magnesium", code = "MAG", misspellings = listOf("magnisium", "magnesuim"), chip = true, weight = 9),
        CatalogEntry("Creatine", code = "CRE", aliases = listOf("Creatine Monohydrate"), chip = true, weight = 8),
        CatalogEntry("Multivitamin", code = "MLT", chip = true, weight = 8),
        CatalogEntry("Zinc", code = "ZNC", chip = true, weight = 7),
        CatalogEntry("Vitamin C", code = "VTC", aliases = listOf("Ascorbic Acid"), chip = true, weight = 8),
        CatalogEntry("Vitamin B12", code = "B12", aliases = listOf("Cobalamin", "Cyanocobalamin"), chip = true, weight = 7),
        CatalogEntry("Iron", code = "IRN", chip = true, weight = 7),
        CatalogEntry("Probiotic", code = "PRB", aliases = listOf("Lactobacillus", "Acidophilus"), chip = true, weight = 7),
        CatalogEntry("Ashwagandha", code = "ASH", aliases = listOf("KSM-66"), misspellings = listOf("ashwaganda", "ashwagandah"),
                     chip = true, weight = 7),
        CatalogEntry("Melatonin", code = "MEL", chip = true, weight = 7),
        CatalogEntry("Collagen", code = "COL", chip = true, weight = 6),
        CatalogEntry("Finasteride", code = "FIN", aliases = listOf("Propecia", "Proscar"), chip = true, weight = 6),
        CatalogEntry("Minoxidil", code = "MIN", aliases = listOf("Rogaine", "Regaine", "Loniten"), chip = true, weight = 6),
        CatalogEntry("Birth Control", code = "BCP",
                     aliases = listOf("The Pill", "Contraceptive Pill", "Oral Contraceptive", "Mini Pill", "Combined Pill",
                               "Yasmin", "Yaz", "Microgynon"),
                     chip = true, weight = 7),
        CatalogEntry("Metformin", code = "MET", aliases = listOf("Glucophage"), chip = true, weight = 6),
        CatalogEntry("Semaglutide", code = "SEM", aliases = listOf("Ozempic", "Wegovy"), chip = true, weekly = true, weight = 7),
        CatalogEntry("Tirzepatide", code = "TRZ", aliases = listOf("Mounjaro", "Zepbound"), chip = true, weekly = true, weight = 6),
        CatalogEntry("Electrolytes", code = "ELC", chip = true, weight = 6),
        CatalogEntry("Vitamin K2", code = "VK2", aliases = listOf("MK-7", "Menaquinone"), chip = true, weight = 6),
        CatalogEntry("Folate", code = "FOL", aliases = listOf("Vitamin B9"), chip = true, weight = 5),
        CatalogEntry("Calcium", code = "CAL", chip = true, weight = 5),
        CatalogEntry("Turmeric", code = "TUR", misspellings = listOf("tumeric", "termeric"), chip = true, weight = 6),
        CatalogEntry("CoQ10", code = "Q10", aliases = listOf("Coenzyme Q10", "Ubiquinone"), chip = true, weight = 5),
        CatalogEntry("L-Theanine", code = "LTH", chip = true, weight = 5),
    )

    private val vitamins: List<CatalogEntry> = listOf(
        CatalogEntry("Vitamin A", code = "VTA", aliases = listOf("Retinol"), weight = 2),
        CatalogEntry("Beta-Carotene"),
        CatalogEntry("Vitamin B1", code = "VB1", aliases = listOf("Thiamine"), weight = 2),
        CatalogEntry("Benfotiamine"),
        CatalogEntry("Vitamin B2", code = "VB2", aliases = listOf("Riboflavin")),
        CatalogEntry("Vitamin B3", code = "VB3", aliases = listOf("Niacin"), weight = 2),
        CatalogEntry("Niacinamide", aliases = listOf("Nicotinamide")),
        CatalogEntry("Vitamin B5", code = "VB5", aliases = listOf("Pantothenic Acid")),
        CatalogEntry("Vitamin B6", code = "VB6", aliases = listOf("Pyridoxine", "P-5-P"), weight = 2),
        CatalogEntry("B Complex", code = "BCX", aliases = listOf("Vitamin B Complex"), weight = 4),
        CatalogEntry("Biotin", aliases = listOf("Vitamin B7"), weight = 4),
        CatalogEntry("Folic Acid", weight = 4),
        CatalogEntry("Methylfolate", code = "MTF", aliases = listOf("L-Methylfolate", "5-MTHF"), weight = 2),
        CatalogEntry("Methylcobalamin", code = "MCB", weight = 2),
        CatalogEntry("Vitamin D2", code = "VD2", aliases = listOf("Ergocalciferol")),
        CatalogEntry("Vitamin E", code = "VTE", aliases = listOf("Tocopherol"), weight = 3),
        CatalogEntry("Choline"),
        CatalogEntry("Inositol", aliases = listOf("Myo-Inositol"), weight = 3),
        CatalogEntry("Prenatal Vitamin", code = "PNV", weight = 4),
    )

    private val minerals: List<CatalogEntry> = listOf(
        CatalogEntry("Calcium Citrate", code = "CCT"),
        CatalogEntry("Calcium Carbonate", code = "CCB"),
        CatalogEntry("Magnesium Glycinate", code = "MGG", aliases = listOf("Magnesium Bisglycinate"), weight = 4),
        CatalogEntry("Magnesium Citrate", code = "MGC", weight = 3),
        CatalogEntry("Magnesium L-Threonate", code = "MGT", aliases = listOf("Magtein"), weight = 2),
        CatalogEntry("Magnesium Malate", code = "MGM"),
        CatalogEntry("Magnesium Oxide", code = "MGO"),
        CatalogEntry("Magnesium Taurate", code = "MGR"),
        CatalogEntry("Zinc Picolinate", code = "ZNP"),
        CatalogEntry("Zinc Gluconate", code = "ZNG"),
        CatalogEntry("Iron Bisglycinate", code = "IRB"),
        CatalogEntry("Ferrous Sulfate", code = "FES", aliases = listOf("Ferrous Sulphate"), weight = 2),
        CatalogEntry("Ferrous Fumarate", code = "FEF"),
        CatalogEntry("Potassium", code = "POT", weight = 2),
        CatalogEntry("Potassium Citrate", code = "PTC"),
        CatalogEntry("Selenium", weight = 2),
        CatalogEntry("Iodine"),
        CatalogEntry("Copper"),
        CatalogEntry("Chromium", aliases = listOf("Chromium Picolinate")),
        CatalogEntry("Manganese"),
        CatalogEntry("Boron"),
    )

    private val botanicals: List<CatalogEntry> = listOf(
        CatalogEntry("Curcumin", weight = 2),
        CatalogEntry("Ginger"),
        CatalogEntry("Garlic"),
        CatalogEntry("Ginkgo Biloba", misspellings = listOf("gingko"), weight = 2),
        CatalogEntry("Panax Ginseng", aliases = listOf("Korean Ginseng", "Red Ginseng"), weight = 2),
        CatalogEntry("Rhodiola", aliases = listOf("Rhodiola Rosea"), weight = 2),
        CatalogEntry("Maca", weight = 2),
        CatalogEntry("Milk Thistle", aliases = listOf("Silymarin"), weight = 2),
        CatalogEntry("Saw Palmetto", weight = 2),
        CatalogEntry("Elderberry", aliases = listOf("Sambucus"), weight = 2),
        CatalogEntry("Echinacea"),
        CatalogEntry("Valerian Root", code = "VLR"),
        CatalogEntry("Chamomile"),
        CatalogEntry("Lemon Balm"),
        CatalogEntry("Passionflower"),
        CatalogEntry("St John's Wort", code = "SJW"),
        CatalogEntry("Holy Basil", aliases = listOf("Tulsi")),
        CatalogEntry("Moringa"),
        CatalogEntry("Spirulina", weight = 2),
        CatalogEntry("Chlorella", code = "CLR"),
        CatalogEntry("Berberine", weight = 3),
        CatalogEntry("Black Seed Oil", aliases = listOf("Nigella Sativa", "Black Cumin")),
        CatalogEntry("Cinnamon"),
        CatalogEntry("Green Tea Extract", aliases = listOf("EGCG")),
        CatalogEntry("Fenugreek"),
        CatalogEntry("Tongkat Ali", weight = 2),
        CatalogEntry("Tribulus"),
        CatalogEntry("Shilajit", weight = 2),
        CatalogEntry("Lion's Mane", weight = 4),
        CatalogEntry("Reishi"),
        CatalogEntry("Cordyceps"),
        CatalogEntry("Chaga"),
        CatalogEntry("Turkey Tail"),
        CatalogEntry("Sea Moss", aliases = listOf("Irish Moss"), weight = 2),
        CatalogEntry("Psyllium Husk", code = "PSY", aliases = listOf("Ispaghula", "Metamucil", "Fybogel"), weight = 3),
        CatalogEntry("Aloe Vera"),
        CatalogEntry("Licorice Root", code = "LIC", aliases = listOf("Liquorice Root", "DGL")),
        CatalogEntry("Dandelion Root"),
        CatalogEntry("Nettle", aliases = listOf("Stinging Nettle")),
        CatalogEntry("Bacopa", code = "BAC", aliases = listOf("Bacopa Monnieri", "Brahmi")),
        CatalogEntry("Gotu Kola"),
        CatalogEntry("Black Cohosh"),
        CatalogEntry("Vitex", aliases = listOf("Chasteberry", "Agnus Castus")),
        CatalogEntry("Evening Primrose Oil", code = "EPO"),
        CatalogEntry("Olive Leaf"),
        CatalogEntry("Oregano Oil"),
        CatalogEntry("Quercetin"),
        CatalogEntry("Resveratrol"),
        CatalogEntry("Grape Seed Extract"),
        CatalogEntry("Bilberry"),
        CatalogEntry("Saffron"),
        CatalogEntry("Beetroot"),
        CatalogEntry("Tart Cherry"),
        CatalogEntry("Apple Cider Vinegar", aliases = listOf("ACV"), weight = 2),
        CatalogEntry("Cranberry"),
        CatalogEntry("Peppermint Oil"),
        CatalogEntry("Slippery Elm"),
        CatalogEntry("Boswellia"),
        CatalogEntry("Feverfew"),
        CatalogEntry("Hawthorn"),
        CatalogEntry("Pumpkin Seed Oil"),
        CatalogEntry("Astragalus", code = "ASG"),
        CatalogEntry("Schisandra"),
        CatalogEntry("Triphala"),
        CatalogEntry("Pine Bark Extract", aliases = listOf("Pycnogenol")),
        CatalogEntry("Red Yeast Rice"),
    )

    private val otherSupplements: List<CatalogEntry> = listOf(
        CatalogEntry("Krill Oil", weight = 2),
        CatalogEntry("Cod Liver Oil", weight = 2),
        CatalogEntry("Algae Oil", aliases = listOf("Algal Oil")),
        CatalogEntry("Flaxseed Oil", code = "FXO", aliases = listOf("Flax Oil", "Linseed Oil")),
        CatalogEntry("MCT Oil"),
        CatalogEntry("Whey Protein", aliases = listOf("Protein Powder"), weight = 3),
        CatalogEntry("BCAA", aliases = listOf("Branched-Chain Amino Acids")),
        CatalogEntry("EAA", aliases = listOf("Essential Amino Acids")),
        CatalogEntry("L-Glutamine", code = "LGL", aliases = listOf("Glutamine")),
        CatalogEntry("L-Arginine", code = "LAR", aliases = listOf("Arginine")),
        CatalogEntry("L-Citrulline", code = "LCT", aliases = listOf("Citrulline")),
        CatalogEntry("L-Carnitine", code = "LCR", aliases = listOf("Carnitine")),
        CatalogEntry("Acetyl-L-Carnitine", code = "ALC", aliases = listOf("ALCAR")),
        CatalogEntry("L-Tyrosine", code = "LTY", aliases = listOf("Tyrosine")),
        CatalogEntry("L-Lysine", code = "LLY", aliases = listOf("Lysine")),
        CatalogEntry("Glycine"),
        CatalogEntry("Taurine", weight = 2),
        CatalogEntry("Beta-Alanine", code = "BAL"),
        CatalogEntry("HMB"),
        CatalogEntry("NAC", aliases = listOf("N-Acetyl Cysteine"), weight = 2),
        CatalogEntry("Glutathione"),
        CatalogEntry("Alpha Lipoic Acid", code = "ALA"),
        CatalogEntry("Ubiquinol"),
        CatalogEntry("PQQ"),
        CatalogEntry("NMN"),
        CatalogEntry("Nicotinamide Riboside", code = "NMR"),
        CatalogEntry("5-HTP", code = "HTP"),
        CatalogEntry("GABA"),
        CatalogEntry("Glucosamine", misspellings = listOf("glucosomine"), weight = 2),
        CatalogEntry("Chondroitin"),
        CatalogEntry("MSM"),
        CatalogEntry("Hyaluronic Acid"),
        CatalogEntry("Prebiotic Fiber", code = "PBF", aliases = listOf("Prebiotic Fibre", "Inulin")),
        CatalogEntry("Digestive Enzymes"),
        CatalogEntry("Greens Powder", aliases = listOf("AG1", "Athletic Greens"), weight = 2),
        CatalogEntry("Caffeine"),
        CatalogEntry("Lecithin", code = "LEC"),
        CatalogEntry("Alpha-GPC", code = "AGP"),
        CatalogEntry("Citicoline", code = "CTC", aliases = listOf("CDP-Choline")),
        CatalogEntry("Phosphatidylserine", code = "PTS"),
        CatalogEntry("DIM", aliases = listOf("Diindolylmethane")),
        CatalogEntry("D-Mannose", code = "DMN"),
        CatalogEntry("Colostrum"),
        CatalogEntry("Beef Liver", aliases = listOf("Desiccated Liver")),
        CatalogEntry("Lutein"),
        CatalogEntry("Zeaxanthin"),
        CatalogEntry("Astaxanthin", code = "ASX"),
        CatalogEntry("Lycopene"),
        CatalogEntry("Glucomannan", code = "GMN"),
        CatalogEntry("Sulforaphane", aliases = listOf("Broccoli Sprout")),
        CatalogEntry("Saccharomyces Boulardii", code = "SBL", aliases = listOf("S. Boulardii")),
        CatalogEntry("Lactase", code = "LAC", aliases = listOf("Lactaid")),
        CatalogEntry("Nattokinase", code = "NTK"),
        CatalogEntry("Bromelain"),
        CatalogEntry("Betaine HCl", code = "BHC"),
    )

    private val medicines: List<CatalogEntry> = listOf(
        // Heart and blood pressure.
        CatalogEntry("Atorvastatin", aliases = listOf("Lipitor"), weight = 3),
        CatalogEntry("Rosuvastatin", code = "RSU", aliases = listOf("Crestor"), weight = 2),
        CatalogEntry("Simvastatin", aliases = listOf("Zocor"), weight = 2),
        CatalogEntry("Pravastatin", aliases = listOf("Pravachol")),
        CatalogEntry("Ezetimibe", aliases = listOf("Zetia", "Ezetrol")),
        CatalogEntry("Amlodipine", aliases = listOf("Norvasc", "Istin"), weight = 3),
        CatalogEntry("Lisinopril", aliases = listOf("Zestril", "Prinivil"), weight = 3),
        CatalogEntry("Ramipril", aliases = listOf("Altace", "Tritace"), weight = 2),
        CatalogEntry("Losartan", aliases = listOf("Cozaar"), weight = 2),
        CatalogEntry("Valsartan", aliases = listOf("Diovan")),
        CatalogEntry("Candesartan", aliases = listOf("Atacand", "Amias")),
        CatalogEntry("Irbesartan", code = "IRS", aliases = listOf("Avapro", "Aprovel")),
        CatalogEntry("Metoprolol", aliases = listOf("Lopressor", "Toprol-XL"), weight = 2),
        CatalogEntry("Bisoprolol", code = "BIS", aliases = listOf("Zebeta", "Cardicor")),
        CatalogEntry("Atenolol", aliases = listOf("Tenormin")),
        CatalogEntry("Propranolol", aliases = listOf("Inderal"), weight = 2),
        CatalogEntry("Carvedilol", aliases = listOf("Coreg")),
        CatalogEntry("Hydrochlorothiazide", code = "HCT", aliases = listOf("HCTZ")),
        CatalogEntry("Furosemide", aliases = listOf("Lasix")),
        CatalogEntry("Spironolactone", code = "SPN", aliases = listOf("Aldactone"), weight = 3),
        CatalogEntry("Doxazosin", aliases = listOf("Cardura")),
        CatalogEntry("Aspirin", weight = 2),
        CatalogEntry("Clopidogrel", aliases = listOf("Plavix")),
        CatalogEntry("Apixaban", aliases = listOf("Eliquis")),
        CatalogEntry("Rivaroxaban", aliases = listOf("Xarelto")),
        CatalogEntry("Warfarin", aliases = listOf("Coumadin")),
        // Diabetes.
        // Semaglutide's tablet is taken once a day (the Rybelsus label; the Wegovy pill since December 2025), so it is
        // its own entry and starts on Daily, where the chip's injections start on Weekly.
        CatalogEntry("Oral Semaglutide", code = "OSM", aliases = listOf("Rybelsus", "Wegovy Pill"), weight = 3),
        CatalogEntry("Sitagliptin", aliases = listOf("Januvia")),
        CatalogEntry("Empagliflozin", aliases = listOf("Jardiance")),
        CatalogEntry("Dapagliflozin", aliases = listOf("Farxiga", "Forxiga")),
        CatalogEntry("Gliclazide", code = "GLZ", aliases = listOf("Diamicron")),
        CatalogEntry("Glipizide", aliases = listOf("Glucotrol")),
        CatalogEntry("Glimepiride", aliases = listOf("Amaryl")),
        CatalogEntry("Pioglitazone", aliases = listOf("Actos")),
        CatalogEntry("Insulin Glargine", code = "IGL", aliases = listOf("Lantus", "Toujeo", "Basaglar")),
        CatalogEntry("Insulin Lispro", code = "ILS", aliases = listOf("Humalog")),
        CatalogEntry("Insulin Aspart", code = "IAS", aliases = listOf("NovoLog", "NovoRapid")),
        CatalogEntry("Insulin Degludec", code = "IDG", aliases = listOf("Tresiba")),
        // Thyroid and hormones.
        CatalogEntry("Levothyroxine", aliases = listOf("Synthroid", "Levoxyl", "Euthyrox", "Eltroxin"), weight = 4),
        CatalogEntry("Liothyronine", code = "LIO", aliases = listOf("Cytomel")),
        CatalogEntry("Estradiol", aliases = listOf("Oestradiol", "Estrace", "Oestrogel"), weight = 2),
        CatalogEntry("Progesterone", aliases = listOf("Prometrium", "Utrogestan"), weight = 2),
        CatalogEntry("Testosterone", aliases = listOf("AndroGel", "Testogel"), weight = 2),
        CatalogEntry("Desogestrel", aliases = listOf("Cerazette", "Cerelle")),
        CatalogEntry("Norethindrone", code = "NET", aliases = listOf("Norethisterone", "Camila", "Errin")),
        CatalogEntry("Drospirenone", aliases = listOf("Slynd")),
        CatalogEntry("Prednisolone", code = "PNL"),
        CatalogEntry("Prednisone"),
        CatalogEntry("Hydrocortisone", code = "HCS"),
        // Mood, sleep, focus and nerves.
        CatalogEntry("Sertraline", aliases = listOf("Zoloft", "Lustral"), weight = 3),
        CatalogEntry("Fluoxetine", aliases = listOf("Prozac"), weight = 2),
        CatalogEntry("Citalopram", aliases = listOf("Celexa", "Cipramil"), weight = 2),
        CatalogEntry("Escitalopram", aliases = listOf("Lexapro", "Cipralex"), weight = 3),
        CatalogEntry("Paroxetine", aliases = listOf("Paxil", "Seroxat")),
        CatalogEntry("Venlafaxine", aliases = listOf("Effexor")),
        CatalogEntry("Desvenlafaxine", aliases = listOf("Pristiq")),
        CatalogEntry("Duloxetine", aliases = listOf("Cymbalta")),
        CatalogEntry("Bupropion", aliases = listOf("Wellbutrin", "Zyban"), weight = 2),
        CatalogEntry("Mirtazapine", aliases = listOf("Remeron", "Zispin")),
        CatalogEntry("Trazodone", code = "TZD"),
        CatalogEntry("Vortioxetine", aliases = listOf("Trintellix", "Brintellix")),
        CatalogEntry("Amitriptyline"),
        CatalogEntry("Nortriptyline", aliases = listOf("Pamelor")),
        CatalogEntry("Buspirone", code = "BUS", aliases = listOf("BuSpar")),
        CatalogEntry("Lamotrigine", aliases = listOf("Lamictal")),
        CatalogEntry("Quetiapine", aliases = listOf("Seroquel")),
        CatalogEntry("Aripiprazole", aliases = listOf("Abilify")),
        CatalogEntry("Olanzapine", aliases = listOf("Zyprexa")),
        CatalogEntry("Risperidone", aliases = listOf("Risperdal")),
        CatalogEntry("Lithium", code = "LIT", aliases = listOf("Lithobid", "Priadel")),
        CatalogEntry("Hydroxyzine", code = "HXZ", aliases = listOf("Atarax")),
        CatalogEntry("Pregabalin", code = "PGB", aliases = listOf("Lyrica")),
        CatalogEntry("Gabapentin", aliases = listOf("Neurontin")),
        CatalogEntry("Methylphenidate", code = "MPH", aliases = listOf("Ritalin", "Concerta"), weight = 2),
        CatalogEntry("Lisdexamfetamine", aliases = listOf("Vyvanse", "Elvanse"), weight = 2),
        CatalogEntry("Atomoxetine", aliases = listOf("Strattera")),
        CatalogEntry("Guanfacine", aliases = listOf("Intuniv")),
        CatalogEntry("Levetiracetam", code = "LEV", aliases = listOf("Keppra")),
        CatalogEntry("Topiramate", aliases = listOf("Topamax")),
        CatalogEntry("Naltrexone"),
        CatalogEntry("Varenicline", aliases = listOf("Chantix", "Champix")),
        // Allergy and breathing.
        CatalogEntry("Cetirizine", aliases = listOf("Zyrtec"), weight = 3),
        CatalogEntry("Loratadine", aliases = listOf("Claritin", "Clarityn"), weight = 2),
        CatalogEntry("Fexofenadine", aliases = listOf("Allegra", "Telfast"), weight = 2),
        CatalogEntry("Levocetirizine", aliases = listOf("Xyzal")),
        CatalogEntry("Desloratadine", aliases = listOf("Clarinex")),
        CatalogEntry("Montelukast", aliases = listOf("Singulair")),
        CatalogEntry("Fluticasone", aliases = listOf("Flonase", "Flixonase")),
        CatalogEntry("Albuterol", aliases = listOf("Salbutamol", "Ventolin", "ProAir")),
        // Stomach and gut.
        CatalogEntry("Omeprazole", aliases = listOf("Prilosec", "Losec"), weight = 3),
        CatalogEntry("Esomeprazole", aliases = listOf("Nexium")),
        CatalogEntry("Lansoprazole", aliases = listOf("Prevacid", "Zoton")),
        CatalogEntry("Pantoprazole", aliases = listOf("Protonix")),
        CatalogEntry("Famotidine", aliases = listOf("Pepcid")),
        CatalogEntry("Mesalamine", aliases = listOf("Mesalazine", "Asacol", "Lialda")),
        // Pain and joints.
        CatalogEntry("Acetaminophen", aliases = listOf("Paracetamol", "Tylenol", "Panadol"), weight = 2),
        CatalogEntry("Ibuprofen", aliases = listOf("Advil", "Motrin", "Nurofen"), weight = 2),
        CatalogEntry("Naproxen", aliases = listOf("Aleve", "Naprosyn")),
        CatalogEntry("Celecoxib", aliases = listOf("Celebrex")),
        CatalogEntry("Allopurinol", aliases = listOf("Zyloprim")),
        CatalogEntry("Hydroxychloroquine", code = "HCQ", aliases = listOf("Plaquenil")),
        // Hair, skin and prostate.
        CatalogEntry("Dutasteride", aliases = listOf("Avodart")),
        CatalogEntry("Tamsulosin", aliases = listOf("Flomax")),
        CatalogEntry("Tadalafil", aliases = listOf("Cialis")),
        CatalogEntry("Isotretinoin", aliases = listOf("Accutane", "Roaccutane"), weight = 2),
        CatalogEntry("Tretinoin", aliases = listOf("Retin-A")),
        CatalogEntry("Adapalene", aliases = listOf("Differin")),
        CatalogEntry("Doxycycline", weight = 2),
        CatalogEntry("Minocycline"),
        // Courses and suppression.
        CatalogEntry("Amoxicillin", aliases = listOf("Amoxil")),
        CatalogEntry("Valacyclovir", aliases = listOf("Valaciclovir", "Valtrex")),
    )
    /** Every name the Add sheet suggests, chips first. */
    val entries: List<CatalogEntry> = chips + vitamins + minerals + botanicals + otherSupplements + medicines

    /** The chip grid, in order. */
    val presets: List<Preset> = chips.map { Preset(it.name, it.code) }

    /** A name folded for lookups: any case, any accents, any width, trimmed. */
    fun lookupKey(name: String): String = fold(name.trim())

    /** Case, accents and width folded, as Swift's `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])`. */
    fun fold(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFKD).replace(marks, "").lowercase(Locale.ROOT)

    private val marks = Regex("\\p{M}+")

    /** Entries by name, then alias, then misspelling: the first one listed wins. */
    private val byName: Map<String, CatalogEntry> = LinkedHashMap<String, CatalogEntry>().also { map ->
        for (entry in entries) map.putIfAbsent(lookupKey(entry.name), entry)
    }

    private val byOtherName: Map<String, CatalogEntry> = LinkedHashMap<String, CatalogEntry>().also { map ->
        for (entry in entries) {
            for (other in entry.aliases + entry.misspellings) map.putIfAbsent(lookupKey(other), entry)
        }
    }

    /** The entry with exactly this name, in any case. */
    fun entryNamed(name: String): CatalogEntry? = byName[lookupKey(name)]

    /** The entry a name, an alias or a misspelling stands for ("Mounjaro" is Tirzepatide). */
    fun entryMatching(name: String): CatalogEntry? {
        val key = lookupKey(name)
        return byName[key] ?: byOtherName[key]
    }

    /** Code tags are 1 to 4 characters, A-Z and 0-9. */
    fun sanitizeCode(raw: String): String = CatalogCodes.sanitizeCode(raw)

    /** A short code for any name: the catalog's code for its name or one of its other names, else derived. */
    fun code(name: String): String = entryMatching(name)?.code ?: derivedCode(name)

    /** Initials plus consonants: "Lion's Mane" is LMN, "Berberine" is BRB. */
    fun derivedCode(name: String): String = CatalogCodes.derivedCode(name)
}
