import Foundation

/// A quick-pick chip in the Add sheet.
struct Preset: Identifiable, Hashable, Sendable {
    let name: String
    let code: String
    var id: String { name }
}

/// One name the Add sheet knows: a chip, or a type-ahead suggestion. Names are ingredient-level and spelled as RxNorm
/// (medicines, US names, with the UK name as an alias) or the NIH supplement label database spells them, checked
/// offline. The app never looks a name up anywhere: the list ships in the binary.
struct CatalogEntry: Identifiable, Hashable, Sendable {
    /// The name the stack shows, in title case.
    let name: String
    /// The short tag on the widgets and the nudge. Unique across the catalog.
    let code: String
    /// Other names it goes by (a brand, a chemical name, a UK name), shown faint after the name when one matches.
    /// Brand names live only here, never as a chip label.
    let aliases: [String]
    /// Common misspellings: they find the entry but are never shown, and rank as one typo.
    let misspellings: [String]
    /// One of the quick-pick chips.
    let isChip: Bool
    /// Taken once a week on a set day (the injectable GLP-1s), so the Add sheet starts it on Weekly.
    let weekly: Bool
    /// How widely it is taken, 1 to 9: orders matches that are otherwise equal.
    let weight: UInt8
    var id: String { name }

    init(_ name: String, code: String? = nil, aliases: [String] = [], misspellings: [String] = [], chip: Bool = false,
         weekly: Bool = false, weight: UInt8 = 1) {
        self.name = name
        self.code = code ?? Catalog.derivedCode(for: name)
        self.aliases = aliases
        self.misspellings = misspellings
        self.isChip = chip
        self.weekly = weekly
        self.weight = weight
    }
}

enum Catalog {
    /// The chips, in the grid's order. Generic names only; Semaglutide and Tirzepatide start on Weekly (the daily tablet
    /// is Oral Semaglutide, in the medicines).
    private static let chips: [CatalogEntry] = [
        CatalogEntry("Vitamin D3", code: "VD3", aliases: ["Vitamin D", "Cholecalciferol"], chip: true, weight: 9),
        CatalogEntry("Fish Oil", code: "FSH", chip: true, weight: 9),
        CatalogEntry("Omega-3", code: "OM3", aliases: ["DHA", "EPA"], chip: true, weight: 8),
        CatalogEntry("Magnesium", code: "MAG", misspellings: ["magnisium", "magnesuim"], chip: true, weight: 9),
        CatalogEntry("Creatine", code: "CRE", aliases: ["Creatine Monohydrate"], chip: true, weight: 8),
        CatalogEntry("Multivitamin", code: "MLT", chip: true, weight: 8),
        CatalogEntry("Zinc", code: "ZNC", chip: true, weight: 7),
        CatalogEntry("Vitamin C", code: "VTC", aliases: ["Ascorbic Acid"], chip: true, weight: 8),
        CatalogEntry("Vitamin B12", code: "B12", aliases: ["Cobalamin", "Cyanocobalamin"], chip: true, weight: 7),
        CatalogEntry("Iron", code: "IRN", chip: true, weight: 7),
        CatalogEntry("Probiotic", code: "PRB", aliases: ["Lactobacillus", "Acidophilus"], chip: true, weight: 7),
        CatalogEntry("Ashwagandha", code: "ASH", aliases: ["KSM-66"], misspellings: ["ashwaganda", "ashwagandah"],
                     chip: true, weight: 7),
        CatalogEntry("Melatonin", code: "MEL", chip: true, weight: 7),
        CatalogEntry("Collagen", code: "COL", chip: true, weight: 6),
        CatalogEntry("Finasteride", code: "FIN", aliases: ["Propecia", "Proscar"], chip: true, weight: 6),
        CatalogEntry("Minoxidil", code: "MIN", aliases: ["Rogaine", "Regaine", "Loniten"], chip: true, weight: 6),
        CatalogEntry("Birth Control", code: "BCP",
                     aliases: ["The Pill", "Contraceptive Pill", "Oral Contraceptive", "Mini Pill", "Combined Pill",
                               "Yasmin", "Yaz", "Microgynon"],
                     chip: true, weight: 7),
        CatalogEntry("Metformin", code: "MET", aliases: ["Glucophage"], chip: true, weight: 6),
        CatalogEntry("Semaglutide", code: "SEM", aliases: ["Ozempic", "Wegovy"], chip: true, weekly: true, weight: 7),
        CatalogEntry("Tirzepatide", code: "TRZ", aliases: ["Mounjaro", "Zepbound"], chip: true, weekly: true, weight: 6),
        CatalogEntry("Electrolytes", code: "ELC", chip: true, weight: 6),
        CatalogEntry("Vitamin K2", code: "VK2", aliases: ["MK-7", "Menaquinone"], chip: true, weight: 6),
        CatalogEntry("Folate", code: "FOL", aliases: ["Vitamin B9"], chip: true, weight: 5),
        CatalogEntry("Calcium", code: "CAL", chip: true, weight: 5),
        CatalogEntry("Turmeric", code: "TUR", misspellings: ["tumeric", "termeric"], chip: true, weight: 6),
        CatalogEntry("CoQ10", code: "Q10", aliases: ["Coenzyme Q10", "Ubiquinone"], chip: true, weight: 5),
        CatalogEntry("L-Theanine", code: "LTH", chip: true, weight: 5),
    ]

    /// Vitamins, with the forms people buy.
    private static let vitamins: [CatalogEntry] = [
        CatalogEntry("Vitamin A", code: "VTA", aliases: ["Retinol"], weight: 2),
        CatalogEntry("Beta-Carotene"),
        CatalogEntry("Vitamin B1", code: "VB1", aliases: ["Thiamine"], weight: 2),
        CatalogEntry("Benfotiamine"),
        CatalogEntry("Vitamin B2", code: "VB2", aliases: ["Riboflavin"]),
        CatalogEntry("Vitamin B3", code: "VB3", aliases: ["Niacin"], weight: 2),
        CatalogEntry("Niacinamide", aliases: ["Nicotinamide"]),
        CatalogEntry("Vitamin B5", code: "VB5", aliases: ["Pantothenic Acid"]),
        CatalogEntry("Vitamin B6", code: "VB6", aliases: ["Pyridoxine", "P-5-P"], weight: 2),
        CatalogEntry("B Complex", code: "BCX", aliases: ["Vitamin B Complex"], weight: 4),
        CatalogEntry("Biotin", aliases: ["Vitamin B7"], weight: 4),
        CatalogEntry("Folic Acid", weight: 4),
        CatalogEntry("Methylfolate", code: "MTF", aliases: ["L-Methylfolate", "5-MTHF"], weight: 2),
        CatalogEntry("Methylcobalamin", code: "MCB", weight: 2),
        CatalogEntry("Vitamin D2", code: "VD2", aliases: ["Ergocalciferol"]),
        CatalogEntry("Vitamin E", code: "VTE", aliases: ["Tocopherol"], weight: 3),
        CatalogEntry("Choline"),
        CatalogEntry("Inositol", aliases: ["Myo-Inositol"], weight: 3),
        CatalogEntry("Prenatal Vitamin", code: "PNV", weight: 4),
    ]

    /// Minerals, with the forms people buy.
    private static let minerals: [CatalogEntry] = [
        CatalogEntry("Calcium Citrate", code: "CCT"),
        CatalogEntry("Calcium Carbonate", code: "CCB"),
        CatalogEntry("Magnesium Glycinate", code: "MGG", aliases: ["Magnesium Bisglycinate"], weight: 4),
        CatalogEntry("Magnesium Citrate", code: "MGC", weight: 3),
        CatalogEntry("Magnesium L-Threonate", code: "MGT", aliases: ["Magtein"], weight: 2),
        CatalogEntry("Magnesium Malate", code: "MGM"),
        CatalogEntry("Magnesium Oxide", code: "MGO"),
        CatalogEntry("Magnesium Taurate", code: "MGR"),
        CatalogEntry("Zinc Picolinate", code: "ZNP"),
        CatalogEntry("Zinc Gluconate", code: "ZNG"),
        CatalogEntry("Iron Bisglycinate", code: "IRB"),
        CatalogEntry("Ferrous Sulfate", code: "FES", aliases: ["Ferrous Sulphate"], weight: 2),
        CatalogEntry("Ferrous Fumarate", code: "FEF"),
        CatalogEntry("Potassium", code: "POT", weight: 2),
        CatalogEntry("Potassium Citrate", code: "PTC"),
        CatalogEntry("Selenium", weight: 2),
        CatalogEntry("Iodine"),
        CatalogEntry("Copper"),
        CatalogEntry("Chromium", aliases: ["Chromium Picolinate"]),
        CatalogEntry("Manganese"),
        CatalogEntry("Boron"),
    ]

    /// Herbs, roots and mushrooms.
    private static let botanicals: [CatalogEntry] = [
        CatalogEntry("Curcumin", weight: 2),
        CatalogEntry("Ginger"),
        CatalogEntry("Garlic"),
        CatalogEntry("Ginkgo Biloba", misspellings: ["gingko"], weight: 2),
        CatalogEntry("Panax Ginseng", aliases: ["Korean Ginseng", "Red Ginseng"], weight: 2),
        CatalogEntry("Rhodiola", aliases: ["Rhodiola Rosea"], weight: 2),
        CatalogEntry("Maca", weight: 2),
        CatalogEntry("Milk Thistle", aliases: ["Silymarin"], weight: 2),
        CatalogEntry("Saw Palmetto", weight: 2),
        CatalogEntry("Elderberry", aliases: ["Sambucus"], weight: 2),
        CatalogEntry("Echinacea"),
        CatalogEntry("Valerian Root", code: "VLR"),
        CatalogEntry("Chamomile"),
        CatalogEntry("Lemon Balm"),
        CatalogEntry("Passionflower"),
        CatalogEntry("St John's Wort", code: "SJW"),
        CatalogEntry("Holy Basil", aliases: ["Tulsi"]),
        CatalogEntry("Moringa"),
        CatalogEntry("Spirulina", weight: 2),
        CatalogEntry("Chlorella", code: "CLR"),
        CatalogEntry("Berberine", weight: 3),
        CatalogEntry("Black Seed Oil", aliases: ["Nigella Sativa", "Black Cumin"]),
        CatalogEntry("Cinnamon"),
        CatalogEntry("Green Tea Extract", aliases: ["EGCG"]),
        CatalogEntry("Fenugreek"),
        CatalogEntry("Tongkat Ali", weight: 2),
        CatalogEntry("Tribulus"),
        CatalogEntry("Shilajit", weight: 2),
        CatalogEntry("Lion's Mane", weight: 4),
        CatalogEntry("Reishi"),
        CatalogEntry("Cordyceps"),
        CatalogEntry("Chaga"),
        CatalogEntry("Turkey Tail"),
        CatalogEntry("Sea Moss", aliases: ["Irish Moss"], weight: 2),
        CatalogEntry("Psyllium Husk", code: "PSY", aliases: ["Ispaghula", "Metamucil", "Fybogel"], weight: 3),
        CatalogEntry("Aloe Vera"),
        CatalogEntry("Licorice Root", code: "LIC", aliases: ["Liquorice Root", "DGL"]),
        CatalogEntry("Dandelion Root"),
        CatalogEntry("Nettle", aliases: ["Stinging Nettle"]),
        CatalogEntry("Bacopa", code: "BAC", aliases: ["Bacopa Monnieri", "Brahmi"]),
        CatalogEntry("Gotu Kola"),
        CatalogEntry("Black Cohosh"),
        CatalogEntry("Vitex", aliases: ["Chasteberry", "Agnus Castus"]),
        CatalogEntry("Evening Primrose Oil", code: "EPO"),
        CatalogEntry("Olive Leaf"),
        CatalogEntry("Oregano Oil"),
        CatalogEntry("Quercetin"),
        CatalogEntry("Resveratrol"),
        CatalogEntry("Grape Seed Extract"),
        CatalogEntry("Bilberry"),
        CatalogEntry("Saffron"),
        CatalogEntry("Beetroot"),
        CatalogEntry("Tart Cherry"),
        CatalogEntry("Apple Cider Vinegar", aliases: ["ACV"], weight: 2),
        CatalogEntry("Cranberry"),
        CatalogEntry("Peppermint Oil"),
        CatalogEntry("Slippery Elm"),
        CatalogEntry("Boswellia"),
        CatalogEntry("Feverfew"),
        CatalogEntry("Hawthorn"),
        CatalogEntry("Pumpkin Seed Oil"),
        CatalogEntry("Astragalus", code: "ASG"),
        CatalogEntry("Schisandra"),
        CatalogEntry("Triphala"),
        CatalogEntry("Pine Bark Extract", aliases: ["Pycnogenol"]),
        CatalogEntry("Red Yeast Rice"),
    ]

    /// Oils, amino acids and everything else on a supplement shelf.
    private static let otherSupplements: [CatalogEntry] = [
        CatalogEntry("Krill Oil", weight: 2),
        CatalogEntry("Cod Liver Oil", weight: 2),
        CatalogEntry("Algae Oil", aliases: ["Algal Oil"]),
        CatalogEntry("Flaxseed Oil", code: "FXO", aliases: ["Flax Oil", "Linseed Oil"]),
        CatalogEntry("MCT Oil"),
        CatalogEntry("Whey Protein", aliases: ["Protein Powder"], weight: 3),
        CatalogEntry("BCAA", aliases: ["Branched-Chain Amino Acids"]),
        CatalogEntry("EAA", aliases: ["Essential Amino Acids"]),
        CatalogEntry("L-Glutamine", code: "LGL", aliases: ["Glutamine"]),
        CatalogEntry("L-Arginine", code: "LAR", aliases: ["Arginine"]),
        CatalogEntry("L-Citrulline", code: "LCT", aliases: ["Citrulline"]),
        CatalogEntry("L-Carnitine", code: "LCR", aliases: ["Carnitine"]),
        CatalogEntry("Acetyl-L-Carnitine", code: "ALC", aliases: ["ALCAR"]),
        CatalogEntry("L-Tyrosine", code: "LTY", aliases: ["Tyrosine"]),
        CatalogEntry("L-Lysine", code: "LLY", aliases: ["Lysine"]),
        CatalogEntry("Glycine"),
        CatalogEntry("Taurine", weight: 2),
        CatalogEntry("Beta-Alanine", code: "BAL"),
        CatalogEntry("HMB"),
        CatalogEntry("NAC", aliases: ["N-Acetyl Cysteine"], weight: 2),
        CatalogEntry("Glutathione"),
        CatalogEntry("Alpha Lipoic Acid", code: "ALA"),
        CatalogEntry("Ubiquinol"),
        CatalogEntry("PQQ"),
        CatalogEntry("NMN"),
        CatalogEntry("Nicotinamide Riboside", code: "NMR"),
        CatalogEntry("5-HTP", code: "HTP"),
        CatalogEntry("GABA"),
        CatalogEntry("Glucosamine", misspellings: ["glucosomine"], weight: 2),
        CatalogEntry("Chondroitin"),
        CatalogEntry("MSM"),
        CatalogEntry("Hyaluronic Acid"),
        CatalogEntry("Prebiotic Fiber", code: "PBF", aliases: ["Prebiotic Fibre", "Inulin"]),
        CatalogEntry("Digestive Enzymes"),
        CatalogEntry("Greens Powder", aliases: ["AG1", "Athletic Greens"], weight: 2),
        CatalogEntry("Caffeine"),
        CatalogEntry("Lecithin", code: "LEC"),
        CatalogEntry("Alpha-GPC", code: "AGP"),
        CatalogEntry("Citicoline", code: "CTC", aliases: ["CDP-Choline"]),
        CatalogEntry("Phosphatidylserine", code: "PTS"),
        CatalogEntry("DIM", aliases: ["Diindolylmethane"]),
        CatalogEntry("D-Mannose", code: "DMN"),
        CatalogEntry("Colostrum"),
        CatalogEntry("Beef Liver", aliases: ["Desiccated Liver"]),
        CatalogEntry("Lutein"),
        CatalogEntry("Zeaxanthin"),
        CatalogEntry("Astaxanthin", code: "ASX"),
        CatalogEntry("Lycopene"),
        CatalogEntry("Glucomannan", code: "GMN"),
        CatalogEntry("Sulforaphane", aliases: ["Broccoli Sprout"]),
        CatalogEntry("Saccharomyces Boulardii", code: "SBL", aliases: ["S. Boulardii"]),
        CatalogEntry("Lactase", code: "LAC", aliases: ["Lactaid"]),
        CatalogEntry("Nattokinase", code: "NTK"),
        CatalogEntry("Bromelain"),
        CatalogEntry("Betaine HCl", code: "BHC"),
    ]

    /// Common daily medicines, by generic name. Weekly-dosed medicines other than the GLP-1s are left out, so no
    /// default schedule could ever read as dosing advice.
    private static let medicines: [CatalogEntry] = [
        // Heart and blood pressure.
        CatalogEntry("Atorvastatin", aliases: ["Lipitor"], weight: 3),
        CatalogEntry("Rosuvastatin", code: "RSU", aliases: ["Crestor"], weight: 2),
        CatalogEntry("Simvastatin", aliases: ["Zocor"], weight: 2),
        CatalogEntry("Pravastatin", aliases: ["Pravachol"]),
        CatalogEntry("Ezetimibe", aliases: ["Zetia", "Ezetrol"]),
        CatalogEntry("Amlodipine", aliases: ["Norvasc", "Istin"], weight: 3),
        CatalogEntry("Lisinopril", aliases: ["Zestril", "Prinivil"], weight: 3),
        CatalogEntry("Ramipril", aliases: ["Altace", "Tritace"], weight: 2),
        CatalogEntry("Losartan", aliases: ["Cozaar"], weight: 2),
        CatalogEntry("Valsartan", aliases: ["Diovan"]),
        CatalogEntry("Candesartan", aliases: ["Atacand", "Amias"]),
        CatalogEntry("Irbesartan", code: "IRS", aliases: ["Avapro", "Aprovel"]),
        CatalogEntry("Metoprolol", aliases: ["Lopressor", "Toprol-XL"], weight: 2),
        CatalogEntry("Bisoprolol", code: "BIS", aliases: ["Zebeta", "Cardicor"]),
        CatalogEntry("Atenolol", aliases: ["Tenormin"]),
        CatalogEntry("Propranolol", aliases: ["Inderal"], weight: 2),
        CatalogEntry("Carvedilol", aliases: ["Coreg"]),
        CatalogEntry("Hydrochlorothiazide", code: "HCT", aliases: ["HCTZ"]),
        CatalogEntry("Furosemide", aliases: ["Lasix"]),
        CatalogEntry("Spironolactone", code: "SPN", aliases: ["Aldactone"], weight: 3),
        CatalogEntry("Doxazosin", aliases: ["Cardura"]),
        CatalogEntry("Aspirin", weight: 2),
        CatalogEntry("Clopidogrel", aliases: ["Plavix"]),
        CatalogEntry("Apixaban", aliases: ["Eliquis"]),
        CatalogEntry("Rivaroxaban", aliases: ["Xarelto"]),
        CatalogEntry("Warfarin", aliases: ["Coumadin"]),
        // Diabetes.
        // Semaglutide's tablet is taken once a day (the Rybelsus label; the Wegovy pill since December 2025), so it is
        // its own entry and starts on Daily, where the chip's injections start on Weekly.
        CatalogEntry("Oral Semaglutide", code: "OSM", aliases: ["Rybelsus", "Wegovy Pill"], weight: 3),
        CatalogEntry("Sitagliptin", aliases: ["Januvia"]),
        CatalogEntry("Empagliflozin", aliases: ["Jardiance"]),
        CatalogEntry("Dapagliflozin", aliases: ["Farxiga", "Forxiga"]),
        CatalogEntry("Gliclazide", code: "GLZ", aliases: ["Diamicron"]),
        CatalogEntry("Glipizide", aliases: ["Glucotrol"]),
        CatalogEntry("Glimepiride", aliases: ["Amaryl"]),
        CatalogEntry("Pioglitazone", aliases: ["Actos"]),
        CatalogEntry("Insulin Glargine", code: "IGL", aliases: ["Lantus", "Toujeo", "Basaglar"]),
        CatalogEntry("Insulin Lispro", code: "ILS", aliases: ["Humalog"]),
        CatalogEntry("Insulin Aspart", code: "IAS", aliases: ["NovoLog", "NovoRapid"]),
        CatalogEntry("Insulin Degludec", code: "IDG", aliases: ["Tresiba"]),
        // Thyroid and hormones.
        CatalogEntry("Levothyroxine", aliases: ["Synthroid", "Levoxyl", "Euthyrox", "Eltroxin"], weight: 4),
        CatalogEntry("Liothyronine", code: "LIO", aliases: ["Cytomel"]),
        CatalogEntry("Estradiol", aliases: ["Oestradiol", "Estrace", "Oestrogel"], weight: 2),
        CatalogEntry("Progesterone", aliases: ["Prometrium", "Utrogestan"], weight: 2),
        CatalogEntry("Testosterone", aliases: ["AndroGel", "Testogel"], weight: 2),
        CatalogEntry("Desogestrel", aliases: ["Cerazette", "Cerelle"]),
        CatalogEntry("Norethindrone", code: "NET", aliases: ["Norethisterone", "Camila", "Errin"]),
        CatalogEntry("Drospirenone", aliases: ["Slynd"]),
        CatalogEntry("Prednisolone", code: "PNL"),
        CatalogEntry("Prednisone"),
        CatalogEntry("Hydrocortisone", code: "HCS"),
        // Mood, sleep, focus and nerves.
        CatalogEntry("Sertraline", aliases: ["Zoloft", "Lustral"], weight: 3),
        CatalogEntry("Fluoxetine", aliases: ["Prozac"], weight: 2),
        CatalogEntry("Citalopram", aliases: ["Celexa", "Cipramil"], weight: 2),
        CatalogEntry("Escitalopram", aliases: ["Lexapro", "Cipralex"], weight: 3),
        CatalogEntry("Paroxetine", aliases: ["Paxil", "Seroxat"]),
        CatalogEntry("Venlafaxine", aliases: ["Effexor"]),
        CatalogEntry("Desvenlafaxine", aliases: ["Pristiq"]),
        CatalogEntry("Duloxetine", aliases: ["Cymbalta"]),
        CatalogEntry("Bupropion", aliases: ["Wellbutrin", "Zyban"], weight: 2),
        CatalogEntry("Mirtazapine", aliases: ["Remeron", "Zispin"]),
        CatalogEntry("Trazodone", code: "TZD"),
        CatalogEntry("Vortioxetine", aliases: ["Trintellix", "Brintellix"]),
        CatalogEntry("Amitriptyline"),
        CatalogEntry("Nortriptyline", aliases: ["Pamelor"]),
        CatalogEntry("Buspirone", code: "BUS", aliases: ["BuSpar"]),
        CatalogEntry("Lamotrigine", aliases: ["Lamictal"]),
        CatalogEntry("Quetiapine", aliases: ["Seroquel"]),
        CatalogEntry("Aripiprazole", aliases: ["Abilify"]),
        CatalogEntry("Olanzapine", aliases: ["Zyprexa"]),
        CatalogEntry("Risperidone", aliases: ["Risperdal"]),
        CatalogEntry("Lithium", code: "LIT", aliases: ["Lithobid", "Priadel"]),
        CatalogEntry("Hydroxyzine", code: "HXZ", aliases: ["Atarax"]),
        CatalogEntry("Pregabalin", code: "PGB", aliases: ["Lyrica"]),
        CatalogEntry("Gabapentin", aliases: ["Neurontin"]),
        CatalogEntry("Methylphenidate", code: "MPH", aliases: ["Ritalin", "Concerta"], weight: 2),
        CatalogEntry("Lisdexamfetamine", aliases: ["Vyvanse", "Elvanse"], weight: 2),
        CatalogEntry("Atomoxetine", aliases: ["Strattera"]),
        CatalogEntry("Guanfacine", aliases: ["Intuniv"]),
        CatalogEntry("Levetiracetam", code: "LEV", aliases: ["Keppra"]),
        CatalogEntry("Topiramate", aliases: ["Topamax"]),
        CatalogEntry("Naltrexone"),
        CatalogEntry("Varenicline", aliases: ["Chantix", "Champix"]),
        // Allergy and breathing.
        CatalogEntry("Cetirizine", aliases: ["Zyrtec"], weight: 3),
        CatalogEntry("Loratadine", aliases: ["Claritin", "Clarityn"], weight: 2),
        CatalogEntry("Fexofenadine", aliases: ["Allegra", "Telfast"], weight: 2),
        CatalogEntry("Levocetirizine", aliases: ["Xyzal"]),
        CatalogEntry("Desloratadine", aliases: ["Clarinex"]),
        CatalogEntry("Montelukast", aliases: ["Singulair"]),
        CatalogEntry("Fluticasone", aliases: ["Flonase", "Flixonase"]),
        CatalogEntry("Albuterol", aliases: ["Salbutamol", "Ventolin", "ProAir"]),
        // Stomach and gut.
        CatalogEntry("Omeprazole", aliases: ["Prilosec", "Losec"], weight: 3),
        CatalogEntry("Esomeprazole", aliases: ["Nexium"]),
        CatalogEntry("Lansoprazole", aliases: ["Prevacid", "Zoton"]),
        CatalogEntry("Pantoprazole", aliases: ["Protonix"]),
        CatalogEntry("Famotidine", aliases: ["Pepcid"]),
        CatalogEntry("Mesalamine", aliases: ["Mesalazine", "Asacol", "Lialda"]),
        // Pain and joints.
        CatalogEntry("Acetaminophen", aliases: ["Paracetamol", "Tylenol", "Panadol"], weight: 2),
        CatalogEntry("Ibuprofen", aliases: ["Advil", "Motrin", "Nurofen"], weight: 2),
        CatalogEntry("Naproxen", aliases: ["Aleve", "Naprosyn"]),
        CatalogEntry("Celecoxib", aliases: ["Celebrex"]),
        CatalogEntry("Allopurinol", aliases: ["Zyloprim"]),
        CatalogEntry("Hydroxychloroquine", code: "HCQ", aliases: ["Plaquenil"]),
        // Hair, skin and prostate.
        CatalogEntry("Dutasteride", aliases: ["Avodart"]),
        CatalogEntry("Tamsulosin", aliases: ["Flomax"]),
        CatalogEntry("Tadalafil", aliases: ["Cialis"]),
        CatalogEntry("Isotretinoin", aliases: ["Accutane", "Roaccutane"], weight: 2),
        CatalogEntry("Tretinoin", aliases: ["Retin-A"]),
        CatalogEntry("Adapalene", aliases: ["Differin"]),
        CatalogEntry("Doxycycline", weight: 2),
        CatalogEntry("Minocycline"),
        // Courses and suppression.
        CatalogEntry("Amoxicillin", aliases: ["Amoxil"]),
        CatalogEntry("Valacyclovir", aliases: ["Valaciclovir", "Valtrex"]),
    ]

    /// Every name the Add sheet suggests, chips first.
    static let entries: [CatalogEntry] = chips + vitamins + minerals + botanicals + otherSupplements + medicines

    /// The chip grid, in order.
    static let presets: [Preset] = chips.map { Preset(name: $0.name, code: $0.code) }

    /// A name folded for lookups: any case, any accents, trimmed.
    static func lookupKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Entries by name, then alias, then misspelling: the first one listed wins.
    private static let byName: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        for entry in entries { map[lookupKey(entry.name)] = map[lookupKey(entry.name)] ?? entry }
        return map
    }()

    private static let byOtherName: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        for entry in entries {
            for other in entry.aliases + entry.misspellings where map[lookupKey(other)] == nil {
                map[lookupKey(other)] = entry
            }
        }
        return map
    }()

    /// The entry with exactly this name, in any case.
    static func entry(named name: String) -> CatalogEntry? {
        byName[lookupKey(name)]
    }

    /// The entry a name, an alias or a misspelling stands for ("Mounjaro" is Tirzepatide).
    static func entry(matching name: String) -> CatalogEntry? {
        let key = lookupKey(name)
        return byName[key] ?? byOtherName[key]
    }

    private static func isCodeCharacter(_ c: Character) -> Bool {
        ("A"..."Z").contains(c) || ("0"..."9").contains(c)
    }

    /// Code tags are 1 to 4 characters, A-Z and 0-9.
    static func sanitizeCode(_ raw: String) -> String {
        String(raw.uppercased().filter(isCodeCharacter).prefix(4))
    }

    /// A short code for any name: the catalog's code for its name or one of its other names, else derived.
    static func code(for name: String) -> String {
        entry(matching: name)?.code ?? derivedCode(for: name)
    }

    /// Initials plus consonants: "Lion's Mane" is LMN, "Berberine" is BRB.
    static func derivedCode(for name: String) -> String {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { !isCodeCharacter($0) })
            .map(String.init)
        guard let first = words.first, let firstLetter = first.first else { return "ITM" }

        var result = String(firstLetter)
        if words.count >= 2 {
            for word in words.dropFirst().prefix(2) {
                if let c = word.first { result.append(c) }
            }
            if result.count < 3, let last = words.last {
                for c in last.dropFirst() where result.count < 3 && !"AEIOU".contains(c) { result.append(c) }
            }
        } else {
            let rest = Array(first.dropFirst())
            for c in rest where result.count < 3 && !"AEIOU".contains(c) { result.append(c) }
            for c in rest where result.count < 3 && "AEIOU".contains(c) { result.append(c) }
        }
        let code = sanitizeCode(result)
        return code.isEmpty ? "ITM" : code
    }
}
